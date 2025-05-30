
#include "../shared/m_debug.h"
program diff_snp

    !! Generate differential snapfile from two inputs
    !!
    !! Copyright 2013-2025 Takuto Maeda. All rights reserved. This project is released under the MIT license.

    use iso_fortran_env, only: error_unit
    use m_std
    use m_system
    use m_fdsnap
    use m_daytim
    use m_debug
    use m_version
    use netcdf

    implicit none

    character(256)        :: fn_in1, fn_in2, fn_out
    character(256)        :: vname
    character(6)          :: snp_type
    type(fdsnap__hdr)     :: hdr_in1, hdr_in2, hdr_out
    integer               :: io_in1, io_in2, io_out
    integer               :: ierr
    integer               :: i, it, nx, ny, nt
    integer               :: ct(3), st(3)
    logical               :: is_exist
    integer, allocatable :: vid(:)
    real(SP), allocatable :: amp1(:, :), amp2(:, :)

    !! Open input files
    call system__getarg(1, fn_in1)
    if (trim(fn_in1) == '-v' .or. trim(fn_in1) == '--version') call version__display('diff_snp')
    call system__getarg(2, fn_in2)
    call system__getarg(3, fn_out)

    call fdsnap__open(fn_in1, io_in1, is_exist, snp_type)
    if (.not. is_exist) stop
    call fdsnap__open(fn_in2, io_in2, is_exist, snp_type)
    if (.not. is_exist) stop

    !! Read Header Part
    call fdsnap__readhdr(fn_in1, io_in1, snp_type, hdr_in1)
    call fdsnap__readhdr(fn_in2, io_in2, snp_type, hdr_in2)

    !! Check size consistency
    call fdsnap__checkhdr(error_unit, hdr_in1)
    call fdsnap__checkhdr(error_unit, hdr_in2)

    call assert(hdr_in1%ns1 == hdr_in2%ns1 .and. hdr_in1%ns2 == hdr_in2%ns2)
    nx = hdr_in1%ns1
    ny = hdr_in1%ns2

    allocate (amp1(nx, ny), amp2(nx, ny))

    !! diff file
    if (snp_type == 'netcdf') then

        !! file generation by a simple copy, then modify in what follows
        call execute_command_line('/bin/cp '//trim(fn_in1)//' '//trim(fn_out))
        call nc_chk(nf90_open(fn_out, NF90_WRITE, io_out))

        !! date & time
        call nc_chk(nf90_put_att(io_out, NF90_GLOBAL, 'exedate', hdr_out%exedate))
        call nc_chk(nf90_inquire_dimension(io_in1, 3, vname, nt))

        allocate (vid(hdr_in1%nsnp))
        do i = 1, hdr_in1%nsnp
            call nc_chk(nf90_inquire_variable(io_in1, 3 + hdr_in1%nmed + i, vname))
            call nc_chk(nf90_inq_varid(io_in1, vname, vid(i)))
        end do

        do it = 1, nt
            write (error_unit, *) it
            ct = (/nx, ny, 1/)
            st = (/1, 1, it/)
            do i = 1, hdr_in1%nsnp
                call nc_chk(nf90_get_var(io_in1, vid(i), amp1, start=st, count=ct))
                call nc_chk(nf90_get_var(io_in2, vid(i), amp2, start=st, count=ct))
                call nc_chk(nf90_put_var(io_out, vid(i), amp1 - amp2, start=st, count=ct))
            end do
        end do

        call nc_chk(nf90_close(io_in1))
        call nc_chk(nf90_close(io_in2))
        call nc_chk(nf90_close(io_out))

    else
        open (newunit=io_out, file=trim(fn_out), access='stream', form='unformatted')
        hdr_out = hdr_in1
        hdr_out%title = "diff__"//trim(hdr_in1%title)//"__"//trim(hdr_in2%title)
        call daytim__getdate(hdr_out%exedate)
        call fdsnap__writehdr(io_out, hdr_out)

        !! medium info
        do i = 1, hdr_in1%nmed
            read (io_in1) amp1
            read (io_in2) amp2
            write (io_out) amp1
            write (error_unit, *) maxval(amp1), minval(amp1)
        end do

        it = 0
        do
            it = it + 1
            do i = 1, hdr_in1%nsnp
                read (io_in1, iostat=ierr) amp1; if (ierr /= 0) call close_exit()
                read (io_in2, iostat=ierr) amp2; if (ierr /= 0) call close_exit()
                write (error_unit, *) it, maxval(amp1 - amp2), minval(amp1 - amp2)
                write (io_out) amp1 - amp2
            end do
        end do

    end if

contains

    subroutine close_exit()
        close (io_in1)
        close (io_in2)
        close (io_out)
        stop
    end subroutine close_exit

    subroutine nc_chk(ierr)

        integer, intent(in) :: ierr

        if (ierr /= NF90_NOERR) write (error_unit, *) NF90_STRERROR(ierr)

    end subroutine nc_chk

end program diff_snp
