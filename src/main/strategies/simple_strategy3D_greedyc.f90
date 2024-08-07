! concrete strategy3D: discrete greedy Cartesian refinement
module simple_strategy3D_greedyc
include 'simple_lib.f08'
use simple_strategy3D_alloc
use simple_strategy3D_utils
use simple_parameters,      only: params_glob
use simple_builder,         only: build_glob
use simple_strategy3D,      only: strategy3D
use simple_strategy3D_srch, only: strategy3D_srch, strategy3D_spec
use simple_cartft_corrcalc, only: cftcc_glob
implicit none

public :: strategy3D_greedyc
private
#include "simple_local_flags.inc"

type, extends(strategy3D) :: strategy3D_greedyc
    type(strategy3D_srch) :: s
    type(strategy3D_spec) :: spec
contains
    procedure :: new         => new_greedyc
    procedure :: srch        => srch_greedyc
    procedure :: oris_assign => oris_assign_greedyc
    procedure :: kill        => kill_greedyc
end type strategy3D_greedyc

contains

    subroutine new_greedyc( self, spec )
        class(strategy3D_greedyc), intent(inout) :: self
        class(strategy3D_spec),   intent(inout) :: spec
        call self%s%new(spec)
        self%spec = spec
    end subroutine new_greedyc

    subroutine srch_greedyc( self, ithr )
        class(strategy3D_greedyc), intent(inout) :: self
        integer,                   intent(in)    :: ithr
        integer   :: iproj, irot, nevals(2)
        type(ori) :: o, osym, obest
        real      :: corr, euldist, dist_inpl, euls(3), corr_best
        real      :: cxy(3), shvec(2), shvec_incr(2)
        logical   :: got_better
        ! discrete greedy search
        if( build_glob%spproj_field%get_state(self%s%iptcl) > 0 )then
            ! set thread index
            self%s%ithr = ithr
            ! prep
            call self%s%prep4_cont_srch
            ! transfer critical per-particle params
            o          = self%s%o_prev
            obest      = self%s%o_prev
            ! currently the best correlation is the previous one
            corr_best  = self%s%prev_corr
            got_better = .false.
            do iproj=1,self%s%nprojs
                euls = build_glob%eulspace%get_euler(iproj)
                do irot = 1,self%s%nrots
                    euls(3) = build_glob%inpl_rots(irot)
                    call o%set_euler(euls)
                    ! calculate Cartesian corr
                    corr = cftcc_glob%project_and_correlate(self%s%iptcl, o)
                    if( corr > corr_best )then
                        corr_best  = corr
                        obest      = o
                        got_better = .true.
                    endif
                end do
            end do
            if( got_better )then
                call build_glob%pgrpsyms%sym_dists(self%s%o_prev, obest, osym, euldist, dist_inpl)
                call obest%set('dist',      euldist)
                call obest%set('dist_inpl', dist_inpl)
                call obest%set('corr',      corr_best)
                call obest%set('frac',      100.0)
                call obest%set('better',      1.0)
                call build_glob%spproj_field%set_ori(self%s%iptcl, obest)
            else
                call build_glob%spproj_field%set(self%s%iptcl, 'better', 0.)
            endif
            if( self%s%doshift .and. got_better ) then
                ! Cartesian shift search using L-BFGS-B with analytical derivatives
                call cftcc_glob%prep4shift_srch(self%s%iptcl, obest)
                cxy = self%s%shift_srch_cart(nevals)
                ! report # cost function and gradient evaluations
                call build_glob%spproj_field%set(self%s%iptcl, 'nevals',  real(nevals(1)))
                call build_glob%spproj_field%set(self%s%iptcl, 'ngevals', real(nevals(2)))
                shvec      = 0.
                shvec_incr = 0.
                if( cxy(1) >= corr_best )then
                    shvec      = self%s%prev_shvec
                    ! since particle image is shifted in the Cartesian formulation and we apply
                    ! with negative sign in rec3D the sign of the increment found needs to be negative
                    shvec_incr = - cxy(2:3)
                    shvec      = shvec + shvec_incr
                end if
                where( abs(shvec) < 1e-6 ) shvec = 0.
                call build_glob%spproj_field%set_shift(self%s%iptcl, shvec)
                call build_glob%spproj_field%set(self%s%iptcl, 'shincarg', arg(shvec_incr))
            endif
        else
            call build_glob%spproj_field%reject(self%s%iptcl)
        endif
    end subroutine srch_greedyc

    subroutine oris_assign_greedyc( self )
        class(strategy3D_greedyc), intent(inout) :: self
    end subroutine oris_assign_greedyc

    subroutine kill_greedyc( self )
        class(strategy3D_greedyc),   intent(inout) :: self
        call self%s%kill
    end subroutine kill_greedyc

end module simple_strategy3D_greedyc
