module m_rfft

    !! Frequency-decimate, out-of-place recursive FFT
    !!
    !! Copyright 2013-2025 Takuto Maeda. All rights reserved. This project is released under the MIT license.

    use m_std
    implicit none
    private

    public :: rfft__1d      ! One-dimensional FFT of complex data
    public :: rfft__2d      ! Two-dimensional FFT of complex data
    public :: rfft__3d      ! One-dimensional FFT of complex data
    public :: rfft__1drf    ! FFT of real-valued data
    public :: rfft__1dri    ! Inverse of rfft__1drf

    interface rfft__1d
        module procedure rfft1d_8c, rfft1d_4c
    end interface rfft__1d

    interface rfft__2d
        module procedure rfft2d_8c, rfft2d_4c
    end interface rfft__2d

    interface rfft__3d
        module procedure rfft3d_8c, rfft3d_4c
    end interface rfft__3d

    interface rfft__1drf
        module procedure rfft1d_8rf, rfft1d_4rf
    end interface rfft__1drf

    interface rfft__1dri
        module procedure rfft1d_8ri, rfft1d_4ri
    end interface rfft__1dri

contains

    subroutine rfft1d_8c(n, a, isign)

        !! FFT 1D calculation
        !!
        !! #### definition
        !! isign =  1:  AA(k) = sum_{j=0}^{n-1} a(j) exp(  2*pi*i*j*k/n )
        !! isign = -1:  AA(k) = sum_{j=0}^{n-1} a(j) exp( -2*pi*i*j*k/n )

        integer, intent(in)    :: n        !! #data (power of 2)
        complex(DP), intent(inout) :: a(0:n - 1) !! data, will be replaced by results
        integer, intent(in)    :: isign    !! sign +1 or -1

        real(DP)    :: theta
        complex(DP), allocatable :: b(:)

        allocate (b(0:n - 1))
        theta = sign(1, isign) * 2 * PI / n
        call fft0(n, theta, a, b)
        deallocate (b)

    end subroutine rfft1d_8c


    subroutine rfft1d_4c(n, a, isign)

        !! Single precision wrapper to the 1D FFT. Calculation is done in DP.
        !!
        !! #### definition
        !! isign =  1:  AA(k) = sum_{j=0}^{n-1} a(j) exp(  2*pi*i*j*k/n )
        !! isign = -1:  AA(k) = sum_{j=0}^{n-1} a(j) exp( -2*pi*i*j*k/n )

        integer, intent(in)    :: n        !! #data (power of 2)
        complex(SP), intent(inout) :: a(0:n - 1) !! data, will be replaced by results
        integer, intent(in)    :: isign    !! sign +1 or -1

        complex(DP), allocatable :: aa(:), bb(:)
        real(DP) :: theta

        allocate (aa(0:n - 1), bb(0:n - 1))
        aa(0:n - 1) = a(0:n - 1)
        theta = sign(1, isign) * 2 * PI / n
        call fft0(n, theta, aa, bb)
        a(0:n - 1) = aa(0:n - 1)
        deallocate (aa, bb)

    end subroutine rfft1d_4c


    subroutine rfft2d_8c(n1, n2, a, isign)

        !! FFT 2D calculation
        !!
        !! #### definition
        !!  AA(k1,k2) = sum_{j1=0}^{n1-1} sum_{j2=0}^{n2-1} a(j1,j2)
        !!            * exp( sign(isign)*2*pi*i*( (j1*k1)/n1 + (j2*k2)/n2 )  )

        integer, intent(in)    :: n1, n2           !! #data (power of 2)
        complex(DP), intent(inout) :: a(0:n1 - 1, 0:n2 - 1) !! data (will be replaced)
        integer, intent(in)    :: isign            !! sign +1 or -1

        real(DP)    :: theta1, theta2
        complex(DP), allocatable :: b1(:), b2(:)
        integer :: j1, j2


        allocate (b1(0:n1 - 1), b2(0:n2 - 1))
        theta1 = sign(1, isign) * 2 * PI / n1
        theta2 = sign(1, isign) * 2 * PI / n2

        do j2 = 0, n2 - 1
            call fft0(n1, theta1, a(0:n1 - 1, j2), b1)
        end do
        do j1 = 0, n1 - 1
            call fft0(n2, theta2, a(j1, 0:n2 - 1), b2)
        end do

        deallocate (b1, b2)

    end subroutine rfft2d_8c


    subroutine rfft2d_4c(n1, n2, a, isign)

        !! FFT 2D calculation
        !!
        !! #### definition
        !!  AA(k1,k2) = sum_{j1=0}^{n1-1} sum_{j2=0}^{n2-1} a(j1,j2)
        !!            * exp( sign(isign)*2*pi*i*( (j1*k1)/n1 + (j2*k2)/n2 )  )

        integer, intent(in)    :: n1, n2           !! #data (power of 2)
        complex(SP), intent(inout) :: a(0:n1 - 1, 0:n2 - 1) !! data (will be replaced)
        integer, intent(in)    :: isign            !! sign +1 or -1

        real(DP)    :: theta1, theta2
        complex(DP), allocatable :: aa1(:), aa2(:)
        complex(DP), allocatable :: b1(:), b2(:)
        integer :: j1, j2

        
        allocate (b1(0:n1 - 1), b2(0:n2 - 1))
        allocate (aa1(0:n1 - 1), aa2(0:n2 - 1))
        theta1 = sign(1, isign) * 2 * PI / n1
        theta2 = sign(1, isign) * 2 * PI / n2

        do j2 = 0, n2 - 1
            aa1(0:n1 - 1) = a(0:n1 - 1, j2)
            call fft0(n1, theta1, aa1, b1)
            a(0:n1 - 1, j2) = aa1(0:n1 - 1)
        end do
        do j1 = 0, n1 - 1
            aa2(0:n2 - 1) = a(j1, 0:n2 - 1)
            call fft0(n2, theta2, aa2, b2)
            a(j1, 0:n2 - 1) = aa2(0:n2 - 1)
        end do

        deallocate (aa1, aa2, b1, b2)

    end subroutine rfft2d_4c


    subroutine rfft3d_8c(n1, n2, n3, a, isign)

        !! FFT 3D calculation
        !!
        !!  #### definition
        !!  AA(k1,k2,k3) = sum_{j1=0}^{n1-1} sum_{j2=0}^{n2-1}  sum_{j3=0}^{n3-1}
        !!                 a(j1,j2,j3)
        !!                 *exp( sign(isign)*2*pi*i*( j1*k1/n1+j2*k2/n2+j3*k3/n3 ))

        integer, intent(in)    :: n1, n2, n3
        complex(DP), intent(inout) :: a(0:n1 - 1, 0:n2 - 1, 0:n3 - 1)
        integer, intent(in)    :: isign

        real(DP)    :: theta1, theta2, theta3
        complex(DP), allocatable :: b1(:), b2(:), b3(:)
        integer :: j1, j2, j3

        
        allocate (b1(0:n1 - 1), b2(0:n2 - 1), b3(0:n3 - 1))
        theta1 = sign(1, isign) * 2 * PI / n1
        theta2 = sign(1, isign) * 2 * PI / n2
        theta3 = sign(1, isign) * 2 * PI / n3

        do j3 = 0, n3 - 1
            do j2 = 0, n2 - 1
                call fft0(n1, theta1, a(0:n1 - 1, j2, j3), b1)
            end do
        end do
        do j3 = 0, n3 - 1
            do j1 = 0, n1 - 1
                call fft0(n2, theta2, a(j1, 0:n2 - 1, j3), b2)
            end do
        end do
        do j2 = 0, n2 - 1
            do j1 = 0, n1 - 1
                call fft0(n3, theta3, a(j1, j2, 0:n3 - 1), b3)
            end do
        end do

        deallocate (b1, b2, b3)

    end subroutine rfft3d_8c


    subroutine rfft3d_4c(n1, n2, n3, a, isign)

        !! FFT 3D calculation
        !!
        !! #### definition
        !! isign =  1:
        !!  AA(k1,k2) = sum_{j1=0}^{n1-1} sum_{j2=0}^{n2-1}  sum_{j3=0}^{n3-1}
        !!           a(j1,j2,j3) * exp( (isign)*2*pi*i*(j1*k1/n1+j2*k2/n2+j3*k3/n3))

        integer, intent(in)    :: n1, n2, n3
        complex(SP), intent(inout) :: a(0:n1 - 1, 0:n2 - 1, 0:n3 - 1)
        integer, intent(in)    :: isign

        real(DP)    :: theta1, theta2, theta3
        complex(DP), allocatable :: aa1(:), aa2(:), aa3(:)
        complex(DP), allocatable :: b1(:), b2(:), b3(:)
        integer :: j1, j2, j3

        
        allocate (aa1(0:n1 - 1), aa2(0:n2 - 1), aa3(0:n3 - 1))
        allocate (b1(0:n1 - 1), b2(0:n2 - 1), b3(0:n3 - 1))
        theta1 = sign(1, isign) * 2 * PI / n1
        theta2 = sign(1, isign) * 2 * PI / n2
        theta3 = sign(1, isign) * 2 * PI / n3

        do j3 = 0, n3 - 1
            do j2 = 0, n2 - 1
                aa1(0:n1 - 1) = a(0:n1 - 1, j2, j3)
                call fft0(n1, theta1, aa1, b1)
                a(0:n1 - 1, j2, j3) = aa1(0:n1 - 1)
            end do
        end do
        do j3 = 0, n3 - 1
            do j1 = 0, n1 - 1
                aa2(0:n2 - 1) = a(j1, 0:n2 - 1, j3)
                call fft0(n2, theta2, aa2, b2)
                a(j1, 0:n2 - 1, j3) = aa2(0:n2 - 1)
            end do
        end do
        do j2 = 0, n2 - 1
            do j1 = 0, n1 - 1
                aa3(0:n3 - 1) = a(j1, j2, 0:n3 - 1)
                call fft0(n3, theta3, aa3, b3)
                a(j1, j2, 0:n3 - 1) = aa3(0:n3 - 1)
            end do
        end do

        deallocate (b1, b2, b3)
        deallocate (aa1, aa2, aa3)

    end subroutine rfft3d_4c


    subroutine rfft1d_8rf(n, r, c, isign)

        !! FFT for real data (real<->complex)
        !!
        !! #### forward definition: 
        !! forward=.true.
        !! isign =  1:  C(k) = sum_{j=0}^{n-1} r(j) exp(  2*pi*i*j*k/n )
        !! isign = -1:  C(k) = sum_{j=0}^{n-1} r(j) exp( -2*pi*i*j*k/n )

        integer, intent(in)  :: n          !! #data (power of 2)
        real(DP), intent(in)  :: r(0:n - 1)   !! real data
        complex(DP), intent(out) :: c(0:n / 2)   !! complex data
        integer, intent(in)  :: isign      !! sign +1 or -1

        real(DP)    :: theta
        complex(DP), allocatable :: a(:)
        integer :: j, k
        complex(DP) :: ww

        allocate (a(0:n / 2 - 1))

        do j = 0, n / 2 - 1
            a(j) = cmplx(r(2 * j), r(2 * j + 1), kind=DP)
        end do
        call rfft1d_8c(n / 2, a, isign)

        theta = sign(1, isign) * 2 * PI / n
        do k = 1, n / 4 - 1
            ww = cmplx(cos(k * theta), sin(k * theta), kind=DP)
            c(k) = a(k) - (1 + EI * ww) / 2.*(a(k) - conjg(a(n / 2 - k)))
            c(n / 2 - k) = conjg(a(n / 2 - k)) + (1 + EI * ww) / 2.*(a(k) - conjg(a(n / 2 - k)))
            c(n / 2 - k) = conjg(c(n / 2 - k))
        end do
        c(0) = cmplx(dble(a(0)) + aimag(a(0)), 0.0_DP, kind=DP)
        c(n / 2) = cmplx(dble(a(0)) - aimag(a(0)), 0.0_DP, kind=DP)

        c(n / 4) = a(n / 4)

        deallocate (a)

    end subroutine rfft1d_8rf


    subroutine rfft1d_8ri(n, c, r, isign)

        !! FFT for real data (inverse transform)
        !!
        !! #### (inverse definition)
        !! isign =  1:  r(j) = sum_{k=0}^{n-1} C(j) exp(  2*pi*i*j*k/n )
        !! isign = -1:  r(j) = sum_{k=0}^{n-1} C(j) exp( -2*pi*i*j*k/n )

        integer, intent(in)  :: n          !! #data (power of 2)
        complex(DP), intent(in)  :: c(0:n / 2)   !! complex data
        real(DP), intent(out) :: r(0:n - 1)   !! real data
        integer, intent(in)  :: isign      !! sign +1 or -1

        real(DP)    :: theta
        complex(DP), allocatable :: a(:)
        integer :: j, k
        complex(DP) :: ww

        allocate (a(0:n / 2 - 1))

        !! c(0), c(n/2) are pure real value
        a(0) = cmplx(0.5 * dble(c(0) + c(n / 2)), 0.5 * dble(c(0) - c(n / 2)), kind=DP)
        a(n / 4) = c(n / 4)
        theta = sign(1, isign) * 2 * PI / n
        do k = 1, n / 4 - 1
            ww = cmplx(cos(k * theta), sin(k * theta), kind=DP)
            a(k) = c(k) - (1 - EI * ww) / 2.*(c(k) - conjg(c(n / 2 - k)))
            a(n / 2 - k) = conjg(c(n / 2 - k)) + (1 - EI * ww) / 2.*(c(k) - conjg(c(n / 2 - k)))
            a(n / 2 - k) = conjg(a(n / 2 - k))
        end do

        call rfft1d_8c(n / 2, a, isign)

        do j = 0, n / 2 - 1
            r(2 * j) = 2 * dble(a(j))
            r(2 * j + 1) = 2 * aimag(a(j))
        end do

        deallocate (a)

    end subroutine rfft1d_8ri


    subroutine rfft1d_4rf(n, r, c, isign)

        !! FFT for real data (real<->complex)

        integer, intent(in)  :: n          !! #data (power of 2)
        real(SP), intent(in)  :: r(0:n - 1)   !! real data
        complex(SP), intent(out) :: c(0:n / 2)   !! complex data
        integer, intent(in)  :: isign      !! sign +1 or -1

        real(DP), allocatable :: rr(:)
        complex(DP), allocatable :: cc(:)

        allocate (cc(0:n / 2), rr(0:n - 1))
        rr(0:n - 1) = r(0:n - 1)
        call rfft1d_8rf(n, rr(0:n - 1), cc(0:n / 2), isign)
        c(0:n / 2) = cc(0:n / 2)

        deallocate (rr, cc)
    end subroutine rfft1d_4rf


    subroutine rfft1d_4ri(n, c, r, isign)
    
        !! FFT for real data (real<->complex)

        integer, intent(in)  :: n          !! #data (power of 2)
        complex(SP), intent(in)  :: c(0:n / 2)   !! complex data
        real(SP), intent(out) :: r(0:n - 1)   !! real data
        integer, intent(in)  :: isign      !! sign +1 or -1

        real(DP), allocatable :: rr(:)
        complex(DP), allocatable :: cc(:)

        allocate (cc(0:n / 2), rr(0:n - 1))
        cc(0:n / 2) = c(0:n / 2)
        call rfft1d_8ri(n, cc(0:n / 2), rr(0:n - 1), isign)
        r(0:n - 1) = real(rr(0:n - 1))

        deallocate (rr, cc)

    end subroutine rfft1d_4ri

    
    recursive subroutine fft0(n, theta, a, b)

        !! Recursive FFT engine by frequency decimation & out-of-place sorting

        integer, intent(in)    :: n
        real(DP), intent(in)    :: theta    !! fft angle (+-)2*pi/n_0
        complex(DP), intent(inout) :: a(0:n - 1) !! data
        complex(DP), intent(inout) :: b(0:n - 1) !! working space
        integer :: nh
        integer :: j
        complex(DP) :: ww, wp1, wp2
        real(DP) :: tsq

        if (n <= 1) return

        nh = n / 2
        b(0) = a(0) + a(nh)
        b(nh) = a(0) - a(nh)

        if (nh >= 2) then
            tsq = 2 * sin(theta)
            wp1 = cmplx(cos(theta), sin(theta), kind=DP)
            wp2 = cmplx(1.0_DP, 0.0_DP, kind=DP)
            b(1) = a(1) + a(nh + 1)
            b(nh + 1) = (a(1) - a(nh + 1)) * wp1
            do j = 2, nh - 1
                ww = EI * tsq * wp1 + wp2
                b(j) = a(j) + a(nh + j)
                b(nh + j) = (a(j) - a(nh + j)) * ww
                wp2 = wp1
                wp1 = ww
            end do
        end if
        call fft0(nh, 2 * theta, b(0:nh - 1), a(0:nh - 1))
        call fft0(nh, 2 * theta, b(nh:n - 1), a(nh:n - 1))

        do j = 0, nh - 1
            a(2 * j) = b(j)
            a(2 * j + 1) = b(nh + j)
        end do

    end subroutine fft0

end module m_rfft
