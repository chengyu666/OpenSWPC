#include "../shared/m_debug.h"
module m_absorb

    !! Absorbing Boundary Condition
    !!
    !! Copyright 2013-2025 Takuto Maeda. All rights reserved. This project is released under the MIT license.

    use m_std
    use m_debug
    use m_global
    use m_absorb_p
    use m_absorb_c
    use m_readini
    use m_pwatch
    implicit none
    private
    save

    public :: absorb__setup
    public :: absorb__update_stress
    public :: absorb__update_vel

contains

    subroutine absorb__setup(io_prm)

        integer, intent(in) :: io_prm

        call pwatch__on("absorb__setup")

        select case (trim(abc_type))
        case ('pml')
            call absorb_p__setup(io_prm)
        case ('cerjan')
            call absorb_c__setup(io_prm)
        case default
            call assert(.false.)
        end select
        call pwatch__off("absorb__setup")

    end subroutine absorb__setup

    subroutine absorb__update_vel()

        call pwatch__on("absorb__update_vel")

        select case (trim(abc_type))
        case ('pml')
            call absorb_p__update_vel
        case ('cerjan')
            call absorb_c__update_vel
        case default
            continue
        end select

        call pwatch__off("absorb__update_vel")

    end subroutine absorb__update_vel

    subroutine absorb__update_stress()

        call pwatch__on("absorb__update_stress")

        select case (trim(abc_type))
        case ('pml')
            call absorb_p__update_stress
        case ('cerjan')
            call absorb_c__update_stress
        case default
            continue
        end select

        call pwatch__off("absorb__update_stress")

    end subroutine absorb__update_stress

end module m_absorb
