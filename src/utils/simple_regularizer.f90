! regularizer of the cluster2D and refine3D
module simple_regularizer
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_parameters,        only: params_glob
use simple_builder,           only: build_glob
use simple_ori,               only: geodesic_frobdev
use simple_polarft_corrcalc,  only: polarft_corrcalc
use simple_pftcc_shsrch_grad, only: pftcc_shsrch_grad  ! gradient-based in-plane angle and shift search
use simple_opt_filter,        only: butterworth_filter
use simple_image
implicit none

public :: regularizer
private
#include "simple_local_flags.inc"

type reg_params
    integer :: iptcl                       !< iptcl index
    integer :: iref                        !< iref index
    integer :: loc                         !< inpl index
    real    :: prob, sh(2)                 !< probability, shift
end type reg_params

type :: regularizer
    integer                  :: nrots
    integer                  :: nrefs
    integer                  :: pftsz
    integer                  :: kfromto(2)
    complex(dp), allocatable :: regs_odd(:,:,:)             !< -"-, reg terms
    complex(dp), allocatable :: regs_even(:,:,:)            !< -"-, reg terms
    real(dp),    allocatable :: regs_denom_odd(:,:,:)       !< -"-, reg denom
    real(dp),    allocatable :: regs_denom_even(:,:,:)      !< -"-, reg denom
    real,        allocatable :: ref_ptcl_cor(:,:)           !< 2D corr table
    integer,     allocatable :: ptcl_ref_map(:)             !< hard-alignment tab
    class(polarft_corrcalc), pointer     :: pftcc => null()
    type(reg_params),        allocatable :: ref_ptcl_tab(:,:)
    contains
    ! CONSTRUCTOR
    procedure          :: new
    ! PROCEDURES
    procedure          :: init_tab
    procedure          :: fill_tab_noshift
    procedure          :: fill_tab_inpl_sto
    procedure          :: prev_cavgs
    procedure          :: compute_cavgs
    procedure          :: output_reproj_cavgs
    procedure          :: tab_align
    procedure          :: uni_align
    procedure          :: nonuni_greedy_align
    procedure          :: nonuni_sto_ptcl_align
    procedure          :: nonuni_sto_ref_align
    procedure          :: find_closest_iref
    procedure          :: reset_regs
    procedure, private :: calc_raw_frc, calc_pspec
    procedure, private :: rotate_polar_real, rotate_polar_complex, rotate_polar_test
    generic            :: rotate_polar => rotate_polar_real, rotate_polar_complex, rotate_polar_test
    ! DESTRUCTOR
    procedure          :: kill
end type regularizer

contains
    ! CONSTRUCTORS

    subroutine new( self, pftcc )
        class(regularizer),      target, intent(inout) :: self
        class(polarft_corrcalc), target, intent(inout) :: pftcc
        self%nrots   = pftcc%nrots
        self%nrefs   = pftcc%nrefs
        self%pftsz   = pftcc%pftsz
        self%kfromto = pftcc%kfromto
        ! allocation
        allocate(self%regs_denom_even(self%pftsz,self%kfromto(1):self%kfromto(2),self%nrefs),&
                &self%regs_denom_odd( self%pftsz,self%kfromto(1):self%kfromto(2),self%nrefs),&
                &self%regs_even(self%pftsz,self%kfromto(1):self%kfromto(2),self%nrefs),&
                &self%regs_odd( self%pftsz,self%kfromto(1):self%kfromto(2),self%nrefs))
        self%regs_odd        = 0.d0
        self%regs_even       = 0.d0
        self%regs_denom_odd  = 0.d0
        self%regs_denom_even = 0.d0
        self%pftcc      => pftcc
    end subroutine new

    subroutine init_tab( self )
        class(regularizer), intent(inout) :: self
        integer :: iptcl, iref
        if( .not.(allocated(self%ref_ptcl_cor)) )then
            allocate(self%ref_ptcl_cor(self%nrefs,params_glob%fromp:params_glob%top), source=0.)
            allocate(self%ref_ptcl_tab(self%nrefs,params_glob%fromp:params_glob%top))
            allocate(self%ptcl_ref_map(params_glob%fromp:params_glob%top))
        endif
        self%ref_ptcl_cor = 0.
        do iref = 1,self%nrefs
            do iptcl = params_glob%fromp,params_glob%top
                self%ref_ptcl_tab(iref,iptcl)%iptcl = iptcl
                self%ref_ptcl_tab(iref,iptcl)%iref  = iref
                self%ref_ptcl_tab(iref,iptcl)%loc   = 0
                self%ref_ptcl_tab(iref,iptcl)%prob  = 0.
                self%ref_ptcl_tab(iref,iptcl)%sh    = 0.
            enddo
        enddo
    end subroutine init_tab

    subroutine fill_tab_noshift( self, glob_pinds )
        class(regularizer), intent(inout) :: self
        integer,            intent(in)    :: glob_pinds(self%pftcc%nptcls)
        integer   :: i, iref, iptcl
        real      :: inpl_corrs(self%nrots)
        !$omp parallel do collapse(2) default(shared) private(i,iref,iptcl,inpl_corrs) proc_bind(close) schedule(static)
        do iref = 1, self%nrefs
            do i = 1, self%pftcc%nptcls
                iptcl = glob_pinds(i)
                ! find best irot/shift for this pair of iref, iptcl
                call self%pftcc%gencorrs( iref, iptcl, inpl_corrs )
                self%ref_ptcl_tab(iref,iptcl)%sh  = 0.
                self%ref_ptcl_tab(iref,iptcl)%loc = maxloc(inpl_corrs, dim=1)
                self%ref_ptcl_cor(iref,iptcl)     = max(0., inpl_corrs(self%ref_ptcl_tab(iref,iptcl)%loc))
            enddo
        enddo
        !$omp end parallel do
    end subroutine fill_tab_noshift

    subroutine fill_tab_inpl_sto( self, glob_pinds )
        class(regularizer), intent(inout) :: self
        integer,            intent(in)    :: glob_pinds(self%pftcc%nptcls)
        integer   :: i, iref, iptcl, indxarr(self%nrots), j, irnd
        real      :: inpl_corrs(self%nrots), rnd_num
        call seed_rnd
        !$omp parallel do collapse(2) default(shared) private(i,j,iref,iptcl,inpl_corrs,indxarr,rnd_num,irnd) proc_bind(close) schedule(static)
        do iref = 1, self%nrefs
            do i = 1, self%pftcc%nptcls
                iptcl = glob_pinds(i)
                ! find best irot/shift for this pair of iref, iptcl
                call self%pftcc%gencorrs( iref, iptcl, inpl_corrs )
                where( inpl_corrs < TINY ) inpl_corrs = 0.
                indxarr = (/(j,j=1,self%nrots)/)
                call hpsort(inpl_corrs, indxarr)
                call reverse(indxarr)
                call reverse(inpl_corrs)
                call random_number(rnd_num)
                irnd = 1 + floor(params_glob%reg_nrots * rnd_num)
                self%ref_ptcl_tab(iref,iptcl)%sh  = 0.
                self%ref_ptcl_tab(iref,iptcl)%loc =    indxarr(irnd)
                self%ref_ptcl_cor(iref,iptcl)     = inpl_corrs(irnd)
            enddo
        enddo
        !$omp end parallel do
    end subroutine fill_tab_inpl_sto

    subroutine compute_cavgs( self )
        class(regularizer), intent(inout) :: self
        integer     :: iptcl, iref, loc, pind_here
        complex     :: ptcl_ctf(self%pftsz,self%kfromto(1):self%kfromto(2),self%pftcc%nptcls)
        complex(dp) :: ptcl_ctf_rot(self%pftsz,self%kfromto(1):self%kfromto(2))
        real(dp)    :: ctf_rot(self%pftsz,self%kfromto(1):self%kfromto(2))
        ptcl_ctf = self%pftcc%pfts_ptcls * self%pftcc%ctfmats
        do iptcl = params_glob%fromp, params_glob%top
            if( iptcl >= self%pftcc%pfromto(1) .and. iptcl <= self%pftcc%pfromto(2))then
                iref = self%ptcl_ref_map(iptcl)
                pind_here = self%pftcc%pinds(iptcl)
                ! computing the reg terms as the gradients w.r.t 2D references of the probability
                loc = self%ref_ptcl_tab(iref, iptcl)%loc
                loc = (self%nrots+1)-(loc-1)
                if( loc > self%nrots ) loc = loc - self%nrots
                call self%rotate_polar(cmplx(ptcl_ctf(:,:,pind_here), kind=dp), ptcl_ctf_rot, loc)
                call self%rotate_polar(self%pftcc%ctfmats(:,:,pind_here),            ctf_rot, loc)
                if( params_glob%l_lpset )then
                    if( self%pftcc%ptcl_iseven(iptcl) )then
                        self%regs_even(:,:,iref)       = self%regs_even(:,:,iref)       + ptcl_ctf_rot
                        self%regs_denom_even(:,:,iref) = self%regs_denom_even(:,:,iref) + ctf_rot**2
                    else
                        self%regs_odd(:,:,iref)       = self%regs_odd(:,:,iref)       + ptcl_ctf_rot
                        self%regs_denom_odd(:,:,iref) = self%regs_denom_odd(:,:,iref) + ctf_rot**2
                    endif
                else
                    self%regs_even(:,:,iref)       = self%regs_even(:,:,iref)       + ptcl_ctf_rot
                    self%regs_denom_even(:,:,iref) = self%regs_denom_even(:,:,iref) + ctf_rot**2
                    self%regs_odd(:,:,iref)        = self%regs_odd(:,:,iref)        + ptcl_ctf_rot
                    self%regs_denom_odd(:,:,iref)  = self%regs_denom_odd(:,:,iref)  + ctf_rot**2
                endif
            endif
        enddo
    end subroutine compute_cavgs

    subroutine prev_cavgs( self )
        class(regularizer), intent(inout) :: self
        type(ori)   :: o_prev
        integer     :: iptcl, iref, loc, pind_here
        complex     :: ptcl_ctf(self%pftsz,self%kfromto(1):self%kfromto(2),self%pftcc%nptcls)
        complex(dp) :: ptcl_ctf_rot(self%pftsz,self%kfromto(1):self%kfromto(2))
        real(dp)    :: ctf_rot(self%pftsz,self%kfromto(1):self%kfromto(2))
        ptcl_ctf = self%pftcc%pfts_ptcls * self%pftcc%ctfmats
        do iptcl = params_glob%fromp, params_glob%top
            if( iptcl >= self%pftcc%pfromto(1) .and. iptcl <= self%pftcc%pfromto(2))then
                call build_glob%spproj_field%get_ori(iptcl, o_prev)     ! previous ori
                iref      = build_glob%eulspace%find_closest_proj(o_prev)   ! previous projection direction
                pind_here = self%pftcc%pinds(iptcl)
                ! computing the reg terms as the gradients w.r.t 2D references of the probability
                loc = self%ref_ptcl_tab(iref, iptcl)%loc
                loc = (self%nrots+1)-(loc-1)
                if( loc > self%nrots ) loc = loc - self%nrots
                call self%rotate_polar(cmplx(ptcl_ctf(:,:,pind_here), kind=dp), ptcl_ctf_rot, loc)
                call self%rotate_polar(self%pftcc%ctfmats(:,:,pind_here), ctf_rot, loc)
                if( params_glob%l_lpset )then
                    if( self%pftcc%ptcl_iseven(iptcl) )then
                        self%regs_even(:,:,iref)       = self%regs_even(:,:,iref)       + ptcl_ctf_rot
                        self%regs_denom_even(:,:,iref) = self%regs_denom_even(:,:,iref) + ctf_rot**2
                    else
                        self%regs_odd(:,:,iref)       = self%regs_odd(:,:,iref)       + ptcl_ctf_rot
                        self%regs_denom_odd(:,:,iref) = self%regs_denom_odd(:,:,iref) + ctf_rot**2
                    endif
                else
                    self%regs_even(:,:,iref)       = self%regs_even(:,:,iref)       + ptcl_ctf_rot
                    self%regs_denom_even(:,:,iref) = self%regs_denom_even(:,:,iref) + ctf_rot**2
                    self%regs_odd(:,:,iref)        = self%regs_odd(:,:,iref)        + ptcl_ctf_rot
                    self%regs_denom_odd(:,:,iref)  = self%regs_denom_odd(:,:,iref)  + ctf_rot**2
                endif
            endif
        enddo
    end subroutine prev_cavgs

    subroutine tab_align( self )
        class(regularizer), intent(inout) :: self
        integer :: iref, iptcl
        real    :: sum_corr
        ! normalize so prob of each ptcl is between [0,1] for all refs
        if( params_glob%l_reg_norm )then
            !$omp parallel do default(shared) proc_bind(close) schedule(static) private(iptcl, sum_corr)
            do iptcl = params_glob%fromp, params_glob%top
                sum_corr = sum(self%ref_ptcl_cor(:,iptcl))
                if( sum_corr < DTINY )then
                    self%ref_ptcl_cor(:,iptcl) = 0.
                else
                    self%ref_ptcl_cor(:,iptcl) = self%ref_ptcl_cor(:,iptcl) / sum_corr
                endif
            enddo
            !$omp end parallel do
        endif
        self%ref_ptcl_cor = self%ref_ptcl_cor / maxval(self%ref_ptcl_cor)
        !$omp parallel do default(shared) proc_bind(close) schedule(static) collapse(2) private(iref,iptcl)
        do iref = 1, self%nrefs
            do iptcl = params_glob%fromp,params_glob%top
                self%ref_ptcl_tab(iref,iptcl)%prob = self%ref_ptcl_cor(iref,iptcl)
            enddo
        enddo
        !$omp end parallel do
        ! sorted clustering
        self%ptcl_ref_map = 1
        call self%nonuni_sto_ref_align
    end subroutine tab_align

    subroutine uni_align( self )
        class(regularizer), intent(inout) :: self
        integer   :: ir, ip, max_ind_ir, max_ind_ip, max_ip(self%nrefs), next_ir
        real      :: max_ir(self%nrefs)
        logical   :: mask_ir(self%nrefs), mask_ip(params_glob%fromp:params_glob%top)
        mask_ir = .false.
        mask_ip = .true.
        do
            if( .not.(any(mask_ip)) ) return
            if( .not.(any(mask_ir)) )then
                mask_ir = .true.
                max_ir  = -1.
                !$omp parallel do default(shared) proc_bind(close) schedule(static) private(ir,ip)
                do ir = 1, self%nrefs
                    if( mask_ir(ir) )then
                        do ip = params_glob%fromp, params_glob%top
                            if( mask_ip(ip) .and. self%ref_ptcl_tab(ir, ip)%prob > max_ir(ir) )then
                                max_ir(ir) = self%ref_ptcl_tab(ir, ip)%prob
                                max_ip(ir) = ip
                            endif
                        enddo
                    endif
                enddo
                !$omp end parallel do
                max_ind_ir = maxloc(max_ir, dim=1, mask=mask_ir)
                max_ind_ip = max_ip(max_ind_ir)
                self%ptcl_ref_map(max_ind_ip) = max_ind_ir
                mask_ip(max_ind_ip) = .false.
                mask_ir(max_ind_ir) = .false.
                next_ir = self%find_closest_iref(max_ind_ir, mask_ir)
            else
                max_ir(next_ir) = -1.
                do ip = params_glob%fromp, params_glob%top
                    if( mask_ip(ip) .and. self%ref_ptcl_tab(next_ir, ip)%prob > max_ir(next_ir) )then
                        max_ir(next_ir) = self%ref_ptcl_tab(next_ir, ip)%prob
                        max_ind_ip = ip
                    endif
                enddo
                self%ptcl_ref_map(max_ind_ip) = next_ir
                mask_ip(max_ind_ip) = .false.
                mask_ir(next_ir)    = .false.
                next_ir             = self%find_closest_iref(next_ir, mask_ir)
            endif
        enddo
    end subroutine uni_align

    subroutine nonuni_greedy_align( self )
        class(regularizer), intent(inout) :: self
        integer   :: ir, ip, max_ind_ir, max_ind_ip, max_ip(self%nrefs)
        real      :: max_ir(self%nrefs)
        logical   :: mask_ip(params_glob%fromp:params_glob%top)
        mask_ip = .true.
        do while( any(mask_ip) )
            max_ir  = -1.
            !$omp parallel do default(shared) proc_bind(close) schedule(static) private(ir,ip)
            do ir = 1, self%nrefs
                do ip = params_glob%fromp, params_glob%top
                    if( mask_ip(ip) .and. self%ref_ptcl_cor(ir,ip) > max_ir(ir) )then
                        max_ir(ir) = self%ref_ptcl_cor(ir,ip)
                        max_ip(ir) = ip
                    endif
                enddo
            enddo
            !$omp end parallel do
            max_ind_ir = maxloc(max_ir, dim=1)
            max_ind_ip = max_ip(max_ind_ir)
            self%ptcl_ref_map(max_ind_ip) = max_ind_ir
            mask_ip(max_ind_ip) = .false.
        enddo
    end subroutine nonuni_greedy_align

    subroutine nonuni_sto_ptcl_align( self )
        class(regularizer), intent(inout) :: self
        integer   :: ir, ip, max_ind_ir, max_ind_ip, max_ip(self%nrefs), indxarr(params_glob%fromp:params_glob%top)
        real      :: max_ir(self%nrefs), temp_corr(params_glob%fromp:params_glob%top), rnd_num
        logical   :: mask_ip(params_glob%fromp:params_glob%top)
        mask_ip = .true.
        call seed_rnd
        do while( any(mask_ip) )
            max_ir  = -1.
            !$omp parallel do default(shared) proc_bind(close) schedule(static) private(ir,ip,indxarr,temp_corr,rnd_num)
            do ir = 1, self%nrefs
                indxarr   = (/(ip,ip=params_glob%fromp, params_glob%top)/)
                temp_corr = self%ref_ptcl_cor(ir,:)
                do ip = params_glob%fromp, params_glob%top
                    if( .not.(mask_ip(ip)) ) temp_corr(ip) = 0.
                enddo
                call hpsort(temp_corr, indxarr)
                call reverse(indxarr)
                call random_number(rnd_num)
                ip = indxarr(1 + floor(min(params_glob%reg_nrots, count(mask_ip)) * rnd_num))
                max_ir(ir) = self%ref_ptcl_cor(ir,ip)
                max_ip(ir) = ip
            enddo
            !$omp end parallel do
            max_ind_ir = maxloc(max_ir, dim=1)
            max_ind_ip = max_ip(max_ind_ir)
            self%ptcl_ref_map(max_ind_ip) = max_ind_ir
            mask_ip(max_ind_ip) = .false.
        enddo
    end subroutine nonuni_sto_ptcl_align

    subroutine nonuni_sto_ref_align( self )
        class(regularizer), intent(inout) :: self
        integer   :: ir, ip, max_ind_ir, max_ind_ip, max_ip(self%nrefs), indxarr(self%nrefs)
        real      :: max_ir(self%nrefs), rnd_num
        logical   :: mask_ip(params_glob%fromp:params_glob%top)
        mask_ip = .true.
        call seed_rnd
        do while( any(mask_ip) )
            max_ir  = -1.
            !$omp parallel do default(shared) proc_bind(close) schedule(static) private(ir,ip)
            do ir = 1, self%nrefs
                do ip = params_glob%fromp, params_glob%top
                    if( mask_ip(ip) .and. self%ref_ptcl_cor(ir,ip) > max_ir(ir) )then
                        max_ir(ir) = self%ref_ptcl_cor(ir,ip)
                        max_ip(ir) = ip
                    endif
                enddo
            enddo
            !$omp end parallel do
            indxarr = (/(ir,ir=1,self%nrefs)/)
            call hpsort(max_ir, indxarr)
            call reverse(indxarr)
            call random_number(rnd_num)
            max_ind_ir = indxarr(1 + floor(params_glob%reg_nrots * rnd_num))
            max_ind_ip = max_ip(max_ind_ir)
            self%ptcl_ref_map(max_ind_ip) = max_ind_ir
            mask_ip(max_ind_ip) = .false.
        enddo
    end subroutine nonuni_sto_ref_align

    function find_closest_iref( self, iref, mask_ir ) result( closest )
        class(regularizer), intent(inout) :: self
        integer,            intent(in)    :: iref
        logical,            intent(in)    :: mask_ir(self%nrefs)
        real      :: dist, min_dist
        integer   :: closest, i
        type(ori) :: oi, oiref
        call build_glob%eulspace%get_ori(iref, oiref)
        call oiref%e3set(0.)
        min_dist = huge(dist)
        closest  = iref
        do i = 1, self%nrefs
            if( i /= iref .and. mask_ir(i) )then
                call build_glob%eulspace%get_ori(i, oi)
                call oi%e3set(0.)
                dist = oi.euldist.oiref
                if( dist < min_dist )then
                    min_dist = dist
                    closest  = i
                endif
            endif
        end do
    end function find_closest_iref

    subroutine output_reproj_cavgs( self )
        class(regularizer), intent(inout) :: self
        complex,            allocatable   :: cmat(:,:)
        type(image) :: calc_cavg
        integer :: iref, k, box, find
        real    :: eps, filt(self%kfromto(1):self%kfromto(2)), rnd_num
        ! form the cavgs
        where( abs(self%regs_denom_odd) < DTINY )
            self%regs_odd = 0._dp
        elsewhere
            self%regs_odd = self%regs_odd / self%regs_denom_odd
        endwhere
        where( abs(self%regs_denom_even) < DTINY )
            self%regs_even = 0._dp
        elsewhere
            self%regs_even = self%regs_even / self%regs_denom_even
        endwhere
        ! output images for debugging
        if( params_glob%l_reg_debug )then
            do iref = 1, self%nrefs
                ! odd
                call self%pftcc%polar2cartesian(cmplx(self%regs_odd(:,:,iref), kind=sp), cmat, box)
                call calc_cavg%new([box,box,1], params_glob%smpd * real(params_glob%box)/real(box))
                call calc_cavg%zero_and_flag_ft
                call calc_cavg%set_cmat(cmat)
                call calc_cavg%shift_phorig()
                call calc_cavg%ifft
                call calc_cavg%write('odd_polar_cavg_reg_'//int2str(params_glob%which_iter)//'.mrc', iref)
                call self%pftcc%polar2cartesian(cmplx(self%pftcc%pfts_refs_odd(:,:,iref), kind=sp), cmat, box)
                call calc_cavg%zero_and_flag_ft
                call calc_cavg%set_cmat(cmat)
                call calc_cavg%shift_phorig()
                call calc_cavg%ifft
                call calc_cavg%write('odd_polar_cavg_'//int2str(params_glob%which_iter)//'.mrc', iref)
                !even
                call self%pftcc%polar2cartesian(cmplx(self%regs_even(:,:,iref), kind=sp), cmat, box)
                call calc_cavg%new([box,box,1], params_glob%smpd * real(params_glob%box)/real(box))
                call calc_cavg%zero_and_flag_ft
                call calc_cavg%set_cmat(cmat)
                call calc_cavg%shift_phorig()
                call calc_cavg%ifft
                call calc_cavg%write('even_polar_cavg_reg_'//int2str(params_glob%which_iter)//'.mrc', iref)
                call self%pftcc%polar2cartesian(cmplx(self%pftcc%pfts_refs_even(:,:,iref), kind=sp), cmat, box)
                call calc_cavg%zero_and_flag_ft
                call calc_cavg%set_cmat(cmat)
                call calc_cavg%shift_phorig()
                call calc_cavg%ifft
                call calc_cavg%write('even_polar_cavg_'//int2str(params_glob%which_iter)//'.mrc', iref)
            enddo
        endif
        ! k-weight
        !$omp parallel do default(shared) private(k) proc_bind(close) schedule(static)
        do k = self%kfromto(1),self%kfromto(2)
            self%regs_odd( :,k,:) = real(k) * self%regs_odd( :,k,:)
            self%regs_even(:,k,:) = real(k) * self%regs_even(:,k,:)
        enddo
        !$omp end parallel do

        ! applying butterworth filter at cut-off = lp
        find = calc_fourier_index(params_glob%lp, params_glob%box, params_glob%smpd)
        call butterworth_filter(find, self%kfromto, filt)
        !$omp parallel do default(shared) private(k) proc_bind(close) schedule(static)
        do k = self%kfromto(1),self%kfromto(2)
            self%regs_odd( :,k,:) = filt(k) * self%regs_odd( :,k,:)
            self%regs_even(:,k,:) = filt(k) * self%regs_even(:,k,:)
        enddo
        !$omp end parallel do

        ! taking the real part only (since the global cost function takes only real part)
        self%regs_odd       = real(self%regs_odd,  dp)
        self%regs_even      = real(self%regs_even, dp)
        
        ! annealing and different grad styles
        eps = min(1., real(params_glob%which_iter) / real(params_glob%reg_iters))
        call seed_rnd
        !$omp parallel do default(shared) private(iref,rnd_num) proc_bind(close) schedule(static)
        do iref = 1, self%nrefs
            call random_number(rnd_num)
            ! golden ratio initial stochastic
            if( rnd_num < ((1. - eps) * 2. / (1.+sqrt(5.))) )then
                self%pftcc%pfts_refs_even(:,:,iref) = self%pftcc%pfts_refs_even(:,:,iref) + self%regs_even(:,:,iref)
                self%pftcc%pfts_refs_odd( :,:,iref) = self%pftcc%pfts_refs_odd( :,:,iref) + self%regs_odd( :,:,iref)
            endif
        enddo
        !$omp end parallel do
        call self%pftcc%memoize_refs
        call calc_cavg%kill
    end subroutine output_reproj_cavgs
    
    subroutine reset_regs( self )
        class(regularizer), intent(inout) :: self
        self%regs_odd        = 0._dp
        self%regs_even       = 0._dp
        self%regs_denom_odd  = 0._dp
        self%regs_denom_even = 0._dp
    end subroutine reset_regs

    subroutine rotate_polar_real( self, ptcl_ctf, ptcl_ctf_rot, irot )
        class(regularizer), intent(inout) :: self
        real(sp),           intent(in)    :: ptcl_ctf(    self%pftsz,self%kfromto(1):self%kfromto(2))
        real(dp),           intent(inout) :: ptcl_ctf_rot(self%pftsz,self%kfromto(1):self%kfromto(2))
        integer,            intent(in)    :: irot
        integer :: rot
        if( irot >= self%pftsz + 1 )then
            rot = irot - self%pftsz
        else
            rot = irot
        end if
        ! just need the realpart
        if( irot == 1 .or. irot == self%pftsz + 1 )then
            ptcl_ctf_rot = ptcl_ctf
        else
            ptcl_ctf_rot(  1:rot-1    , :) = ptcl_ctf(self%pftsz-rot+2:self%pftsz      ,:)
            ptcl_ctf_rot(rot:self%pftsz,:) = ptcl_ctf(               1:self%pftsz-rot+1,:)
        end if
    end subroutine rotate_polar_real

    subroutine rotate_polar_complex( self, ptcl_ctf, ptcl_ctf_rot, irot )
        class(regularizer), intent(inout) :: self
        complex(dp),        intent(in)    :: ptcl_ctf(    self%pftsz,self%kfromto(1):self%kfromto(2))
        complex(dp),        intent(inout) :: ptcl_ctf_rot(self%pftsz,self%kfromto(1):self%kfromto(2))
        integer,            intent(in)    :: irot
        integer :: rot
        if( irot >= self%pftsz + 1 )then
            rot = irot - self%pftsz
        else
            rot = irot
        end if
        if( irot == 1 )then
            ptcl_ctf_rot = ptcl_ctf
        else if( irot <= self%pftsz )then
            ptcl_ctf_rot(rot:self%pftsz,:) =       ptcl_ctf(               1:self%pftsz-rot+1,:)
            ptcl_ctf_rot(  1:rot-1     ,:) = conjg(ptcl_ctf(self%pftsz-rot+2:self%pftsz      ,:))
        else if( irot == self%pftsz + 1 )then
            ptcl_ctf_rot = conjg(ptcl_ctf)
        else
            ptcl_ctf_rot(rot:self%pftsz,:) = conjg(ptcl_ctf(               1:self%pftsz-rot+1,:))
            ptcl_ctf_rot(  1:rot-1     ,:) =       ptcl_ctf(self%pftsz-rot+2:self%pftsz      ,:)
        end if
    end subroutine rotate_polar_complex

    subroutine rotate_polar_test( self, ptcl_ctf, ptcl_ctf_rot, irot )
        class(regularizer), intent(inout) :: self
        real(dp),           intent(in)    :: ptcl_ctf(    self%pftsz,self%kfromto(1):self%kfromto(2))
        real(dp),           intent(inout) :: ptcl_ctf_rot(self%pftsz,self%kfromto(1):self%kfromto(2))
        integer,            intent(in)    :: irot
        integer :: rot
        if( irot >= self%pftsz + 1 )then
            rot = irot - self%pftsz
        else
            rot = irot
        end if
        ! just need the realpart
        if( irot == 1 .or. irot == self%pftsz + 1 )then
            ptcl_ctf_rot = real(ptcl_ctf, dp)
        else
            ptcl_ctf_rot(  1:rot-1    , :) = real(ptcl_ctf(self%pftsz-rot+2:self%pftsz      ,:), dp)
            ptcl_ctf_rot(rot:self%pftsz,:) = real(ptcl_ctf(               1:self%pftsz-rot+1,:), dp)
        end if
    end subroutine rotate_polar_test

    ! Calculates frc between two PFTs, rotation, shift & ctf are not factored in
    subroutine calc_raw_frc( self, pft1, pft2, frc )
        class(regularizer), intent(inout) :: self
        complex(sp),        intent(in)    :: pft1(self%pftsz,self%kfromto(1):self%kfromto(2))
        complex(sp),        intent(in)    :: pft2(self%pftsz,self%kfromto(1):self%kfromto(2))
        real,               intent(out)   :: frc(self%kfromto(1):self%kfromto(2))
        real(dp) :: num, denom
        integer  :: k
        do k = self%kfromto(1),self%kfromto(2)
            num   = real(sum(pft1(:,k)*conjg(pft2(:,k))),dp)
            denom = real(sum(pft1(:,k)*conjg(pft1(:,k))),dp) * real(sum(pft2(:,k)*conjg(pft2(:,k))),dp)
            if( denom > DTINY )then
                frc(k) = real(num / dsqrt(denom))
            else
                frc(k) = 0.0
            endif
        end do
    end subroutine calc_raw_frc

    ! Calculates normalized PFT power spectrum
    subroutine calc_pspec( self, pft, pspec )
        class(regularizer), intent(inout) :: self
        complex(dp),        intent(in)    :: pft(self%pftsz,self%kfromto(1):self%kfromto(2))
        real,               intent(out)   :: pspec(self%kfromto(1):self%kfromto(2))
        integer :: k
        do k = self%kfromto(1),self%kfromto(2)
            pspec(k) = real( real(sum(pft(:,k)*conjg(pft(:,k))),dp) / real(self%pftsz,dp) )
        end do
    end subroutine calc_pspec

    ! DESTRUCTOR

    subroutine kill( self )
        class(regularizer), intent(inout) :: self
        deallocate(self%regs_odd, self%regs_denom_odd,self%regs_even,self%regs_denom_even)
        if(allocated(self%ref_ptcl_cor)) deallocate(self%ref_ptcl_cor,self%ref_ptcl_tab,self%ptcl_ref_map)
    end subroutine kill
end module simple_regularizer
