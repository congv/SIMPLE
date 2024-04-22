! common strategy2D methods and type specification for polymorphic strategy2D object creation are delegated to this class
module simple_strategy2D_srch
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_polarft_corrcalc,  only: pftcc_glob
use simple_pftcc_shsrch_grad, only: pftcc_shsrch_grad ! gradient-based angle and shift search
use simple_parameters,        only: params_glob
use simple_builder,           only: build_glob
use simple_strategy2D_alloc   ! s2D singleton
implicit none

public :: strategy2D_srch, strategy2D_spec, squared_sampling
private

#include "simple_local_flags.inc"

type strategy2D_spec
    real    :: stoch_bound = 0.
    integer :: iptcl       = 0  ! global particle index
    integer :: iptcl_map   = 0  ! maps to index in batch
end type strategy2D_spec

type strategy2D_srch
    type(pftcc_shsrch_grad) :: grad_shsrch_obj      !< origin shift search object, L-BFGS with gradient
    type(pftcc_shsrch_grad) :: grad_shsrch_obj2     !< origin shift search object, L-BFGS with gradient, no call back
    integer                 :: nrefs         =  0   !< number of references
    integer                 :: nrots         =  0   !< number of in-plane rotations in polar representation
    integer                 :: nrefs_eval    =  0   !< nr of references evaluated
    integer                 :: prev_class    =  0   !< previous class index
    integer                 :: best_class    =  0   !< best class index found by search
    integer                 :: best_rot      =  0   !< best in-plane rotation found by search
    integer                 :: prev_rot      =  0   !< previous in-plane rotation found by search
    integer                 :: iptcl         =  0   !< global particle index
    integer                 :: iptcl_map     =  0   !< index in pre-allocated batch array
    integer                 :: ithr          =  0   !< current thread
    real                    :: prev_shvec(2) =  0.  !< previous origin shift vector
    real                    :: best_shvec(2) =  0.  !< best shift vector found by search
    real                    :: prev_corr     = -1.  !< previous best correlation
    real                    :: best_corr     = -1.  !< best corr found by search
    real                    :: specscore     =  0.  !< spectral score
    real                    :: trs           =  0.  !< shift boundary
  contains
    procedure          :: new
    procedure          :: prep4srch
    procedure          :: inpl_srch
    procedure          :: store_solution
    procedure          :: kill
end type strategy2D_srch

contains

    subroutine new( self, spec )
        class(strategy2D_srch), intent(inout) :: self
        class(strategy2D_spec), intent(in)    :: spec
        integer, parameter :: MAXITS = 60
        real :: lims(2,2), lims_init(2,2)
        call self%kill
        ! set constants
        self%iptcl      =  spec%iptcl
        self%iptcl_map  =  spec%iptcl_map
        self%nrefs      =  params_glob%ncls
        self%nrots      =  pftcc_glob%get_nrots()
        self%nrefs_eval =  0
        ! construct composites
        self%trs        = params_glob%trs
        lims(:,1)       = -params_glob%trs
        lims(:,2)       =  params_glob%trs
        lims_init(:,1)  = -SHC_INPL_TRSHWDTH
        lims_init(:,2)  =  SHC_INPL_TRSHWDTH
        if( trim(params_glob%tseries).eq.'yes' )then
            ! shift only search
            call self%grad_shsrch_obj%new(lims, lims_init=lims_init, maxits=MAXITS, opt_angle=.false.)
        else
            call self%grad_shsrch_obj%new(lims, lims_init=lims_init, maxits=MAXITS)
        endif
        call self%grad_shsrch_obj2%new(lims, lims_init=lims_init, maxits=MAXITS, opt_angle=.false.)
    end subroutine new

    subroutine prep4srch( self )
        class(strategy2D_srch), intent(inout) :: self
        real    :: corrs(pftcc_glob%get_nrots())
        integer :: prev_roind
        self%nrefs_eval = 0
        self%ithr       = omp_get_thread_num() + 1
        ! find previous discrete alignment parameters
        self%prev_class = nint(build_glob%spproj_field%get(self%iptcl,'class'))                ! class index
        prev_roind      = pftcc_glob%get_roind(360.-build_glob%spproj_field%e3get(self%iptcl)) ! in-plane angle index
        self%prev_shvec = build_glob%spproj_field%get_2Dshift(self%iptcl)                      ! shift vector
        self%best_shvec = 0.
        if( self%prev_class > 0 )then
            if( s2D%cls_pops(self%prev_class) > 0 )then
                ! all done
            else
                ! for limiting cases
                self%prev_class = irnd_uni(self%nrefs)
                do while( s2D%cls_pops(self%prev_class) <= 0 )
                    self%prev_class = irnd_uni(self%nrefs)
                enddo
            endif
        else
            ! initialization
            self%prev_class = irnd_uni(self%nrefs)
            do while( s2D%cls_pops(self%prev_class) <= 0 )
                self%prev_class = irnd_uni(self%nrefs)
            enddo
        endif
        ! set best to previous best by default
        self%best_class = self%prev_class
        self%best_rot   = prev_roind
        self%prev_rot   = prev_roind
        ! calculate previous best corr (treshold for better)
        call pftcc_glob%gencorrs(self%prev_class, self%iptcl, corrs)
        if( params_glob%cc_objfun == OBJFUN_CC )then
            self%prev_corr  = max(0., corrs(prev_roind))
        else
            self%prev_corr  = corrs(prev_roind)
        endif
        self%best_corr  = self%prev_corr
        ! calculate spectral score
        self%specscore = pftcc_glob%specscore(self%prev_class, self%iptcl, prev_roind)
    end subroutine prep4srch

    subroutine inpl_srch( self )
        class(strategy2D_srch), intent(inout) :: self
        real              :: cxy(3)
        integer           :: irot
        self%best_shvec = [0.,0.]
        if( s2D%do_inplsrch(self%iptcl_map) )then
            ! BFGS
            call self%grad_shsrch_obj%set_indices(self%best_class, self%iptcl)
            if( .not.self%grad_shsrch_obj%does_opt_angle() )then
                ! shift-only optimization
                irot = self%best_rot
            endif
            cxy = self%grad_shsrch_obj%minimize(irot=irot)
            if( irot > 0 )then
                self%best_corr  = cxy(1)
                self%best_rot   = irot
                self%best_shvec = cxy(2:3)
            endif
        endif
    end subroutine inpl_srch

    subroutine store_solution( self, nrefs )
        class(strategy2D_srch), intent(in) :: self
        integer,      optional, intent(in) :: nrefs
        real :: dist, mat(2,2), u(2), x1(2), x2(2)
        real :: e3, mi_class, frac
        ! get in-plane angle
        e3   = 360. - pftcc_glob%get_rot(self%best_rot) ! change sgn to fit convention
        ! calculate in-plane rot dist (radians)
        u(1) = 0.
        u(2) = 1.
        call rotmat2d(e3, mat)
        x1   = matmul(u,mat)
        call rotmat2d(build_glob%spproj_field%e3get(self%iptcl), mat)
        x2   = matmul(u,mat)
        dist = myacos(dot_product(x1,x2))
        ! calculate overlap between distributions
        mi_class = 0.
        if( self%prev_class == self%best_class ) mi_class = 1.
        ! search psace explored
        if( present(nrefs) )then
            frac = 100.*(real(self%nrefs_eval)/real(nrefs))
        else
            frac = 100.*(real(self%nrefs_eval)/real(self%nrefs))
        endif
        ! update parameters
        call build_glob%spproj_field%e3set(self%iptcl,e3)
        call build_glob%spproj_field%set_shift(self%iptcl, self%prev_shvec + self%best_shvec)
        call build_glob%spproj_field%set(self%iptcl, 'shincarg',   arg(self%best_shvec))
        call build_glob%spproj_field%set(self%iptcl, 'inpl',       real(self%best_rot))
        call build_glob%spproj_field%set(self%iptcl, 'class',      real(self%best_class))
        call build_glob%spproj_field%set(self%iptcl, 'corr',       self%best_corr)
        call build_glob%spproj_field%set(self%iptcl, 'specscore',  self%specscore)
        call build_glob%spproj_field%set(self%iptcl, 'dist_inpl',  rad2deg(dist))
        call build_glob%spproj_field%set(self%iptcl, 'mi_class',   mi_class)
        call build_glob%spproj_field%set(self%iptcl, 'frac',       frac)
        call build_glob%spproj_field%set(self%iptcl, 'w',          1.)
    end subroutine store_solution

    subroutine kill( self )
        class(strategy2D_srch),  intent(inout) :: self
        call self%grad_shsrch_obj%kill
        call self%grad_shsrch_obj2%kill
    end subroutine kill

    subroutine squared_sampling( n, corrs, order, nb, ind, rank, cc )
        integer, intent(in)    :: n, nb
        real,    intent(inout) :: corrs(n), cc
        integer, intent(inout) :: order(n), ind, rank
        integer, parameter :: P=2
        real    :: cdf(nb), r
        integer :: i
        if( nb == 1 )then
            rank = n
            ind  = maxloc(corrs,dim=1)
            cc   = corrs(ind)
            return
        endif
        order = (/(i,i=1,n)/)
        call hpsort(corrs, order)
        cdf = corrs(n-nb+1:n)
        if( all(cdf<TINY) )then
            rank = n
            ind  = order(rank)
            cc   = corrs(rank)
            return
        endif
        where( cdf < TINY ) cdf = 0.
        do i = 2,nb
            cdf(i) = cdf(i) + cdf(i-1)
        enddo
        cdf = cdf / sum(cdf)
        r   = ran3()
        r   = 1.-r**P
        rank = 0
        do i = 1,nb
            if( cdf(i) > r )then
                rank = i
                exit
            endif
        enddo
        if( rank == 0 ) rank = nb
        rank = n - nb + rank    ! rank of selected value
        ind  = order(rank)      ! index
        cc   = corrs(rank)      ! value
    end subroutine squared_sampling

end module simple_strategy2D_srch
