! concrete strategy3D: greedy refinement
module simple_strategy3D_greedy
include 'simple_lib.f08'
use simple_strategy3D_alloc
use simple_strategy3D_utils
use simple_parameters,       only: params_glob
use simple_builder,          only: build_glob
use simple_strategy3D,       only: strategy3D
use simple_strategy3D_srch,  only: strategy3D_srch, strategy3D_spec
use simple_polarft_corrcalc, only: pftcc_glob
implicit none

public :: strategy3D_greedy
private
#include "simple_local_flags.inc"

type, extends(strategy3D) :: strategy3D_greedy
    type(strategy3D_srch) :: s
    type(strategy3D_spec) :: spec
contains
    procedure :: new         => new_greedy
    procedure :: srch        => srch_greedy
    procedure :: kill        => kill_greedy
    procedure :: oris_assign => oris_assign_greedy
end type strategy3D_greedy

contains

    subroutine new_greedy( self, spec )
        class(strategy3D_greedy), intent(inout) :: self
        class(strategy3D_spec),   intent(inout) :: spec
        call self%s%new(spec)
        self%spec = spec
    end subroutine new_greedy

    subroutine srch_greedy( self, ithr )
        class(strategy3D_greedy), intent(inout) :: self
        integer,                  intent(in)    :: ithr
        integer, parameter :: N_SAMPLES = 10
        integer   :: iref, isample, loc, refs_inpl(self%s%nrefs), inpl_ind
        real      :: inpl_corrs(self%s%nrots), refs_corrs(self%s%nrefs), cxy(3), prob_shift
        if( build_glob%spproj_field%get_state(self%s%iptcl) > 0 )then
            ! set thread index
            self%s%ithr = ithr
            ! prep
            call self%s%prep4srch
             ! shift search on previous best reference
            call self%s%inpl_srch_first
            ! search
            do isample=1,self%s%nrefs
                iref = s3D%srch_order(isample,self%s%ithr) ! set the reference index
                if( s3D%state_exists(s3D%proj_space_state(iref)) )then
                    ! identify the top scoring in-plane angle
                    if( params_glob%l_sh_first )then
                        call pftcc_glob%gencorrs(iref, self%s%iptcl, self%s%xy_first, inpl_corrs)
                    else
                        call pftcc_glob%gencorrs(iref, self%s%iptcl, inpl_corrs)
                    endif
                    loc = maxloc(inpl_corrs, dim=1)
                    refs_corrs(iref) = inpl_corrs(loc)
                    refs_inpl( iref) = loc
                    call self%s%store_solution(iref, loc, inpl_corrs(loc))
                endif
            end do
            iref     = maxloc(refs_corrs, dim=1)
            inpl_ind = refs_inpl(iref)
            call self%s%grad_shsrch_obj%set_indices(iref, self%s%iptcl)
            cxy = self%s%grad_shsrch_obj%minimize(irot=inpl_ind)
            if( inpl_ind == 0 )then
                inpl_ind = refs_inpl(iref)
                cxy      = [real(pftcc_glob%gencorr_for_rot_8(iref, self%s%iptcl, inpl_ind)), 0.,0.]
            endif
            prob_shift = refs_corrs(iref) / (refs_corrs(iref) + cxy(1))
            if( ran3() < prob_shift )then
                call assign_ori(self%s, iref, inpl_ind, refs_corrs(iref), [0.,0.])
            else
                call assign_ori(self%s, iref, inpl_ind, cxy(1), cxy(2:3))
            endif
        else
            call build_glob%spproj_field%reject(self%s%iptcl)
        endif
    end subroutine srch_greedy

    subroutine oris_assign_greedy( self )
        class(strategy3D_greedy), intent(inout) :: self
        call extract_peak_ori(self%s)
    end subroutine oris_assign_greedy

    subroutine kill_greedy( self )
        class(strategy3D_greedy), intent(inout) :: self
        call self%s%kill
    end subroutine kill_greedy

end module simple_strategy3D_greedy
