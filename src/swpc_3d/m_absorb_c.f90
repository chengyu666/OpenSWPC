#include "../shared/m_debug.h"
module m_absorb_c

    !! Boundary absorber module: Cerjan's Sponge
    !!
    !! Copyright 2013-2025 Takuto Maeda. All rights reserved. This project is released under the MIT license.

    use m_std
    use m_debug
    use m_global
    use m_pwatch
    use m_fdtool

    implicit none
    private
    save

    public :: absorb_c__setup
    public :: absorb_c__update_stress
    public :: absorb_c__update_vel

    real(SP), allocatable :: gx_c(:), gy_c(:), gz_c(:)     !<  attenuator for Q and B.C. for voxel center
    real(SP), allocatable :: gx_b(:), gy_b(:), gz_b(:)     !<  attenuator for Q and B.C. for voxel boundary

contains

    subroutine absorb_c__setup(io_prm)

        !! Setup
        !!
        !! set Cerjan's sponge function for x(i), y(j) and z(k) directions
        !!
        !!#### Note
        !! 2013-00446

        integer, intent(in) :: io_prm

        real(SP), parameter :: alpha = 0.09
        real(SP) :: Lx, Ly, Lz
        integer :: i, j, k
        integer :: io2

        !! memory allocation and initialize

        allocate (gx_c(ibeg_m:iend_m), gx_b(ibeg_m:iend_m))
        allocate (gy_c(jbeg_m:jend_m), gy_b(jbeg_m:jend_m))
        allocate (gz_c(kbeg_m:kend_m), gz_b(kbeg_m:kend_m))
        gx_c(ibeg_m:iend_m) = 1.0
        gy_c(jbeg_m:jend_m) = 1.0
        gz_c(kbeg_m:kend_m) = 1.0
        gx_b(ibeg_m:iend_m) = 1.0
        gy_b(jbeg_m:jend_m) = 1.0
        gz_b(kbeg_m:kend_m) = 1.0

        Lx = na * real(dx)
        Ly = na * real(dy)
        Lz = na * real(dz)

        !! Calculate attenuator based on distance
        do i = ibeg, iend
            if (i <= na) then
                gx_c(i) = exp(-alpha * (1.0 - (i2x(i, 0.0, real(dx))) / Lx)**2)
                gx_b(i) = exp(-alpha * (1.0 - ((i2x(i, 0.0, real(dx)) + real(dx) / 2)) / Lx)**2)
            else if (i >= nx - na + 1) then
                gx_c(i) = exp(-alpha * (1.0 - (i2x(i, Nx * real(dx), -real(dx)) + real(dx) / 2) / Lx)**2)
                gx_b(i) = exp(-alpha * (1.0 - ((i2x(i, Nx * real(dx), -real(dx)))) / Lx)**2)
            else
                gx_c(i) = 1.0
                gx_b(i) = 1.0
            end if
        end do
        do j = jbeg, jend
            if (j <= na) then
                gy_c(j) = exp(-alpha * (1.0 - (j2y(j, 0.0, real(dy))) / Ly)**2)
                gy_b(j) = exp(-alpha * (1.0 - ((j2y(j, 0.0, real(dy)) + real(dy) / 2)) / Ly)**2)
            else if (j >= ny - na + 1) then
                gy_c(j) = exp(-alpha * (1.0 - (j2y(j, Ny * real(dy), -real(dy)) + real(dy) / 2) / Ly)**2)
                gy_b(j) = exp(-alpha * (1.0 - ((j2y(j, Ny * real(dy), -real(dy)))) / Ly)**2)
            else
                gy_c(j) = 1.0
                gy_b(j) = 1.0
            end if
        end do

        do k = kbeg, kend
            if (k <= na) then
                ! if( fullspace_mode ) then
                !   gz_c(k) = exp( - alpha * ( 1.0 -  (   k2z(k, 0.0, real(dz)) )                / Lz )**2 )
                !   gz_b(k) = exp( - alpha * ( 1.0 -  ( ( k2z(k, 0.0, real(dz)) + real(dz)/2 ) ) / Lz )**2 )
                ! else
                gz_c(k) = 1.0
                gz_b(k) = 1.0
                ! end if
            else if (k >= nz - na + 1) then
                gz_c(k) = exp(-alpha * (1.0 - (k2z(k, Nz * real(dz), -real(dz)) + real(dz) / 2) / Lz)**2)
                gz_b(k) = exp(-alpha * (1.0 - ((k2z(k, Nz * real(dz), -real(dz)))) / Lz)**2)
            else
                gz_c(k) = 1.0
                gz_b(k) = 1.0
            end if
        end do

        !! dummy
        io2 = io_prm

#ifdef _OPENACC
        !$acc enter data &
        !$acc copyin(gx_c, gx_b, gy_c, gy_b, gz_c, gz_b)
#endif

    end subroutine absorb_c__setup

    subroutine absorb_c__update_stress

        integer :: i, j, k
        real(SP) :: gcc

#ifdef _OPENACC
        !$acc kernels &
        !$acc present(Sxx, Syy, Szz, gx_c, gy_c, gz_c)
        !$acc loop independent collapse(3)
#else
        !$omp parallel do schedule(dynamic) private( i, j, k, gcc )
#endif
        do j = jbeg, jend
            do i = ibeg, iend
                do k = kbeg, kend_k

                    gcc = gx_c(i) * gy_c(j) * gz_c(k)
                    Sxx(k, i, j) = Sxx(k, i, j) * gcc
                    Syy(k, i, j) = Syy(k, i, j) * gcc
                    Szz(k, i, j) = Szz(k, i, j) * gcc

                end do
            end do
        end do
#ifdef _OPENACC
        !$acc end kernels
#else
        !$omp end parallel do
#endif

        
#ifdef _OPENACC
        !$acc kernels &
        !$acc pcopyin(Syz, Sxz, Sxy, gx_c, gx_b, gy_c, gy_b, gz_c, gz_b)
        !$acc loop independent collapse(3)
#else
        !$omp parallel do schedule(dynamic) private( i, j, k, gcc )
#endif
        do j = jbeg, jend
            do i = ibeg, iend
                do k = kbeg, kend_k

                    Syz(k, i, j) = Syz(k, i, j) * gx_c(i) * gy_b(j) * gz_b(k)
                    Sxz(k, i, j) = Sxz(k, i, j) * gx_b(i) * gy_c(j) * gz_b(k)
                    Sxy(k, i, j) = Sxy(k, i, j) * gx_b(i) * gy_b(j) * gz_c(k)

                end do
            end do
        end do
#ifdef _OPENACC
        !$acc end kernels
#else
        !$omp end parallel do
#endif

    end subroutine absorb_c__update_stress

    subroutine absorb_c__update_vel

        integer :: i, j, k

#ifdef _OPENACC
        !$acc kernels &
        !$acc pcopyin(Vx, Vy, Vz, gx_c, gx_b, gy_c, gy_b, gz_c, gz_b)
        !$acc loop independent collapse(3)
#else
        !$omp parallel do schedule(dynamic) private(i,j,k)
#endif
        do j = jbeg, jend
            do i = ibeg, iend
                do k = kbeg, kend

                    Vx(k, i, j) = Vx(k, i, j) * gx_b(i) * gy_c(j) * gz_c(k)
                    Vy(k, i, j) = Vy(k, i, j) * gx_c(i) * gy_b(j) * gz_c(k)
                    Vz(k, i, j) = Vz(k, i, j) * gx_c(i) * gy_c(j) * gz_b(k)

                end do
            end do
        end do
#ifdef _OPENACC
        !$acc end kernels
#else
        !$omp end parallel do
#endif

    end subroutine absorb_c__update_vel

end module m_absorb_c
