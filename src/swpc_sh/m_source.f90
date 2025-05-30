#include "../shared/m_debug.h"
module m_source

    !! seismic source radiation
    !!
    !! Copyright 2013-2025 Takuto Maeda. All rights reserved. This project is released under the MIT license.

    use iso_fortran_env, only: error_unit
    use m_std
    use m_debug
    use m_global
    use m_fdtool
    use m_pwatch
    use m_readini
    use m_geomap
    use mpi

    implicit none
    private
    save

    public :: source__setup
    public :: source__stressglut
    public :: source__bodyforce

    character(16)         :: stftype                                        !< type of source time function: used in u_source
    integer               :: nsrc                                           !< source grid number inside the node
    integer               :: n_stfprm                                       !< number of parameters for moment-rate function
    real(SP), allocatable :: srcprm(:, :)                                   !< control paramater for moment-rate function at grids
    real(SP), allocatable :: sx(:), sz(:)                                   !< source location in distance scale
    integer, allocatable :: isrc(:), ksrc(:)                                !< source grid location voxel
    real(MP), allocatable :: myz(:), mxy(:)                                 !< moment rate
    real(MP), allocatable :: mo(:)                                          !< moment at grids
    real(MP), allocatable :: fy(:)                                          !< body force magnitude at grids
    real(SP)              :: dt_dxz
    character(4)          :: sdep_fit                                       !< 'bd0', 'bd1', ..., 'bd9'
    logical :: earth_flattening

contains

    subroutine source__setup(io_prm)

        !! read source grid and allocates memory for source grid and time-related parameters
        !! also pre-calculate common variables for stress glut source

        integer, intent(in) :: io_prm

        integer :: nn, i, k
        integer :: nsrc_g
        real(SP), allocatable :: myz_g(:), mxy_g(:), mo_g(:), fy_g(:)
        real(SP), allocatable :: sx_g(:), sz_g(:)
        integer, allocatable :: is_g(:), ks_g(:)
        logical, allocatable :: inside(:)
        real(SP), allocatable :: srcprm_g(:, :)
        character(99) :: fn_stf
        character(6)  :: stf_format
        integer :: io
        character(3) :: sdep0
        character :: sdep1

        call pwatch__on("source__setup")

        !! plane wave mode
        call readini(io_prm, 'pw_mode', pw_mode, .false.)
        if (pw_mode) then
            if (.not. benchmark_mode) then !! neglect pw_mode for benchmark
                call pw_setup(io_prm)
                nsrc = 0        !! no regular source grid for plane wave mode
                M0 = 1.0 / UC   !! Fictitious scalar moment for output
                call pwatch__off("source__setup")
                return
            end if
        end if

        !! body-force mode?
        call readini(io_prm, 'bf_mode', bf_mode, .false.)

        !! obtain number of source grid points and number of parameters for specifying soruce time functions
        call readini(io_prm, 'fn_stf', fn_stf, '')
        call readini(io_prm, 'stftype', stftype, 'boxcar')
        call readini(io_prm, 'stf_format', stf_format, 'xym0ij')
        call readini(io_prm, 'sdep_fit', sdep_fit, 'asis')

        call readini(io_prm, 'earth_flattening', earth_flattening, .false.)

        if (trim(adjustl(stftype)) == 'scosine') stftype = 'cosine'  !! backward compatibility

        select case (trim(stftype))
        case ('boxcar'); n_stfprm = 2
        case ('triangle'); n_stfprm = 2
        case ('herrmann'); n_stfprm = 2
        case ('kupper'); n_stfprm = 2
        case ('cosine'); n_stfprm = 2
        case ('texp'); n_stfprm = 2
        end select

        !! fixed source parameter for benchmarking: no source grid file used
        if (benchmark_mode) then
            nsrc_g = 1
            stftype = 'kupper'
            n_stfprm = 2
            bf_mode = .false.
        else
            !! count source-grid file
            open (newunit=io, file=trim(fn_stf), action='read', status='old')
            call std__countline(io, nsrc_g, "#")  ! exclude comment line which start by "#"
            close (io)
        end if

        !! temporal memory allocation, read all grids
        allocate (is_g(nsrc_g), ks_g(nsrc_g))
        allocate (srcprm_g(n_stfprm, nsrc_g))
        allocate (sx_g(nsrc_g), sz_g(nsrc_g))
        allocate (inside(nsrc_g))
        inside(1:nsrc_g) = .false.
        if (bf_mode) then

            allocate (fy_g(nsrc_g))

            call source__grid_bodyforce(fn_stf, stf_format, nsrc_g, n_stfprm, sx_g, sz_g, fy_g, srcprm_g)

        else
            allocate (mo_g(nsrc_g), myz_g(nsrc_g), mxy_g(nsrc_g))

            !! fixed source parameter for benchmarking
            if (benchmark_mode) then
                sx_g(1) = 0.0
                sz_g(1) = 5.0
                mo_g(1) = 1e15
                myz_g(1) = 1.0
                mxy_g(1) = 0.0
                srcprm_g(1, 1) = 0.1
                srcprm_g(2, 1) = 2.0
            else

                !! request all source grid information ( from user-defined routine )
                call source__grid_moment(fn_stf, stf_format, nsrc_g, n_stfprm, sx_g, sz_g, mo_g, myz_g, mxy_g, srcprm_g)
            end if

        end if

        if (earth_flattening) then
            do k = 1, nsrc_g
                sz_g(k) = -R_EARTH * log((R_EARTH - sz_g(k)) / R_EARTH)
            end do
        end if

        !! check cut-off frequency
        !! currently assumes srcprm(2,:) indicates rise time
        fcut = 0.
        do i = 1, nsrc_g
            fcut = max(fcut, 1 / srcprm_g(2, i))
        end do
        fmax = 2 * fcut

        !! count up all moment / body force
        if (bf_mode) then
            M0 = sqrt(sum(fy_g(1:nsrc_g))**2)
            !! unit conversion for body wave source
            UC = UC * 10**3
        else
            M0 = sum(mo_g(1:nsrc_g))
        end if

        !! check if the soruce grid is located inside the node
        nsrc = 0
        do i = 1, nsrc_g

            is_g(i) = x2i(sx_g(i), xbeg, real(dx))
            ks_g(i) = z2k(sz_g(i), zbeg, real(dz))

            !! Count-up source grid *including sleeve area* so that it works even if the source grid is near MPI node boundary
            if (ibeg - 2 <= is_g(i) .and. is_g(i) <= iend + 3 .and. &
                kbeg - 2 <= ks_g(i) .and. ks_g(i) <= kend + 3) then

                inside(i) = .true.

                nsrc = nsrc + 1

            end if
        end do

        !! memory allocation for source grids inside the node
        allocate (sx(nsrc), sz(nsrc))
        allocate (isrc(nsrc), ksrc(nsrc))
        allocate (srcprm(n_stfprm, nsrc))
        if (bf_mode) then
            allocate (fy(nsrc))
        else
            allocate (mo(nsrc), myz(nsrc), mxy(nsrc))
        end if

        !! copy source grid information for the current node
        nn = 0
        do i = 1, nsrc_g
            if (inside(i)) then

                nn = nn + 1

                isrc(nn) = is_g(i)
                ksrc(nn) = ks_g(i)
                sx(nn) = sx_g(i)
                sz(nn) = sz_g(i)

                if (bf_mode) then
                    fy(nn) = fy_g(i)
                else
                    mo(nn) = mo_g(i)
                    myz(nn) = myz_g(i)
                    mxy(nn) = mxy_g(i)
                end if

                srcprm(:, nn) = srcprm_g(:, i)

                !! depth fitting
                do k = 0, NBD
                    write (sdep1, '(I1.1)') k
                    sdep0 = 'bd'//sdep1

                    if (trim(sdep_fit) == sdep0) then
                        sz(nn) = bddep(isrc(nn), k)
                        ksrc(nn) = z2k(sz(nn), zbeg, real(dz))
                    end if
                end do

            end if
        end do

        !! Confirm that FDM model space contains the srouce grid location
        do i = 1, nsrc
            call assert(xbeg <= sx(i) .and. sx(i) <= xend)
            call assert(zbeg <= sz(i) .and. sz(i) <= zend)
        end do

        !! release memroy
        if (bf_mode) then
            deallocate (fy_g)
        else
            deallocate (myz_g, mxy_g)
            deallocate (mo_g)
        end if
        deallocate (sx_g, sz_g)
        deallocate (is_g, ks_g)
        deallocate (inside)

        !! Normalization for numerical stability
        !! Total moment M0 will again be multiplied when export the result
        if (bf_mode) then
            fy(1:nsrc) = fy(1:nsrc) / M0
        else
            mo(1:nsrc) = mo(1:nsrc) / M0
        end if

        !! common grid-related value for stress drip calculation
        dt_dxz = dt / (dx * dz)

        !$acc enter data copyin(stftype, n_stfprm, mo, srcprm, isrc, ksrc, myz, mxy)

        call pwatch__off("source__setup")

    end subroutine source__setup

    subroutine source__grid_moment(fn_stf, stf_format, ns, nprm, sx, sz, mo, myz, mxy, sprm)

        !! returns source grid location, moment and mechanism
        !!
        !! The source__grid subroutine should return
        !!   - number of source grid ns
        !!   - number of source control parameters ( e.g., rupture start time, rise time ... ) nprm
        !!   - source location sx(ns), sy(ns), sz(ns) in the Cartesian coordinate
        !!   - moment release at source grids mo(ns)
        !!   - moment tensors mij(ns) (six components)
        !!   - source control parameters sprm (nprm,ns)

        character(*), intent(in) :: fn_stf
        character(*), intent(in) :: stf_format
        integer, intent(in)     :: ns
        integer, intent(in)     :: nprm
        real(SP), intent(out)    :: sx(ns), sz(ns)
        real(SP), intent(out)    :: mo(ns), myz(ns), mxy(ns)
        real(SP), intent(out)    :: sprm(1:nprm, 1:ns)
        real(SP) :: strike, dip, rake, lon, lat
        integer :: io
        integer :: i
        character(256) :: adum
        integer :: ierr
        real(SP) :: rdum1, rdum2, rdum3, rdum4
        real(SP) :: mw
        real(SP) :: D, S
        integer :: is0, ks0
        real(SP), allocatable :: r0(:)
        real(SP) :: sy(ns)
        integer :: iex
        real(MP) :: M0tmp

        open (newunit=io, file=trim(fn_stf), action='read', status='old')
        i = 0

        do

            read (io, '(A256)', iostat=ierr) adum
            adum = adjustl(adum)
            if (ierr /= 0) exit                  ! detect EOF
            if (adjustl(adum(1:1)) == "#") cycle ! neglect comment line
            if (trim(adjustl(adum)) == "") cycle ! neglect blank line

            i = i + 1

            select case (stf_format)

            case ('xym0ij')
                read (adum, *, iostat=ierr) sx(i), sy(i), sz(i), sprm(1, i), sprm(2, i), &
                    mo(i), rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i)
                call assert(ierr == 0)

            case ('xym0dc')
                read (adum, *, iostat=ierr) sx(i), sy(i), sz(i), sprm(1, i), sprm(2, i), mo(i), strike, dip, rake
                call assert(ierr == 0)
                call assert(-360. <= strike .and. strike <= 360.)
                call assert(-90. <= dip .and. dip <= 90.)
                call assert(-180. <= rake .and. rake <= 180.)
                ! use strike angle measured from map azimuth
                call sdr2moment(strike - phi, dip, rake, rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i))

            case ('llm0ij')
                read (adum, *, iostat=ierr) lon, lat, sz(i), sprm(1, i), sprm(2, i), &
                    mo(i), rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i)
                call assert(ierr == 0)
                call assert(-360. <= lon .and. lon <= 360)
                call assert(-90. <= lat .and. lat <= 90)
                call geomap__g2c(lon, lat, clon, clat, phi, sx(i), sy(i))

            case ('llm0dc')
                read (adum, *, iostat=ierr) lon, lat, sz(i), sprm(1, i), sprm(2, i), mo(i), strike, dip, rake
                call assert(ierr == 0)
                call assert(-360. <= lon .and. lon <= 360)
                call assert(-90. <= lat .and. lat <= 90)
                call sdr2moment(strike - phi, dip, rake, rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i))
                call geomap__g2c(lon, lat, clon, clat, phi, sx(i), sy(i))

            case ('xymwij')
                read (adum, *, iostat=ierr) sx(i), sy(i), sz(i), sprm(1, i), sprm(2, i), &
                    mw, rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i)
                call assert(ierr == 0)
                call assert(mw <= 11.) !! magnitude
                mo(i) = seismic_moment(mw)
            case ('xymwdc')
                read (adum, *, iostat=ierr) sx(i), sy(i), sz(i), sprm(1, i), sprm(2, i), mw, strike, dip, rake
                call assert(ierr == 0)
                call assert(-360. <= strike .and. strike <= 360.)
                call assert(-90. <= dip .and. dip <= 90.)
                call assert(-180. <= rake .and. rake <= 180.)
                call assert(mw <= 11.) !! magnitude
                mo(i) = seismic_moment(mw)
                ! use strike angle measured from map azimuth
                call sdr2moment(strike - phi, dip, rake, rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i))

            case ('llmwij')
                read (adum, *, iostat=ierr) lon, lat, sz(i), sprm(1, i), sprm(2, i), mw, rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i)
                call assert(ierr == 0)
                call assert(-360. <= lon .and. lon <= 360)
                call assert(-90. <= lat .and. lat <= 90)
                call assert(mw <= 11.) !! magnitude
                mo(i) = seismic_moment(mw)
                call geomap__g2c(lon, lat, clon, clat, phi, sx(i), sy(i))

            case ('llmwdc')
                read (adum, *, iostat=ierr) lon, lat, sz(i), sprm(1, i), sprm(2, i), mw, strike, dip, rake
                call assert(ierr == 0)
                call assert(-360. <= lon .and. lon <= 360)
                call assert(-90. <= lat .and. lat <= 90)
                call assert(-360. <= strike .and. strike <= 360.)
                call assert(-90. <= dip .and. dip <= 90.)
                call assert(-180. <= rake .and. rake <= 180.)
                call assert(mw <= 11.) !! magnitude
                mo(i) = seismic_moment(mw)
                call sdr2moment(strike - phi, dip, rake, rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i))
                call geomap__g2c(lon, lat, clon, clat, phi, sx(i), sy(i))

            case ('xydsdc')
                read (adum, *, iostat=ierr) sx(i), sy(i), sz(i), sprm(1, i), sprm(2, i), D, S, strike, dip, rake
                call assert(ierr == 0)
                call assert(-360. <= strike .and. strike <= 360.)
                call assert(-90. <= dip .and. dip <= 90.)
                call assert(-180. <= rake .and. rake <= 180.)
                call sdr2moment(strike - phi, dip, rake, rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i))
                is0 = x2i(sx(i), xbeg, real(dx))
                if (earth_flattening) then
                    ks0 = z2k(real(-R_EARTH * log((R_EARTH - sz(i)) / R_EARTH)), zbeg, real(dz))
                else
                    ks0 = z2k(sz(i), zbeg, real(dz))
                end if

                if (ibeg - 2 <= is0 .and. is0 <= iend + 3 .and. &
                    kbeg - 2 <= ks0 .and. ks0 <= kend + 3) then
                    mo(i) = (1e9 * mu(ks0, is0)) * D * S
                else
                    mo(i) = 0.
                end if

            case ('lldsdc')
                read (adum, *, iostat=ierr) lon, lat, sz(i), sprm(1, i), sprm(2, i), D, S, strike, dip, rake
                call assert(ierr == 0)
                call assert(-360. <= lon .and. lon <= 360)
                call assert(-90. <= lat .and. lat <= 90)
                call assert(-360. <= strike .and. strike <= 360.)
                call assert(-90. <= dip .and. dip <= 90.)
                call assert(-180. <= rake .and. rake <= 180.)

                call sdr2moment(strike - phi, dip, rake, rdum1, rdum2, rdum3, myz(i), rdum4, mxy(i))
                call geomap__g2c(lon, lat, clon, clat, phi, sx(i), sy(i))

                is0 = x2i(sx(i), xbeg, real(dx))
                if (earth_flattening) then
                    ks0 = z2k(real(-R_EARTH * log((R_EARTH - sz(i)) / R_EARTH)), zbeg, real(dz))
                else
                    ks0 = z2k(sz(i), zbeg, real(dz))
                end if

                if (ibeg - 2 <= is0 .and. is0 <= iend + 3 .and. &
                    kbeg - 2 <= ks0 .and. ks0 <= kend + 3) then
                    mo(i) = (1e9 * mu(ks0, is0)) * D * S
                else
                    mo(i) = 0.
                end if

            case ('psmeca')
                read (adum, *, iostat=ierr) lon, lat, sz(i), rdum1, rdum2, rdum3, rdum4, myz(i), mxy(i), iex
                ! reverse sign
                myz(i) = -myz(i)
                mxy(i) = -mxy(i)

                call geomap__g2c(lon, lat, clon, clat, phi, sx(i), sy(i))

                ! moment in dyn-cm
                M0tmp = sqrt(2 * (myz(i)**2 + mxy(i)**2)) / sqrt(2.0)
                mo(i) = M0tmp * 10.**(iex)

                sprm(1, i) = 0.0
                ! 2 x (empirical half-duration) will be a rise time
                sprm(2, i) = 2 * 1.05 * 1e-8 * mo(i)**(1._dp / 3._dp)

                ! convert to N-m unit from Dyn-cm
                mo(i) = mo(i) * 1e-7

                ! scale moment tensor components
                myz(i) = myz(i) / M0tmp
                mxy(i) = mxy(i) / M0tmp

            case default
                write (error_unit, *) "ERROR [source__setup]: Invalid source type: "//trim(stf_format)

            end select

            if (i == 1) then
                call geomap__c2g(sx(i), sy(i), clon, clat, phi, evlo, evla)
                evdp = sz(i)
                mxx0 = -12345.0
                myy0 = -12345.0
                mzz0 = -12345.0
                myz0 = myz(i)
                mxz0 = -12345.0
                mxy0 = mxy(i)
                otim = sprm(1, i)
                sx0 = sx(i)
                sy0 = sy(i)
            end if

        end do

        close (io)

        if (stf_format == 'lldsdc' .or. stf_format == 'xydsdc') then
            allocate (r0(ns))
            call mpi_allreduce(mo, r0, ns, mpi_real, mpi_max, mpi_comm_world, ierr)
            mo(:) = r0(:)
            deallocate (r0)
        end if
    end subroutine source__grid_moment

    subroutine source__grid_bodyforce(fn_stf, stf_format, ns, nprm, sx, sz, fy, sprm)

        !! returns source grid location, moment and mechanism
        !!
        !! The source__grid subroutine should return
        !!   - number of source grid ns
        !!   - number of source control parameters ( e.g., rupture start time, rise time ... ) nprm
        !!   - source location sx(ns), sy(ns), sz(ns) in the Cartesian coordinate
        !!   - body force component fy(ns)
        !!   - source control parameters sprm (nprm,ns)

        character(*), intent(in) :: fn_stf
        character(*), intent(in) :: stf_format
        integer, intent(in)     :: ns
        integer, intent(in)     :: nprm
        real(SP), intent(out)    :: sx(ns), sz(ns)
        real(SP), intent(out)    :: fy(ns)
        real(SP), intent(out)    :: sprm(1:nprm, 1:ns)
        real(SP) :: lon, lat
        integer :: io
        integer :: i
        character(256) :: adum
        integer :: ierr
        real(SP) :: rdum
        character(2) :: stf_coord

        open (newunit=io, file=trim(fn_stf), action='read', status='old')
        i = 0

        stf_coord(1:2) = stf_format(1:2)

        do

            read (io, '(A256)', iostat=ierr) adum
            if (ierr /= 0) exit                  ! detect EOF
            if (adjustl(adum(1:1)) == "#") cycle ! neglect comment line
            if (trim(adjustl(adum)) == "") cycle ! neglect blank line

            i = i + 1

            select case (stf_coord)

            case ('xy')
                read (adum, *, iostat=ierr) sx(i), rdum, sz(i), sprm(1, i), sprm(2, i), rdum, fy(i), rdum
                call assert(ierr == 0)

            case ('ll')
                read (adum, *, iostat=ierr) lon, lat, sz(i), sprm(1, i), sprm(2, i), rdum, fy(i), rdum
                call assert(ierr == 0)
                call assert(-360. <= lon .and. lon <= 360)
                call assert(-90. <= lat .and. lat <= 90)
                call geomap__g2c(lon, lat, clon, clat, phi, sx(i), rdum)

            case default
                write (error_unit, *) "ERROR [source__setup]: Invalid source type: "//trim(stf_format)

            end select

            if (i == 1) then
                call geomap__c2g(sx(i), 0.0, clon, clat, phi, evlo, evla)
                evdp = sz(i)
                fx0 = -12345.0
                fy0 = fy(i)
                fz0 = -12345.0
                otim = sprm(1, i)
            end if

        end do

        close (io)

    end subroutine source__grid_bodyforce

    subroutine source__stressglut(it)

        !! apply stress glut for source grids

        integer, intent(in) :: it !< time grid number

        integer  :: ii, kk
        real(SP) :: sdrop
        integer  :: i
        real(SP) :: stime

        if (bf_mode) return

        call pwatch__on("source__stressglut")

#ifdef _OPENACC
        !$acc kernels &
        !$acc present(stftype, n_stfprm, mo, srcprm, isrc, ksrc, Sxy, Syz, mxy, myz)
        !$acc loop seq
#endif
        do i = 1, nsrc

            stime = momentrate(tbeg + (it-0.5) * dt, stftype, n_stfprm, srcprm(:,i))
            sdrop = mo(i) * stime * dt_dxz

            ii = isrc(i)
            kk = ksrc(i)

            Sxy(kk,ii  ) = Sxy(kk,ii  ) - mxy(i) * sdrop / 2
            Sxy(kk,ii-1) = Sxy(kk,ii-1) - mxy(i) * sdrop / 2

            Syz(kk  ,ii) = Syz(kk  ,ii) - myz(i) * sdrop / 2
            Syz(kk-1,ii) = Syz(kk-1,ii) - myz(i) * sdrop / 2

        end do
#ifdef _OPENACC
        !$acc end kernels
#endif
        call pwatch__off("source__stressglut")

    end subroutine source__stressglut

    subroutine source__bodyforce(it)

        !! apply body force for source grids

        integer, intent(in) :: it !< time grid
        integer :: i, ii, kk
        real(SP) :: stime

        if (.not. bf_mode) return

        call pwatch__on("source__bodyforce")

#ifdef _OPENACC
        !$acc kernels &
        !$acc present(Vy, isrc, ksrc, srcprm, fy, rho, n_stfprm ,stftype)
        !$acc loop seq
#endif
        do i = 1, nsrc

            !! t= nt2(it,tbeg,dt) + dt/2
            stime = momentrate(tbeg + it * dt, stftype, n_stfprm, srcprm(:,i))

            ii = isrc(i)
            kk = ksrc(i)

            Vy(kk, ii) = Vy(kk, ii) + fy(i) / rho(kk,ii) * stime * dt_dxz

        end do
#ifdef _OPENACC
        !$acc end kernels
#endif

        call pwatch__off("source__bodyforce")
    end subroutine source__bodyforce

    subroutine pw_setup(io_prm)

        integer, intent(in) :: io_prm
        real(SP)  :: pw_ztop
        real(SP)  :: pw_zlen
        character :: pw_ps
        real(SP)  :: pw_strike, pw_dip, pw_rake
        real(SP)  :: vs
        integer   :: i, k
        real(SP)  :: sd, cd, sf, cf, sl, cl, c2d, c2f
        real(SP)  :: x0, z0, x1, z1, mu0
        real(SP)  :: stf_vy, stf_yz, stf_xy
        integer   :: ierr

        !! parameter input
        call readini(io_prm, 'pw_ztop', pw_ztop, 1e30)
        call assert(pw_ztop < zend)

        call readini(io_prm, 'pw_zlen', pw_zlen, -1.)
        call assert(pw_zlen > 0.0)

        call readini(io_prm, 'pw_ps', pw_ps, '')
        call assert(pw_ps == 's' .or. pw_ps == 'S') ! only S wave

        call readini(io_prm, 'pw_strike', pw_strike, 0.0)
        call readini(io_prm, 'pw_dip', pw_dip, 0.0)

        pw_strike = std__deg2rad(90.0)
        pw_dip = std__deg2rad(pw_dip)
        pw_rake = std__deg2rad(0.0)

        call readini(io_prm, 'stftype', stftype, 'kupper')

        sd = sin(pw_dip)
        cd = cos(pw_dip)
        sf = sin(pw_strike)
        cf = cos(pw_strike)
        sl = sin(pw_rake)
        cl = cos(pw_rake)
        c2d = cos(2 * pw_dip)
        c2f = cos(2 * pw_strike)

        if (pw_ps == 's' .or. pw_ps == 'S') then

            do i = ibeg_m, iend_m
                do k = kbeg_m, kend_m

                    vs = sqrt(mu(k, i) / rho(k, i))
                    if (vs < epsilon(1.0)) cycle

                    x0 = xbeg + (i - 0.5) * dx
                    z0 = zbeg + (k - 0.5) * dz - pw_ztop
                    x1 = x0 + dx / 2.
                    z1 = z0 + dz / 2.

                    mu0 = mu(k, i)

                    !! source time function evaluated along rotated zeta value at staggered grid points
                    stf_vy = momentrate(sd * sf * x0 + cd * z0 + dt / 2.*vs, stftype, 2, (/0., pw_zlen/))
                    stf_yz = momentrate(sd * sf * x0 + cd * z1, stftype, 2, (/0., pw_zlen/))
                    stf_xy = momentrate(sd * sf * x1 + cd * z0, stftype, 2, (/0., pw_zlen/))

                    vy(k, i) = (cl * sf - sl * cd * cf) * stf_vy
                    syz(k, i) = mu0 * (cl * cd * sf - sl * c2d * cf) * stf_yz / vs
                    sxy(k, i) = -mu0 * (cl * sd * c2f + 2 * sl * sd * cd * sf * cf) * stf_xy / vs

                end do
            end do

        else
            call assert(.false.)
        end if

        !! wavelength condition
        i = x2i((xbeg + xend) / 2, xbeg, real(dx))
        k = z2k(pw_ztop, zbeg, real(dz))
        fcut = 0
        fmax = 0
        if (ibeg <= i .and. i <= iend) then
            vs = sqrt(mu(k, i) / rho(k, i))
            fcut = vs / pw_zlen
        end if
        call mpi_allreduce(fcut, fmax, 1, MPI_REAL, MPI_MAX, mpi_comm_world, ierr)
        fcut = fmax
        fmax = fcut * 2.0

    end subroutine pw_setup

end module m_source
