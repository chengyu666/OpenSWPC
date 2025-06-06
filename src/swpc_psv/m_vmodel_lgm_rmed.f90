#include "../shared/m_debug.h"
module m_vmodel_lgm_rmed

    !! 1D velocity structure with velocity gradient
    !!
    !! Copyright 2013-2025 Takuto Maeda. All rights reserved. This project is released under the MIT license.

    use m_std
    use m_debug
    use m_readini
    use m_global
    use m_rdrmed
    use m_fdtool
    use m_seawater
    implicit none
    private
    save

    public :: vmodel_lgm_rmed

contains

    subroutine vmodel_lgm_rmed(io_prm, i0, i1, k0, k1, xc, zc, vcut, rho, lam, mu, Qp, Qs, bd)

        !! Define meidum velocity, density and attenuation: 1D linear gradient model

        integer,  intent(in)  :: io_prm              !< I/O unit number
        integer,  intent(in)  :: i0, i1              !< i-region
        integer,  intent(in)  :: k0, k1              !< k-region
        real(SP), intent(in)  :: xc(i0:i1)           !< x-coordinate location
        real(SP), intent(in)  :: zc(k0:k1)           !< z-coordinate location
        real(SP), intent(in)  :: vcut                !< cut-off minimum velocity
        real(SP), intent(out) :: rho(k0:k1, i0:i1)   !< mass density [g/cm^3]
        real(SP), intent(out) :: lam(k0:k1, i0:i1)   !< Lame's parameter lambda [ (g/cm^3) * (km/s) ]
        real(SP), intent(out) :: mu(k0:k1, i0:i1)    !< Lame's parameter mu     [ (g/cm^3) * (km/s) ]
        real(SP), intent(out) :: qp(k0:k1, i0:i1)    !< P-wave attenuation
        real(SP), intent(out) :: qs(k0:k1, i0:i1)    !< S-wave attenuation
        real(SP), intent(out) :: bd(i0:i1, 0:NBD)    !< Boundary depths

        character(256) :: fn_lhm
        integer :: i, k, l
        real(SP), allocatable, dimension(:) :: vp0, vs0, rho0, qp0, qs0, depth
        real(SP) :: vp1, vs1, rho1, qp1, qs1
        real(SP) :: dum
        integer :: ierr
        integer :: io_vel
        logical :: is_exist
        integer :: nlayer
        character(256) :: adum
        logical :: use_munk
        logical :: earth_flattening
        real(SP) :: zs(k0:k1) ! spherical depth for earth_flattening
        real(SP) :: Cv(k0:k1) ! velocity scaling coefficient for earth_flattening
        real(SP) :: dh, cc, rhomin
        logical  :: vmax_over, vmin_under, rhomin_under
        character(256), allocatable :: fn_rmed(:)
        real(SP), allocatable :: xi(:,:,:)
        integer :: n_rmed
        integer, allocatable :: tbl_rmed(:)
        character(256), allocatable :: fn_rmed2(:)
        character(256) :: dir_rmed


        call readini(io_prm, 'fn_lhm_rmed', fn_lhm, '')
        call readini(io_prm, 'dir_rmed', dir_rmed, '')
        call readini(io_prm, 'rhomin', rhomin, 1.0)

        inquire (file=fn_lhm, exist=is_exist)
        call assert(is_exist)

        ! seawater
        call readini(io_prm, 'munk_profile', use_munk, .false.)
        call seawater__init(use_munk)

        call readini(io_prm, 'earth_flattening', earth_flattening, .false.)
        if (earth_flattening) then
            do k = k0, k1
                zs(k) = R_EARTH - R_EARTH * exp(- zc(k) / R_EARTH)
                Cv(k) = exp(zc(k) / R_EARTH)
            end do
        else
            zs(:) = zc(:)
            Cv(:) = 1.0
        end if

        vmin = vcut

        dh = 1. /sqrt(1./dx**2 + 1./dz**2)
        cc = 6./7. !! assume 4th order
        vmax = cc * dh / dt 

        vmax_over = .false.
        vmin_under = .false.
        rhomin_under = .false.

        open (newunit=io_vel, file=fn_lhm, status='old', action='read', iostat=ierr)
        call assert(ierr == 0)
        call std__countline(io_vel, nlayer, '#')
        allocate (depth(nlayer), rho0(nlayer), vp0(nlayer), vs0(nlayer), qp0(nlayer), qs0(nlayer), fn_rmed(nlayer))

        l = 0
        do
            read (io_vel, '(A256)', iostat=ierr) adum
            if (ierr /= 0) exit
            adum = trim(adjustl(adum))
            if (trim(adum) == '') cycle
            if (adum(1:1) == "#") cycle
            l = l+1
            read (adum, *) depth(l), rho0(l), vp0(l), vs0(l), qp0(l), qs0(l), fn_rmed(l)
        end do
        close (io_vel)

        ! velocity cut-off
        do l = nlayer-1, 1, -1
            if ((vp0(l) < vcut .or. vs0(l) < vcut) .and. (vp0(l) > 0 .and. vs0(l) > 0)) then
                vp0 (l) = vp0(l+1)
                vs0 (l) = vs0(l+1)
                rho0(l) = rho0(l+1)
                qp0 (l) = qp0(l+1)
                qs0 (l) = qs0(l+1)
            end if
        end do

        do l = 1, nlayer
            fn_rmed(l) = trim(dir_rmed)//'/'//trim(fn_rmed(l))
        end do
        
        !! Read random media
        allocate (tbl_rmed(nlayer), fn_rmed2(nlayer))
        call independent_list(nlayer, fn_rmed, n_rmed, tbl_rmed, fn_rmed2)

        allocate (xi(k0:k1, i0:i1, n_rmed))
        do l = 1, n_rmed
            inquire (file=trim(fn_rmed2(l)), exist=is_exist)
            if (is_exist) then
                call rdrmed__2d(i0, i1, k0, k1, fn_rmed2(l), xi(k0:k1, i0:i1, l))
            else
                xi(k0:k1, i0:i1, l) = 0.0
            end if
        end do        

        ! define topography shape here
        bd(i0:i1, 0) = depth(1)

        do k = k0, k1

            ! air/ocean column
            if (zs(k) < depth(1)) then

                if (zs(k) < 0.0) then

                    rho1 = 0.001 
                    vp1 = 0.0
                    vs1 = 0.0
                    qp1 = 10.0
                    qs1 = 10.0
 
                else

                    rho1 = 1.0
                    vp1 = Cv(k) * seawater__vel(zc(k))
                    vs1 = 0.0
                    qp1 = 1000000.0
                    qs1 = 1000000.0

                end if

                ! set medium parameters above the surface
                rho(k, i0:i1) = rho1
                mu (k, i0:i1) = rho1 * vs1 * vs1
                lam(k, i0:i1) = rho1 * (vp1 * vp1 - 2 * vs1 * vs1)
                qp (k, i0:i1) = qp1
                qs (k, i0:i1) = qs1                
                
            else ! in the medium

                do i = i0 , i1

                    ! initialize by the values of lowermost layer
                    rho1 = rho0(nlayer) * ( 1 + 0.8 * xi(k, i, tbl_rmed(nlayer)))
                    vp1 = Cv(k) * vp0(nlayer) * ( 1 + xi(k, i, tbl_rmed(nlayer)))
                    vs1 = Cv(k) * vs0(nlayer) * ( 1 + xi(k, i, tbl_rmed(nlayer)))
                    qp1 =         qp0(nlayer)
                    qs1 =         qs0(nlayer)

                    ! chose layer
                    do l = 1, nlayer-1            
                        if (depth(l) <= zs(k) .and. zs(k) < depth(l+1)) then
        
                            rho1 =         rho0(l) + (rho0(l+1) - rho0(l)) / (depth(l+1) - depth(l)) * (zs(k) - depth(l))
                            vp1 = Cv(k) * ( vp0(l) + ( vp0(l+1) -  vp0(l)) / (depth(l+1) - depth(l)) * (zs(k) - depth(l)))
                            vs1 = Cv(k) * ( vs0(l) + ( vs0(l+1) -  vs0(l)) / (depth(l+1) - depth(l)) * (zs(k) - depth(l)))
                            qp1 =           qp0(l) + ( qp0(l+1) -  qp0(l)) / (depth(l+1) - depth(l)) * (zs(k) - depth(l))
                            qs1 =           qs0(l) + ( qs0(l+1) -  qs0(l)) / (depth(l+1) - depth(l)) * (zs(k) - depth(l))

                            !! random media
                            rho1 = rho1 * ( 1 + 0.8 * xi(k, i, tbl_rmed(l)))
                            vp1  = vp1  * ( 1 + xi(k, i, tbl_rmed(l)))
                            vs1  = vs1  * ( 1 + xi(k, i, tbl_rmed(l)))


                            if (vp0(l) > 0 .and. vs0(l) > 0) then
                                call vcheck(vp1, vs1, rho1, xi(k, i, tbl_rmed(l)), &
                                            vmin, vmax, rhomin, vmin_under, vmax_over, rhomin_under)
                            end if

                            exit
                        end if                
                    end do

                    ! set medium parameters
                    rho(k, i0:i1) = rho1
                    mu (k, i0:i1) = rho1 * vs1 * vs1
                    lam(k, i0:i1) = rho1 * (vp1 * vp1 - 2 * vs1 * vs1)
                    qp (k, i0:i1) = qp1
                    qs (k, i0:i1) = qs1
        
                end do

            end if

        end do

        !! notification for velocity torelance
        if (vmax_over) call info('Too high velocity due to random media was corrected. ')
        if (vmin_under) call info('Too low  velocity due to random media was corrected. ')
        if (rhomin_under) call info('Too low  density due to random media was corrected. ')

        ! dummy value
        bd(:,1:NBD) = -9999

        ! substitute to a dummy variable for avoiding compiler warnings
        dum = xc(i0)

        deallocate (depth, rho0, vp0, vs0, qp0, qs0)

    end subroutine vmodel_lgm_rmed

end module m_vmodel_lgm_rmed

