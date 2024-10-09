program simple_test_opt_reg
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_polarft_corrcalc,  only: polarft_corrcalc
use simple_cmdline,           only: cmdline
use simple_builder,           only: builder
use simple_image,             only: image
use simple_parameters,        only: parameters
use simple_strategy2D3D_common
use simple_simulator
use simple_ctf
use simple_ori
use simple_classaverager
implicit none
type(cmdline)            :: cline
type(builder)            :: b
type(parameters)         :: p
type(ctf)                :: tfun
type(ori)                :: o
type(oris)               :: os
type(ctfparams)          :: ctfparms
type(image), allocatable :: match_imgs(:), ptcl_match_imgs(:)
logical,     allocatable :: ptcl_mask(:)
integer,     allocatable :: pinds(:)
real,        allocatable :: truth_sh(:,:)
real,        parameter   :: SHMAG = 3.0, SNR = 0.01, BFAC = 10.
integer,     parameter   :: N_PTCLS = 100, ITERS = 1
integer                  :: iptcl, nptcls2update, ithr, iter
if( command_argument_count() < 4 )then
    write(logfhandle,'(a)',advance='no') 'ERROR! required arguments: '
endif
call cline%parse_oldschool
call cline%checkvar('stk',      1)
call cline%checkvar('mskdiam',  2)
call cline%checkvar('smpd',     3)
call cline%checkvar('lp',       4)
call cline%check
call cline%set('oritype','ptcl2D')
if( .not.cline%defined('objfun') ) call cline%set('objfun', 'euclid')
call cline%set('ml_reg', 'no')
call cline%set('ncls',   1.)
call cline%set('kv',     300)
call cline%set('cs',     2.7)
call cline%set('fraca',  0.1)
call cline%set('nptcls',  N_PTCLS)

! general input
call b%init_params_and_build_strategy2D_tbox(cline, p)
call b%spproj%projinfo%new(1,is_ptcl=.false.)
call b%spproj%projinfo%set(1,'projname', 'test')
call b%spproj%os_ptcl2D%kill
call b%spproj%os_ptcl3D%kill
p%fromp          = 1
p%top            = p%nptcls
p%frcs           = trim(FRCS_FILE)
ctfparms%smpd    = p%smpd
ctfparms%kv      = p%kv
ctfparms%cs      = p%cs
if( trim(p%ctf) .eq. 'no' )then
ctfparms%ctfflag = CTFFLAG_NO
endif
ctfparms%fraca   = p%fraca
tfun             = ctf(p%smpd, p%kv, p%cs, p%fraca)

! generate particles
call b%img%read(p%stk, p%iptcl)
call prepimgbatch(N_PTCLS)
call os%new(p%nptcls,is_ptcl=.true.)
if( trim(p%ctf) .eq. 'no' )then
else
    call os%rnd_ctf(p%kv, p%cs, p%fraca, 2.5, 1.5, 0.001)
endif
allocate(truth_sh(p%fromp:p%top,2))
do iptcl = p%fromp,p%top
    call os%set(iptcl,'state',1.)
    call os%set(iptcl,'w',    1.)
    call os%set(iptcl,'class',1.)
    truth_sh(iptcl,:) = [gasdev( 0., SHMAG), gasdev( 0., SHMAG)]
    call os%set(iptcl,'x', truth_sh(iptcl,1))
    call os%set(iptcl,'y', truth_sh(iptcl,2))
    call os%get_ori(iptcl, o)
    call b%img%pad(b%img_pad)
    call b%img_pad%fft
    call b%img_pad%shift2Dserial(truth_sh(iptcl,:) )
    call simimg(b%img_pad, o, tfun, p%ctf, SNR, bfac=BFAC)
    call b%img_pad%clip(b%imgbatch(iptcl))
    call b%imgbatch(iptcl)%write('particles.mrc',iptcl)
enddo
do iptcl = p%fromp,p%top
    call os%set(iptcl,'x', 0.)
    call os%set(iptcl,'y', 0.)
enddo
call b%spproj%add_single_stk('particles.mrc', ctfparms, os)
call b%spproj_field%partition_eo
allocate(ptcl_mask(p%fromp:p%top))
call b%spproj_field%sample4update_all([p%fromp,p%top],nptcls2update, pinds, ptcl_mask, .true.)
allocate(match_imgs(p%ncls),ptcl_match_imgs(nthr_glob))
do ithr = 1,nthr_glob
    call ptcl_match_imgs(ithr)%new([p%box_crop, p%box_crop, 1], p%smpd_crop, wthreads=.false.)
enddo

! references
call restore_read_polarize_cavgs(0)

! particles
!$omp parallel do default(shared) private(iptcl,ithr)&
!$omp schedule(static) proc_bind(close)
do iptcl = p%fromp,p%top
    ithr = omp_get_thread_num() + 1
    call prepimg4align(iptcl, b%imgbatch(iptcl), ptcl_match_imgs(ithr))
    call b%imgbatch(iptcl)%ifft
end do
!$omp end parallel do

do iter = 1, ITERS
    do iptcl = p%fromp,p%top
        call b%spproj_field%get_ori(iptcl, o)
        ! do stuffs with o
    enddo
    call restore_read_polarize_cavgs(iter)
enddo

! last one is truth
do iptcl = p%fromp,p%top
    call b%spproj_field%set_shift(iptcl, truth_sh(iptcl,:))
enddo
call restore_read_polarize_cavgs(iter)


contains

    subroutine restore_read_polarize_cavgs( iter )
        integer, intent(in) :: iter
        p%which_iter = iter
        call cavger_kill()
        call cavger_new(ptcl_mask)
        call cavger_transf_oridat( b%spproj )
        call cavger_assemble_sums( .false. )
        call cavger_merge_eos_and_norm
        call cavger_calc_and_write_frcs_and_eoavg(p%frcs, p%which_iter)
        p%refs      = trim(CAVGS_ITER_FBODY)//int2str_pad(p%which_iter,3)//p%ext
        p%refs_even = trim(CAVGS_ITER_FBODY)//int2str_pad(p%which_iter,3)//'_even'//p%ext
        p%refs_odd  = trim(CAVGS_ITER_FBODY)//int2str_pad(p%which_iter,3)//'_odd'//p%ext
        call cavger_write(trim(p%refs),      'merged')
        call cavger_write(trim(p%refs_even), 'even'  )
        call cavger_write(trim(p%refs_odd),  'odd'   )
        call b%clsfrcs%read(FRCS_FILE)
        call cavger_read(trim(p%refs_even), 'even' )
        call cavger_read(trim(p%refs_even), 'odd' )
    end subroutine restore_read_polarize_cavgs

end program simple_test_opt_reg