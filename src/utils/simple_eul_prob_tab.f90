! orientation eul_prob_tab, used in refine3D
module simple_eul_prob_tab
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_parameters, only: params_glob
use simple_builder,    only: build_glob
implicit none

public :: eul_prob_tab
public :: calc_num2sample, calc_athres, calc_numinpl2sample2D, eulprob_dist_switch, eulprob_corr_switch, shift_sampling
private
#include "simple_local_flags.inc"

logical, parameter :: DEBUG = .false.

type :: eul_prob_tab
    type(ptcl_ref), allocatable :: loc_tab(:,:) !< search table
    type(ptcl_ref), allocatable :: assgn_map(:) !< assignment map
    integer,        allocatable :: pinds(:)     !< particle indices for processing
    integer                     :: nptcls       !< size of pinds array
  contains
    ! CONSTRUCTOR
    procedure :: new
    ! PARTITION-WISE PROCEDURES (used only by partition-wise eul_prob_tab objects)
    procedure :: fill_tab
    procedure :: write_tab
    procedure :: read_assignment
    ! GLOBAL PROCEDURES (used only by the global eul_prob_tab object)
    procedure :: read_tab_to_glob
    procedure :: tab_normalize
    procedure :: tab_align
    procedure :: write_assignment
    ! DESTRUCTOR
    procedure :: kill
end type eul_prob_tab

contains

    ! CONSTRUCTORS

    subroutine new( self, pinds )
        class(eul_prob_tab), intent(inout) :: self
        integer,             intent(in)    :: pinds(:)
        integer :: i, iref, iptcl
        real    :: x
        call self%kill
        self%nptcls = size(pinds)
        if( DEBUG )then
            print *, 'nptcls = ', self%nptcls
            print *, 'pinds  = ', pinds
        endif
        allocate(self%pinds(self%nptcls), source=pinds)
        allocate(self%loc_tab(params_glob%nspace,self%nptcls), self%assgn_map(self%nptcls))
        !$omp parallel do default(shared) private(i,iptcl,iref) proc_bind(close) schedule(static)
        do i = 1,self%nptcls
            iptcl = self%pinds(i)
            self%assgn_map(i)%pind = iptcl
            self%assgn_map(i)%iref = 0
            self%assgn_map(i)%inpl = 0
            self%assgn_map(i)%dist = huge(x)
            do iref = 1,params_glob%nspace
                self%loc_tab(iref,i)%pind = iptcl
                self%loc_tab(iref,i)%iref = iref
                self%loc_tab(iref,i)%inpl = 0
                self%loc_tab(iref,i)%dist = huge(x)
            end do
        end do
        !$omp end parallel do 
    end subroutine new

    ! partition-wise table filling, used only in shared-memory commander 'exec_prob_tab'
    subroutine fill_tab( self, pftcc )
        use simple_polarft_corrcalc,  only: polarft_corrcalc
        use simple_pftcc_shsrch_grad, only: pftcc_shsrch_grad  ! gradient-based in-plane angle and shift search
        class(eul_prob_tab),     intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,      parameter :: MAXITS = 60
        integer,    allocatable :: locn(:)
        type(pftcc_shsrch_grad) :: grad_shsrch_obj(nthr_glob) !< origin shift search object, L-BFGS with gradient
        integer :: i, j, iref, iptcl, refs_ns, ithr, irot, inds_sorted(pftcc%nrots,nthr_glob)
        real    :: dists_inpl(pftcc%nrots,nthr_glob), dists_inpl_sorted(pftcc%nrots,nthr_glob)
        real    :: dists_refs(pftcc%nrefs,nthr_glob), lims(2,2), lims_init(2,2), cxy(3), inpl_athres
        call seed_rnd
        inpl_athres = calc_athres('dist_inpl')
        call calc_num2sample(params_glob%nspace, 'dist', refs_ns)
        if( params_glob%l_prob_sh )then
            allocate(locn(refs_ns), source=0)
            ! make shift search objects
            lims(:,1)      = -params_glob%trs
            lims(:,2)      =  params_glob%trs
            lims_init(:,1) = -SHC_INPL_TRSHWDTH
            lims_init(:,2) =  SHC_INPL_TRSHWDTH
            do ithr = 1,nthr_glob
                call grad_shsrch_obj(ithr)%new(lims, lims_init=lims_init, shbarrier=params_glob%shbarrier, maxits=MAXITS, opt_angle=.false.)
            end do
            ! fill the table
            !$omp parallel do default(shared) private(i,j,iptcl,ithr,iref,irot,cxy,locn) proc_bind(close) schedule(static)
            do i = 1, self%nptcls
                iptcl = self%pinds(i)
                ithr  = omp_get_thread_num() + 1
                do iref = 1, params_glob%nspace
                    call pftcc%gencorrs(iref, iptcl, dists_inpl(:,ithr))
                    dists_inpl(:,ithr) = eulprob_dist_switch(dists_inpl(:,ithr))
                    irot = angle_sampling(dists_inpl(:,ithr), dists_inpl_sorted(:,ithr), inds_sorted(:,ithr), inpl_athres)
                    self%loc_tab(iref,i)%dist = dists_inpl(irot,ithr)
                    self%loc_tab(iref,i)%inpl = irot
                    dists_refs(iref,ithr)     = dists_inpl(irot,ithr)
                enddo
                locn = minnloc(dists_refs(:,ithr), refs_ns)
                if( params_glob%l_doshift )then
                    do j = 1,refs_ns
                        iref = locn(j)
                        ! BFGS over shifts
                        call grad_shsrch_obj(ithr)%set_indices(iref, iptcl)
                        irot = self%loc_tab(iref,i)%inpl
                        cxy  = grad_shsrch_obj(ithr)%minimize(irot=irot)
                        if( irot > 0 )then
                            ! no storing of shifts for now, re-search with in-plane jiggle in strategy3D_prob
                            self%loc_tab(iref,i)%dist = eulprob_dist_switch(cxy(1))
                        endif
                    end do
                endif
            enddo
            !$omp end parallel do
        else
            ! fill the table
            !$omp parallel do collapse(2) default(shared) private(i,ithr,iref,iptcl,irot) proc_bind(close) schedule(static)
            do iref = 1, params_glob%nspace
                do i = 1, self%nptcls
                    iptcl = self%pinds(i)
                    ithr  = omp_get_thread_num() + 1
                    call pftcc%gencorrs(iref, iptcl, dists_inpl(:,ithr))
                    dists_inpl(:,ithr) = eulprob_dist_switch(dists_inpl(:,ithr))
                    irot = angle_sampling(dists_inpl(:,ithr), dists_inpl_sorted(:,ithr), inds_sorted(:,ithr), inpl_athres)
                    self%loc_tab(iref,i)%dist = dists_inpl(irot,ithr)
                    self%loc_tab(iref,i)%inpl = irot
                enddo
            enddo
            !$omp end parallel do
        endif
    end subroutine fill_tab

    ! reference normalization (same energy) of the global dist value table
    ! [0,1] normalization of the whole table
    ! used in the global prob_align commander, in 'exec_prob_align'
    subroutine tab_normalize( self )
        class(eul_prob_tab), intent(inout) :: self
        real    :: sum_dist_all, min_dist, max_dist
        integer :: i
        ! normalize so prob of each ptcl is between [0,1] for all refs
        !$omp parallel do default(shared) proc_bind(close) schedule(static) private(i,sum_dist_all)
        do i = 1, self%nptcls
            sum_dist_all = sum(self%loc_tab(:,i)%dist)
            if( sum_dist_all < TINY )then
                self%loc_tab(:,i)%dist = 0.
            else
                self%loc_tab(:,i)%dist = self%loc_tab(:,i)%dist / sum_dist_all
            endif
        enddo
        !$omp end parallel do
        ! min/max normalization to obtain values between 0 and 1
        max_dist = 0.
        min_dist = huge(min_dist)
        !$omp parallel do default(shared) proc_bind(close) schedule(static) private(i)&
        !$omp reduction(min:min_dist) reduction(max:max_dist)
        do i = 1, self%nptcls
            max_dist = max(max_dist, maxval(self%loc_tab(:,i)%dist, dim=1))
            min_dist = min(min_dist, minval(self%loc_tab(:,i)%dist, dim=1))
        enddo
        !$omp end parallel do
        if( (max_dist - min_dist) < TINY )then
            self%loc_tab%dist = 0.
        else
            self%loc_tab%dist = (self%loc_tab%dist - min_dist) / (max_dist - min_dist)
        endif
    end subroutine tab_normalize

    ! ptcl -> ref assignment using the global normalized dist value table
    ! used in the global prob_align commander, in 'exec_prob_align'
    subroutine tab_align( self )
        class(eul_prob_tab), intent(inout) :: self
        integer :: i, iref, assigned_iref, assigned_ptcl, ref_dist_inds(params_glob%nspace),&
                   &stab_inds(self%nptcls, params_glob%nspace), inds_sorted(params_glob%nspace)
        real    :: sorted_tab(self%nptcls, params_glob%nspace), refs_athres,&
                   &ref_dist(params_glob%nspace), dists_sorted(params_glob%nspace)
        logical :: ptcl_avail(self%nptcls)
        ! sorting each columns
        refs_athres = calc_athres('dist')
        sorted_tab  = transpose(self%loc_tab(:,:)%dist)
        !$omp parallel do default(shared) proc_bind(close) schedule(static) private(iref,i)
        do iref = 1, params_glob%nspace
            stab_inds(:,iref) = (/(i,i=1,self%nptcls)/)
            call hpsort(sorted_tab(:,iref), stab_inds(:,iref))
        enddo
        !$omp end parallel do
        ! first row is the current best ref distribution
        ref_dist_inds = 1
        ref_dist      = sorted_tab(1,:)
        ptcl_avail    = .true.
        do while( any(ptcl_avail) )
            ! sampling the ref distribution to choose next iref to assign
            assigned_iref = angle_sampling(ref_dist, dists_sorted, inds_sorted, refs_athres)
            assigned_ptcl = stab_inds(ref_dist_inds(assigned_iref), assigned_iref)
            ptcl_avail(assigned_ptcl)          = .false.
            self%assgn_map(assigned_ptcl)%iref = assigned_iref
            self%assgn_map(assigned_ptcl)%dist = self%loc_tab(assigned_iref,assigned_ptcl)%dist
            self%assgn_map(assigned_ptcl)%inpl = self%loc_tab(assigned_iref,assigned_ptcl)%inpl
            ! update the ref_dist and ref_dist_inds
            do iref = 1, params_glob%nspace
                do while( ref_dist_inds(iref) < self%nptcls .and. .not.(ptcl_avail(stab_inds(ref_dist_inds(iref), iref))))
                    ref_dist_inds(iref) = ref_dist_inds(iref) + 1
                    ref_dist(iref)      = sorted_tab(ref_dist_inds(iref), iref)
                enddo
            enddo
        enddo
    end subroutine tab_align

    ! FILE IO

    ! write the partition-wise (or global) dist value table to a binary file
    subroutine write_tab( self, binfname )
        class(eul_prob_tab), intent(in) :: self
        character(len=*),    intent(in) :: binfname
        integer :: funit, addr, io_stat, file_header(2)
        file_header(1) = params_glob%nspace
        file_header(2) = self%nptcls
        call fopen(funit,trim(binfname),access='STREAM',action='WRITE',status='REPLACE', iostat=io_stat)
        write(unit=funit,pos=1) file_header
        addr = sizeof(file_header) + 1
        write(funit,pos=addr) self%loc_tab
        call fclose(funit)
    end subroutine write_tab

    ! read the partition-wise dist value binary file to global reg object's dist value table
    subroutine read_tab_to_glob( self, binfname, nptcls_glob )
        class(eul_prob_tab), intent(inout) :: self
        character(len=*),    intent(in)    :: binfname
        integer,             intent(in)    :: nptcls_glob
        type(ptcl_ref),      allocatable   :: mat_loc(:,:)
        integer :: funit, addr, io_stat, file_header(2), nptcls_loc, nrefs_loc, i_loc, i_glob
        if( file_exists(trim(binfname)) )then
            call fopen(funit,trim(binfname),access='STREAM',action='READ',status='OLD', iostat=io_stat)
            call fileiochk('simple_eul_prob_tab; read_tab_to_glob; file: '//trim(binfname), io_stat)
        else
            THROW_HARD( 'corr/rot files of partitions should be ready! ' )
        endif
        ! reading header and the nrefs/nptcls in this partition file
        read(unit=funit,pos=1) file_header
        nrefs_loc  = file_header(1)
        nptcls_loc = file_header(2)
        allocate(mat_loc(nrefs_loc, nptcls_loc))
        if( nrefs_loc .ne. params_glob%nspace ) THROW_HARD( 'npsace should be the same as nrefs in this partition file!' )
        ! read partition information
        addr = sizeof(file_header) + 1
        read(unit=funit,pos=addr) mat_loc
        call fclose(funit)
        !$omp parallel do collapse(2) default(shared) proc_bind(close) schedule(static) private(i_loc,i_glob)
        do i_loc = 1, nptcls_loc
            do i_glob = 1, nptcls_glob
                if( mat_loc(1,i_loc)%pind == self%loc_tab(1,i_glob)%pind ) self%loc_tab(:,i_glob) = mat_loc(:,i_loc)
            end do
        end do
        !$omp end parallel do
    end subroutine read_tab_to_glob

    ! write a global assignment map to binary file
    subroutine write_assignment( self, binfname )
        class(eul_prob_tab), intent(in) :: self
        character(len=*),    intent(in) :: binfname
        integer :: funit, io_stat, headsz
        headsz = sizeof(self%nptcls)
        call fopen(funit,trim(binfname),access='STREAM',action='WRITE',status='REPLACE', iostat=io_stat)
        write(unit=funit,pos=1)          self%nptcls
        write(unit=funit,pos=headsz + 1) self%assgn_map
        call fclose(funit)
        if( DEBUG )then
            print *, 'MASTER ----'
            print *, 'pinds = ', self%assgn_map(:)%pind
            print *, 'irefs = ', self%assgn_map(:)%iref
            print *, 'inpls = ', self%assgn_map(:)%inpl
        endif
    end subroutine write_assignment

    ! read from the global assignment map to local partition for shift search and further refinement
    subroutine read_assignment( self, binfname )
        class(eul_prob_tab), intent(inout) :: self
        character(len=*),    intent(in)    :: binfname
        type(ptcl_ref),      allocatable   :: assgn_glob(:)
        integer :: funit, io_stat, nptcls_glob, headsz, i_loc, i_glob
        headsz = sizeof(nptcls_glob)
        if( .not. file_exists(trim(binfname)) )then
            THROW_HARD('file '//trim(binfname)//' does not exists!')
        else
            call fopen(funit,trim(binfname),access='STREAM',action='READ',status='OLD', iostat=io_stat)
        end if
        call fileiochk('read_tab_to_glob; read_assignment; file: '//trim(binfname), io_stat)
        read(unit=funit,pos=1) nptcls_glob
        allocate(assgn_glob(nptcls_glob))
        read(unit=funit,pos=headsz + 1) assgn_glob
        call fclose(funit)
        !$omp parallel do collapse(2) default(shared) proc_bind(close) schedule(static) private(i_loc,i_glob)
        do i_loc = 1, self%nptcls
            do i_glob = 1, nptcls_glob
                if( self%assgn_map(i_loc)%pind == assgn_glob(i_glob)%pind )then
                    self%assgn_map(i_loc) = assgn_glob(i_glob)
                endif
            end do
        end do
        !$omp end parallel do
        if( DEBUG )then
            print *, 'PARTITION ----'
            print *, 'pinds = ', self%assgn_map(:)%pind
            print *, 'irefs = ', self%assgn_map(:)%iref
            print *, 'inpls = ', self%assgn_map(:)%inpl
        endif
    end subroutine read_assignment

    ! DESTRUCTOR

    subroutine kill( self )
        class(eul_prob_tab), intent(inout) :: self
        if( allocated(self%loc_tab)   ) deallocate(self%loc_tab)
        if( allocated(self%assgn_map) ) deallocate(self%assgn_map)
        if( allocated(self%pinds)     ) deallocate(self%pinds)
    end subroutine kill

    ! PUBLIC UTILITITES

    subroutine calc_num2sample( num_all, field_str, num_smpl)
        use simple_builder, only: build_glob
        integer,          intent(in)  :: num_all
        character(len=*), intent(in)  :: field_str
        integer,          intent(out) :: num_smpl
        real, allocatable :: vals(:)
        real :: athres, dist_thres
        vals       = build_glob%spproj_field%get_all_sampled(trim(field_str))
        dist_thres = sum(vals) / real(size(vals))
        athres     = params_glob%prob_athres
        if( dist_thres > TINY ) athres = min(athres, dist_thres)
        num_smpl   = min(num_all,max(1,int(athres * real(num_all) / 180.)))
    end subroutine calc_num2sample

    function calc_athres( field_str ) result( athres )
        use simple_builder, only: build_glob
        character(len=*), intent(in) :: field_str
        real, allocatable :: vals(:)
        real :: athres, dist_thres
        vals       = build_glob%spproj_field%get_all_sampled(trim(field_str))
        dist_thres = sum(vals) / real(size(vals))
        athres     = params_glob%prob_athres
        if( dist_thres > TINY ) athres = min(athres, dist_thres)
    end function calc_athres

    subroutine calc_numinpl2sample2D( num_all, num_smpl )

        !!!!!!!!!!!!!! NEEDS TO CHANGE, SEE ABOVE

        use simple_builder, only: build_glob
        integer, intent(in)  :: num_all
        integer, intent(out) :: num_smpl
        real,    allocatable :: vals(:)
        logical, allocatable :: ptcl_mask(:)
        real    :: athres, dist_thres
        integer :: n
        ptcl_mask  = nint(build_glob%spproj_field%get_all('state')) == 1
        ptcl_mask  = ptcl_mask .and. (nint(build_glob%spproj_field%get_all('mi_class')) == 1)
        n          = count(ptcl_mask)
        athres     = params_glob%prob_athres
        if( n > 0 )then
            vals       = build_glob%spproj_field%get_all(trim('dist_inpl'))
            dist_thres = sum(vals, mask=ptcl_mask) / real(n)
            if( dist_thres > TINY ) athres = min(athres, dist_thres)
        endif
        num_smpl = min(num_all,max(1,int(athres * real(num_all) / 180.)))
    end subroutine calc_numinpl2sample2D

    ! switch corr in [0,1] to [0, infinity) to do greedy_sampling
    elemental function eulprob_dist_switch( corr ) result(dist)
        real, intent(in) :: corr
        real :: dist
        select case(params_glob%cc_objfun)
            case(OBJFUN_CC)
                if( corr < 0. )then
                    dist = 0.
                else
                    dist = corr
                endif
                dist = 1. - dist
            case(OBJFUN_EUCLID)
                if( corr < TINY )then
                    dist = huge(dist)
                else
                    dist = - log(corr)
                endif
        end select
    end function eulprob_dist_switch

    ! switch corr in [0,1] to [0, infinity) to do greedy_sampling
    elemental function eulprob_corr_switch( dist ) result(corr)
        real, intent(in) :: dist
        real :: corr
        select case(params_glob%cc_objfun)
            case(OBJFUN_CC)
                corr = 1 - dist
            case(OBJFUN_EUCLID)
                corr = exp(-dist)
        end select
    end function eulprob_corr_switch

    function angle_sampling( pvec, pvec_sorted, sorted_inds, thres_bound ) result( which )
        real,    intent(in)    :: pvec(:)             !< probabilities
        real,    intent(inout) :: pvec_sorted(:)      !< sorted probabilities
        integer, intent(inout) :: sorted_inds(:)
        real,    intent(in)    :: thres_bound
        integer :: which, num_safe, num_smpl, n
        real    :: athres
        n        = size(pvec)
        athres   = min(params_glob%prob_athres, thres_bound)
        num_smpl = min(n,max(1,int(athres * real(n) / 180.)))
        num_safe = 1
        if( params_glob%l_angle_smpl .and. thres_bound > ANGLE_SAFE ) num_safe = 1 + floor(ANGLE_SAFE / athres * num_smpl)
        which    = greedy_sampling( pvec, pvec_sorted, sorted_inds, num_smpl, num_safe )
    end function angle_sampling

    ! shift multinomal sampling within a threshold, units are in Ang
    function shift_sampling( cur_sh, thres_bound ) result(sh)
        real,              intent(in) :: cur_sh(2)
        real,    optional, intent(in) :: thres_bound
        integer, parameter   :: N_SMPL  = 100
        real,    allocatable :: vals(:)
        integer :: i, sh_signs(2), which, dim, n_safe
        real    :: sh(2)
        real    :: d_sh, gauss_sh(N_SMPL), sh_vals(N_SMPL), sig2, d_thres, thres
        if( present(thres_bound) )then
            thres = thres_bound
        else
            vals  = build_glob%spproj_field%get_all_sampled(trim('shincarg'))
            thres = sum(vals) / real(size(vals))
            thres = thres / 2.
        endif
        sh = cur_sh
        if( thres < TINY ) return
        ! randomly pick the plus/minus for each x,y dimensions
        sh_signs = 1
        if( ran3() < 0.5 ) sh_signs(1) = -1
        if( ran3() < 0.5 ) sh_signs(2) = -1
        ! sampling for x
        d_sh   = thres / real(N_SMPL-1)
        n_safe = 1
        if( thres > SH_SAFE ) n_safe = 1 + floor(SH_SAFE / d_sh)
        sig2   = thres**2.
        do dim = 1, 2
            do i = 1, N_SMPL
                d_thres     = d_sh * real(i - 1)
                gauss_sh(i) = gaussian1D(d_thres, avg=0., sigma_sq=sig2)
                sh_vals(i)  = d_thres
            enddo
            gauss_sh = (1. - gauss_sh)
            gauss_sh = gauss_sh / sum(gauss_sh)
            which    = greedy_sampling( gauss_sh, N_SMPL, n_safe )
            sh(dim)  = cur_sh(dim) + real(sh_signs(dim)) * sh_vals(which)
        enddo
    end function shift_sampling

end module simple_eul_prob_tab
