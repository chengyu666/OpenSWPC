#include "../shared/m_debug.h"
module m_medium

    !! Set-up medium velocity/attenuation structure
    !!
    !! Copyright 2013-2025 Takuto Maeda. All rights reserved. This project is released under the MIT license.

    use m_std
    use m_debug
    use m_global
    use m_pwatch
    use m_readini
    use m_vmodel_uni
    use m_vmodel_grd
    use m_vmodel_lhm
    use m_vmodel_lgm
    use m_vmodel_user
    use m_vmodel_uni_rmed
    use m_vmodel_lhm_rmed
    use m_vmodel_grd_rmed
    use m_vmodel_lgm_rmed
    use m_fdtool
    use mpi
    implicit none
    private
    save

    public :: medium__setup
    public :: medium__initialized

    logical :: init = .false.

contains

    subroutine medium__setup(io_prm)

        !! Obtain elastic/anelastic medium structure

        integer, intent(in) :: io_prm

        real(SP) :: fq_min, fq_max                    !< frequency range
        real(SP) :: fq_ref                            !< reference frequency

        real(SP) :: zeta
        real(SP) :: vcut
        character(16) :: vmodel_type
        integer :: i, k
        logical :: is_stabilize_pml

        call pwatch__on("medium__setup")

        !! allocate memory and initialize
        call memory_allocate()

        rho(kbeg_m:kend_m, ibeg_m:iend_m) = 0.0
        lam(kbeg_m:kend_m, ibeg_m:iend_m) = 0.0
        mu(kbeg_m:kend_m, ibeg_m:iend_m) = 0.0
        taup(kbeg_m:kend_m, ibeg_m:iend_m) = 0.0
        taus(kbeg_m:kend_m, ibeg_m:iend_m) = 0.0

        !! benchmark mode: fixed medium parameter
        if (benchmark_mode) then

            fq_min = 0.05
            fq_max = 5.0
            fq_ref = 1.0
            do k = kbeg_m, kend_m
                if (zc(k) < 0.0) then
                    rho(k, :) = 0.001
                    mu(k, :) = 0.0
                    lam(k, :) = 0.0
                else
                    rho(k, :) = 2.7
                    mu(k, :) = 2.7 * 3.5 * 3.5
                    lam(k, :) = 2.7 * 3.5 * 3.5 ! poison solid: lambda = mu
                end if

                !! very large Q value (no attenuation) for benchmark
                taup(k, :) = 1e10
                taus(k, :) = 1e10
            end do

        else

            !! read parameters
            call readini(io_prm, 'fq_min', fq_min, 0.05)
            call readini(io_prm, 'fq_max', fq_max, 5.00)
            call readini(io_prm, 'fq_ref', fq_ref, 1.00)

            call readini(io_prm, 'vmodel_type', vmodel_type, 'uni')
            call readini(io_prm, 'vcut', vcut, 0.0)

            call pwatch__on("vmodel")
            select case (trim(vmodel_type))

            case ('user')
                call vmodel_user(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case ('uni')
                call vmodel_uni(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case ('grd')
                call vmodel_grd(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case ('lhm')
                call vmodel_lhm(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case ('lgm')
                call vmodel_lgm(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case ('uni_rmed')
                call vmodel_uni_rmed(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case ('grd_rmed')
                call vmodel_grd_rmed(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case ('lhm_rmed')
                call vmodel_lhm_rmed(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case ('lgm_rmed')
                call vmodel_lhm_rmed(io_prm, ibeg_m, iend_m, kbeg_m, kend_m, xc, zc, vcut, rho, lam, mu, taup, taus, bddep)

            case default
                call assert(.false.)
            end select

            call pwatch__off("vmodel")
        end if

        !! homogenize absorber region
        do i = ibeg_m, na
            do k = kbeg_m, kend_m
                rho(k, i) = rho(k, na + 1)
                lam(k, i) = lam(k, na + 1)
                mu(k, i) = mu(k, na + 1)
                taup(k, i) = taup(k, na + 1)
                taus(k, i) = taus(k, na + 1)
            end do
        end do
        do i = nx - na + 1, iend_m
            do k = kbeg_m, kend_m
                rho(k, i) = rho(k, nx - na)
                lam(k, i) = lam(k, nx - na)
                mu(k, i) = mu(k, nx - na)
                taup(k, i) = taup(k, nx - na)
                taus(k, i) = taus(k, nx - na)
            end do
        end do
        do i = ibeg_m, iend_m
            do k = nz - na + 1, kend_m
                rho(k, i) = rho(nz - na, i)
                lam(k, i) = lam(nz - na, i)
                mu(k, i) = mu(nz - na, i)
                taup(k, i) = taup(nz - na, i)
                taus(k, i) = taus(nz - na, i)
            end do
        end do

        !! Define visco-elastic medium by tau-method
        call visco_set_relaxtime(nm, ts, fq_min, fq_max)
        zeta = visco_constq_zeta(nm, fq_min, fq_max, ts)

        !! Re-define taup and taus as relaxation times of P- and S-waves, based on tau-method
        do i = ibeg_m, iend_m
            do k = kbeg_m, kend_m
                taup(k, i) = nm * zeta / taup(k, i)
                taus(k, i) = nm * zeta / taus(k, i)
            end do
        end do

        call relaxed_medium()
        call surface_detection()
        call velocity_minmax()

        call readini(io_prm, 'stabilize_pml', is_stabilize_pml, .false.)
        if (is_stabilize_pml) then
            call stabilize_absorber()
        end if

        !! initialized flag
        init = .true.

        call pwatch__off("medium__setup")

    contains

        subroutine relaxed_medium()

            !! scale medium velocity using reference frequency

            integer :: i, k
            real(SP) :: rho_beta2, rho_alpha2

            if (nm == 0) return

            !! mu, lam must be re-defined including sleeve area for medium smoothing

            do i = ibeg_m, iend_m
                do k = kbeg_m, kend_m

                    rho_beta2 = mu(k, i)
                    rho_alpha2 = lam(k, i) + 2 * mu(k, i)

                    !! re-definie mu and lambda as unrelaxed moduli of viscoelastic medium
                    mu(k, i) = rho_beta2 / visco_chi(nm, ts, taus(k, i), fq_ref)**2
                    lam(k, i) = rho_alpha2 / visco_chi(nm, ts, taup(k, i), fq_ref)**2 - 2 * mu(k, i)

                end do
            end do

        end subroutine relaxed_medium

        subroutine surface_detection

            !! free surface boundary detection

            real(SP) :: epsl
            integer :: i, k

            epsl = epsilon(1.0)

            !! initial value. This initial settings do not apply 2nd order condition interior the medium
            kfs(:) = kbeg - 1
            kob(:) = kbeg - 1

            !! kfs, kob must be defined one-grid outside of (beg, end) for detecting kfs_top & kfs_bot
            do i = ibeg - 1, iend + 2
                do k = kbeg, kend - 1

                    !! air(ocean)-to-solid boundary
                    if (abs(mu(k, i)) < epsl .and. abs(mu(k + 1, i)) > epsl) then
                        kob(i) = k
                    end if

                    !! air-to-solid(ocean) boundary
                    if (abs(lam(k, i)) < epsl .and. abs(lam(k + 1, i)) > epsl) then
                        kfs(i) = k
                    end if

                end do
            end do

            !! define 2nd-order derivative area #2013-00419
            !! -> udpated to stable version: 2023-08-06
            do i = ibeg, iend

                kfs_top(i) = max(minval(kfs(i - 2:i + 3)) - 2, kbeg)
                kfs_top(i) = min(maxval(kfs(i - 2:i + 3)) + 2, kend)

                kob_top(i) = max(minval(kob(i - 2:i + 3)) - 2, kbeg)
                kob_bot(i) = min(maxval(kob(i - 2:i + 3)) + 2, kend)

            end do

            ! if( fullspace_mode ) then
            !   kfs_bot = kfs_top - 1
            !   kob_bot = kob_top - 1
            ! end if

        end subroutine surface_detection

        subroutine velocity_minmax()

            !! maximum & minimum velocities

            real(SP) :: vmin1, vmax1
            integer  :: i, k
            real(SP) :: vs
            integer  :: ierr

            vmax1 = -1
            vmin1 = 1e30

            !! SH code use S-wave velocity only
            do i = ibeg, iend
                do k = kfs(i) + 1, kend
                    vs = sqrt(mu(k, i) / rho(k, i))
                    vmax1 = max(vmax1, vs)
                    if (vs < epsilon(1.0)) cycle
                    vmin1 = min(vmin1, vs)
                end do
            end do

            call mpi_allreduce(vmax1, vmax, 1, MPI_REAL, MPI_MAX, mpi_comm_world, ierr)
            call mpi_allreduce(vmin1, vmin, 1, MPI_REAL, MPI_MIN, mpi_comm_world, ierr)

        end subroutine velocity_minmax

    end subroutine medium__setup

    logical function medium__initialized()

        !! Check if medium__setup has already been called

        medium__initialized = init

    end function medium__initialized

    subroutine stabilize_absorber()

        !! Avoid low-velocity layer for stabilize PML absorber

        integer :: i, k, k2
        real :: vs
        real, parameter :: V_DYNAMIC_RANGE = 0.4 ! ratio between maximum and minimum velocity
        real :: vmin_pml
        integer :: LV_THICK = 20 !! minimum thickness of low-velocity layer in grids

        vmin_pml = vmax * V_DYNAMIC_RANGE

        do i = ibeg - 1, iend + 1
            k = minval(kbeg_a(i - 2:i + 2))
            do while (k <= kend)
                if (lam(k, i) < lam(k - 1, i) .or. mu(k, i) < mu(k - 1, i)) then

                    !! detection the bottom of the low-velocity layer
                    do k2 = k + 1, kend
                        if (lam(k2, i) > lam(k2 - 1, i) .or. mu(k2, i) > mu(k2 - 1, i)) exit
                    end do

                    if (k2 - k <= LV_THICK) then

                        rho(k:k2 - 1, i) = rho(k - 1, i)
                        lam(k:k2 - 1, i) = lam(k - 1, i)
                        mu(k:k2 - 1, i) = mu(k - 1, i)
                        taup(k:k2 - 1, i) = taup(k - 1, i)
                        taus(k:k2 - 1, i) = taus(k - 1, i)
                        k = k2 - 1
                    end if

                end if
                k = k + 1
            end do
        end do

        do i = ibeg - 1, iend + 1
            do k = minval(kbeg_a(i - 2:i + 2)), kend

                vs = sqrt(mu(k, i) / rho(k, i))

                ! skip ocean and air
                if (vs < epsilon(1.0)) cycle

                if (vs < vmin_pml) then
                    vs = vmin_pml
                    mu(k, i) = rho(k, i) * (vs**2)
                end if
            end do
        end do

    end subroutine stabilize_absorber

    subroutine memory_allocate()

        allocate (rho(kbeg_m:kend_m, ibeg_m:iend_m))
        allocate (lam(kbeg_m:kend_m, ibeg_m:iend_m))
        allocate (mu(kbeg_m:kend_m, ibeg_m:iend_m))
        allocate (taup(kbeg_m:kend_m, ibeg_m:iend_m))
        allocate (taus(kbeg_m:kend_m, ibeg_m:iend_m))
        allocate (kfs(ibeg_m:iend_m))
        allocate (kob(ibeg_m:iend_m))
        allocate (kfs_top(ibeg_m:iend_m))
        allocate (kfs_bot(ibeg_m:iend_m))
        allocate (kob_top(ibeg_m:iend_m))
        allocate (kob_bot(ibeg_m:iend_m))
        allocate (bddep(ibeg_m:iend_m, 0:NBD))
        if (nm > 0) allocate (ts(1:nm))

    end subroutine memory_allocate

end module m_medium
