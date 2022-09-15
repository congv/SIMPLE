program simple_test_grad_cartftcc
include 'simple_lib.f08'
use simple_cartft_corrcalc, only: cartft_corrcalc
use simple_eval_cartftcc,   only: eval_cartftcc
use simple_cmdline,         only: cmdline
use simple_builder,         only: builder
use simple_parameters,      only: parameters
use simple_cftcc_shsrch_grad,   only: cftcc_shsrch_grad
use simple_projector_hlev
use simple_timer
use simple_oris
use simple_image
implicit none
type(parameters)         :: p
type(cartft_corrcalc)    :: cftcc
type(cmdline)            :: cline
type(builder)            :: b
integer,     parameter   :: NSPACE=1    ! set to 1 for fast test
real                     :: corrs(NSPACE), corrs2(NSPACE), grad(2, NSPACE), lims(2,2), cxy(3)
type(image), allocatable :: imgs(:)
real,        allocatable :: pshifts(:,:)
integer                  :: iref, iptcl, loc(1), cnt, x, y, iter
type(eval_cartftcc)      :: evalcc
type(cftcc_shsrch_grad)  :: grad_carshsrch_obj
if( command_argument_count() < 3 )then
    write(logfhandle,'(a)') 'simple_test_eval_cartftcc lp=xx smpd=yy nthr=zz vol1=vol1.mrc'
    stop
endif
call cline%parse_oldschool
call cline%checkvar('lp',   1)
call cline%checkvar('smpd', 2)
call cline%checkvar('nthr', 3)
call cline%checkvar('vol1', 4)
call cline%set('ctf', 'no')
call cline%set('match_filt', 'no')
call cline%check
call p%new(cline)
p%kfromto(1) = 3
p%kfromto(2) = calc_fourier_index(p%lp, p%box, p%smpd)
p%kstop      = p%kfromto(2)
call b%build_general_tbox(p, cline)
! prep projections
call b%vol%read(p%vols(1))
call b%eulspace%new(NSPACE, is_ptcl=.false.)
call b%eulspace%spiral
p%nptcls = NSPACE
imgs     = reproject(b%vol, b%eulspace)
call b%vol%fft
call b%vol%expand_cmat(KBALPHA) ! necessary for re-projection
! prep correlator
call cftcc%new(p%nptcls, [1, p%nptcls], .false.)
do iref = 1, p%nptcls
    call imgs(iref)%fft
    call cftcc%set_ref(iref, imgs(iref), .true.)
end do
do iptcl = 1,p%nptcls
    call cftcc%set_ptcl(iptcl,imgs(iptcl))
end do
! prep evaluator
call evalcc%new(b%vol, b%vol, NSPACE)
allocate(pshifts(p%nptcls, 2), source=0.)
do iref = 1,p%nptcls
    ! mapping ran3 (0 to 1) to [-5, 5]
    pshifts(iref, 1) = floor(ran3()*10.99) - 5
    pshifts(iref, 2) = floor(ran3()*10.99) - 5
    call evalcc%set_ori(iref, b%eulspace%get_euler(iref), pshifts(iref, :))
end do
! testing with lbfgsb
lims(:,1) = -5.
lims(:,2) =  5.
call grad_carshsrch_obj%new(lims)
call grad_carshsrch_obj%set_indices(1, 1)
cxy = grad_carshsrch_obj%minimize()
print *, cxy
! testing with basic gradient descent
iptcl = 1
iref  = 1
print *, 'initial shift = ', pshifts(iref, :)
do iter = 1, 1000
    call evalcc%set_ori(iref, b%eulspace%get_euler(iref), pshifts(iref, :))
    call evalcc%project_and_correlate(iptcl, corrs, grad)
    if( mod(iter, 100) == 0)then
        print *, 'iter = ', iter
        print *, 'cost = ', corrs(1)
        print *, 'shifts = ', pshifts(iref, :)
    endif
    pshifts(iref, :) = pshifts(iref, :) + grad(:, iref)
enddo
end program simple_test_grad_cartftcc
