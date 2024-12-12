! concrete commander: dev cluster2D_stream for streaming 2D alignment and clustering of single-particle images
module simple_commander_cluster2D_stream
include 'simple_lib.f08'
use simple_cmdline,            only: cmdline
use simple_commander_base,     only: commander_base
use simple_parameters,         only: parameters, params_glob
use simple_sp_project,         only: sp_project
use simple_qsys_env,           only: qsys_env
use simple_image,              only: image
use simple_class_frcs,         only: class_frcs
use simple_stack_io,           only: stack_io
use simple_starproject,        only: starproject
use simple_starproject_stream, only: starproject_stream
use simple_euclid_sigma2,      only: consolidate_sigma2_groups, split_sigma2_into_groups, sigma2_star_from_iter
use simple_guistats,           only: guistats
use simple_stream_utils
use simple_qsys_funs
use simple_commander_cluster2D
use FoX_dom
implicit none

public :: init_cluster2D_stream, update_user_params2D, terminate_stream2D
! Pool
public :: import_records_into_pool, classify_pool, update_pool_status, update_pool
public :: reject_from_pool, reject_from_pool_user, write_pool_cls_selected_user
public :: generate_pool_stats, read_pool_xml_beamtilts, assign_pool_optics
public :: is_pool_available, get_pool_iter
! Chunks
public :: update_chunks, classify_new_chunks, import_chunks_into_pool
public :: flush_remaining_particles, all_chunks_available
! Utilities
public :: cleanup_root_folder
! Cluster2D subsets
public :: cluster2D_commander_subsets

private
#include "simple_local_flags.inc"

type, extends(commander_base) :: cluster2D_commander_subsets
  contains
    procedure :: execute      => exec_cluster2D_subsets
end type cluster2D_commander_subsets

type scaled_dims
    real    :: smpd=0., msk=0.
    integer :: box=0, boxpd=0
end type scaled_dims

integer,               parameter :: MINBOXSZ             = 128              ! minimum boxsize for scaling
integer,               parameter :: CHUNK_MINITS         = 13               ! minimum number of iterations for chunks
integer,               parameter :: CHUNK_MAXITS         = CHUNK_MINITS + 2 ! maximum number of iterations for chunks
integer,               parameter :: CHUNK_CC_ITERS       = 8                ! maximum number of correlatiion-based iterations for chunks
integer,               parameter :: CHUNK_EXTR_ITER      = 3                ! starting extremal iteration for chunks
integer,               parameter :: FREQ_POOL_REJECTION  = 5                ! pool class rejection performed every FREQ_POOL_REJECTION iteration
integer,               parameter :: MIN_NPTCLS_REJECTION = 200000           ! Minimum number of particles required to activate rejection
character(len=STDLEN), parameter :: USER_PARAMS          = 'stream2D_user_params.txt'
character(len=STDLEN), parameter :: PROJFILE_POOL        = 'cluster2D.simple'
character(len=STDLEN), parameter :: POOL_DIR             = ''               ! should be './pool/' for tidyness but difficult with gui
character(len=STDLEN), parameter :: SIGMAS_DIR           = './sigma2/'
character(len=STDLEN), parameter :: DISTR_EXEC_FNAME     = './distr_cluster2D_pool'
character(len=STDLEN), parameter :: LOGFILE              = 'simple_log_cluster2D_pool'
character(len=STDLEN), parameter :: CHECKPOINT_DIR       = 'checkpoint/'
character(len=STDLEN), parameter :: CLS_POOL_REJECTED    = 'cls_rejected_pool.mrc'
logical,               parameter :: DEBUG_HERE           = .false.
integer(timer_int_kind)          :: t

! Pool related
type(sp_project)                       :: pool_proj                         ! master project
type(qsys_env)                         :: qenv_pool
type(cmdline)                          :: cline_cluster2D_pool              ! master pool classification command line
type(scaled_dims)                      :: pool_dims                         ! crop dimensions used for pool
logical,                   allocatable :: pool_stacks_mask(:)               ! subset of stacks undergoing classification
integer                                :: pool_iter                         ! Iteration counter
logical                                :: pool_available
logical                                :: l_no_chunks                       ! for not using chunks (cf gen_picking_refs)
! Chunk related
type(stream_chunk),        allocatable :: chunks(:), converged_chunks(:)
type(cmdline)                          :: cline_cluster2D_chunk             ! master chunk classification command line
type(scaled_dims)                      :: chunk_dims                        ! crop dimensions used for chunks
integer                                :: glob_chunk_id                     ! ID book-keeping
! Book-keeping
character(len=:),          allocatable :: orig_projfile
character(len=STDLEN)                  :: refs_glob                         ! global 2D references filename
real                                   :: conv_score=0., conv_mi_class=0., conv_frac=0., current_resolution=999.
integer                                :: nptcls_glob=0, nptcls_rejected_glob=0, ncls_rejected_glob=0
integer                                :: ncls_glob                         ! global number of classes
integer                                :: iterswitch2euclid = 0             ! only used by gen_picking_refs
logical                                :: stream2D_active   = .false.       ! initiation flag
! GUI-related
type(starproject)                      :: starproj
type(starproject_stream)               :: starproj_stream
character(len=:),          allocatable :: projfile4gui                      ! Joe: is this output still used?
! other
real     :: lpstart, lpstop, lpcen
integer  :: max_ncls, nptcls_per_chunk, nmics_last, numlen
logical  :: l_wfilt                     ! flags partial wiener restoration
logical  :: l_scaling                   ! flags downscaling
logical  :: l_update_sigmas = .false.   ! flags objective function (cc/euclid)
logical  :: l_abinitio2D    = .false.   ! Whether to use abinitio2D/cluster2D

contains

    subroutine init_cluster2D_stream( cline, spproj, projfilegui, reference_generation )
        class(cmdline),    intent(inout) :: cline
        class(sp_project), intent(inout) :: spproj
        character(len=*),  intent(in)    :: projfilegui
        logical, optional, intent(in)    :: reference_generation    ! Joe: redundant with l_no_chunks (nchunks==0), will remove
        character(len=:), allocatable    :: carg
        character(len=STDLEN)            :: chunk_nthr_env, pool_nthr_env, pool_part_env, refgen_nthr_env, refgen_part_env
        real    :: chunk_nthr, pool_nthr, refgen_nthr
        integer :: ichunk, envlen, nthr2D
        logical :: refgen
        call seed_rnd
        ! general parameters
        call mskdiam2lplimits(params_glob%mskdiam, lpstart, lpstop, lpcen)
        if( cline%defined('lp') ) lpstart = params_glob%lp
        l_wfilt             = trim(params_glob%wiener) .eq. 'partial'
        l_scaling           = trim(params_glob%autoscale) .eq. 'yes'
        max_ncls            = floor(cline%get_rarg('ncls')/real(params_glob%ncls_start))*params_glob%ncls_start ! effective maximum # of classes
        nptcls_per_chunk    = params_glob%nptcls_per_cls*params_glob%ncls_start         ! # of particles in each chunk
        ncls_glob           = 0
        ncls_rejected_glob  = 0
        orig_projfile       = trim(params_glob%projfile)
        projfile4gui        = trim(projfilegui)
        l_update_sigmas     = params_glob%l_needs_sigma
        nmics_last          = 0
        l_abinitio2D        = cline%defined('algorithm')
        if( l_abinitio2D ) l_abinitio2D = str_has_substr(params_glob%algorithm,'abinitio')
        ! bookkeeping & directory structure
        numlen         = len(int2str(params_glob%nparts_pool))
        refs_glob      = 'start_cavgs'//params_glob%ext
        pool_available = .true.
        pool_iter      = 0
        call simple_mkdir(POOL_DIR)
        call simple_mkdir(trim(POOL_DIR)//trim(STDERROUT_DIR))
        if( l_update_sigmas ) call simple_mkdir(SIGMAS_DIR)
        call simple_touch(trim(POOL_DIR)//trim(CLUSTER2D_FINISHED))
        call pool_proj%kill
        pool_proj%projinfo = spproj%projinfo
        pool_proj%compenv  = spproj%compenv
        call pool_proj%projinfo%delete_entry('projname')
        call pool_proj%projinfo%delete_entry('projfile')
        ! update to computational parameters to pool, will be transferred to chunks upon init
        if( cline%defined('walltime') ) call pool_proj%compenv%set(1,'walltime', params_glob%walltime)
        call pool_proj%write(trim(POOL_DIR)//trim(PROJFILE_POOL))
        ! chunk master command line
        if( params_glob%nchunks > 0 )then
            if( l_abinitio2D )then
                call cline_cluster2D_chunk%set('prg', 'abinitio2D')
                if( params_glob%nparts_chunk > 1 )then
                    call cline_cluster2D_chunk%set('nparts', params_glob%nparts_chunk)
                endif
                if( cline%defined('cls_init') )then
                    call cline_cluster2D_chunk%set('cls_init', params_glob%cls_init)
                else
                    call cline_cluster2D_chunk%set('cls_init','rand')
                endif
                call cline_cluster2D_chunk%set('rank_cavgs','no')
            else
                if( params_glob%nparts_chunk > 1 )then
                    call cline_cluster2D_chunk%set('prg',    'cluster2D_distr')
                    call cline_cluster2D_chunk%set('nparts', params_glob%nparts_chunk)
                else
                    ! shared memory execution
                    call cline_cluster2D_chunk%set('prg',    'cluster2D')
                endif
                call cline_cluster2D_chunk%set('minits',    CHUNK_MINITS)
                call cline_cluster2D_chunk%set('maxits',    CHUNK_MAXITS)
                call cline_cluster2D_chunk%set('extr_iter', CHUNK_EXTR_ITER)
                call cline_cluster2D_chunk%set('extr_lim',  MAX_EXTRLIM2D)
                call cline_cluster2D_chunk%set('startit',   1)
                if( l_update_sigmas ) call cline_cluster2D_chunk%set('cc_iters', CHUNK_CC_ITERS)
                if( cline%defined('cls_init') )then
                    call cline_cluster2D_chunk%set('cls_init', params_glob%cls_init)
                else
                    call cline_cluster2D_chunk%set('cls_init','ptcl')
                endif
            endif
            call cline_cluster2D_chunk%set('oritype',   'ptcl2D')
            call cline_cluster2D_chunk%set('center',    'no')
            call cline_cluster2D_chunk%set('autoscale', 'no')
            call cline_cluster2D_chunk%set('mkdir',     'no')
            call cline_cluster2D_chunk%set('stream',    'no')
            call cline_cluster2D_chunk%set('mskdiam',   params_glob%mskdiam)
            call cline_cluster2D_chunk%set('ncls',      params_glob%ncls_start)
            call cline_cluster2D_chunk%set('kweight',   params_glob%kweight_chunk)
            if( l_wfilt ) call cline_cluster2D_chunk%set('wiener', 'partial')
            ! EV override
            call get_environment_variable(SIMPLE_STREAM_CHUNK_NTHR, chunk_nthr_env, envlen)
            if(envlen > 0) then
                read(chunk_nthr_env,*) chunk_nthr
                call cline_cluster2D_chunk%set('nthr', chunk_nthr)
            else
                call cline_cluster2D_chunk%set('nthr', params_glob%nthr2D)
            end if
            l_no_chunks       = .false. ! will be using chunks
        else
            l_no_chunks       = .true.  ! will NOT be using chunks
            ncls_glob         = params_glob%ncls
            iterswitch2euclid = 0
        endif
        ! Pool command line
        call cline_cluster2D_pool%set('prg',       'cluster2D_distr')
        call cline_cluster2D_pool%set('oritype',   'ptcl2D')
        call cline_cluster2D_pool%set('autoscale', 'no')
        call cline_cluster2D_pool%set('trs',       MINSHIFT)
        call cline_cluster2D_pool%set('projfile',  PROJFILE_POOL)
        call cline_cluster2D_pool%set('projname',  trim(get_fbody(trim(PROJFILE_POOL),trim('simple'))))
        call cline_cluster2D_pool%set('kweight',   params_glob%kweight_pool)
        if( cline%defined('center') )then
            carg = cline%get_carg('center')
            call cline_cluster2D_pool%set('center',carg)
            deallocate(carg)
        else
            call cline_cluster2D_pool%set('center','yes')
        endif
        if( l_wfilt ) call cline_cluster2D_pool%set('wiener', 'partial')
        call cline_cluster2D_pool%set('extr_iter', 99999)
        call cline_cluster2D_pool%set('extr_lim',  MAX_EXTRLIM2D)
        call cline_cluster2D_pool%set('mkdir',     'no')
        call cline_cluster2D_pool%set('mskdiam',   params_glob%mskdiam)
        call cline_cluster2D_pool%set('async',     'yes') ! to enable hard termination
        call cline_cluster2D_pool%set('stream',    'yes')
        call cline_cluster2D_pool%set('nparts',    params_glob%nparts_pool)
        if( l_update_sigmas ) call cline_cluster2D_pool%set('cc_iters', 0)
        ! when the classification is started without chunks (no chunk pre-classification)
        if( l_no_chunks ) l_update_sigmas = .false.
        ! EV override
        refgen = .false.
        if( present(reference_generation) ) refgen = reference_generation
        if( refgen )then
            call get_environment_variable(SIMPLE_STREAM_REFGEN_NTHR, refgen_nthr_env, envlen)
            if(envlen > 0) then
                read(refgen_nthr_env,*) refgen_nthr
                call cline_cluster2D_pool%set('nthr', refgen_nthr)
            else
                call cline_cluster2D_pool%set('nthr', params_glob%nthr2D)
            end if
            call get_environment_variable(SIMPLE_STREAM_REFGEN_PARTITION, refgen_part_env, envlen)
            if(envlen > 0) then
                call qenv_pool%new(params_glob%nparts_pool,exec_bin='simple_private_exec',qsys_name='local', qsys_partition=trim(refgen_part_env))
            else
                call qenv_pool%new(params_glob%nparts_pool,exec_bin='simple_private_exec',qsys_name='local')
            end if
        else
            call get_environment_variable(SIMPLE_STREAM_POOL_NTHR, pool_nthr_env, envlen)
            if(envlen > 0) then
                read(pool_nthr_env,*) pool_nthr
                call cline_cluster2D_pool%set('nthr',   pool_nthr)
                call cline_cluster2D_pool%set('nthr2D', pool_nthr)
            else
                call cline_cluster2D_pool%set('nthr', params_glob%nthr2D)
            end if
            call get_environment_variable(SIMPLE_STREAM_POOL_PARTITION, pool_part_env, envlen)
            if(envlen > 0) then
                call qenv_pool%new(params_glob%nparts_pool,exec_bin='simple_private_exec',qsys_name='local', qsys_partition=trim(pool_part_env))
            else
                call qenv_pool%new(params_glob%nparts_pool,exec_bin='simple_private_exec',qsys_name='local')
            end if
        end if
        ! objective function
        select case(params_glob%cc_objfun)
        case(OBJFUN_CC)
            call cline_cluster2D_chunk%set('objfun', 'cc')
            call cline_cluster2D_pool%set('objfun',  'cc')
        case(OBJFUN_EUCLID)
            call cline_cluster2D_chunk%set('objfun', 'euclid')
            call cline_cluster2D_pool%set('objfun',  'euclid')
            call cline_cluster2D_chunk%set('ml_reg', params_glob%ml_reg_chunk)
            call cline_cluster2D_pool%set('ml_reg',  params_glob%ml_reg_pool)
            call cline_cluster2D_chunk%set('tau',    params_glob%tau)
            call cline_cluster2D_pool%set('tau',     params_glob%tau)
        end select
        ! refinement
        select case(trim(params_glob%refine))
        case('snhc')
            call cline_cluster2D_chunk%set('refine', 'snhc')
            call cline_cluster2D_pool%set('refine',  'snhc')
        case('snhc_smpl')
            call cline_cluster2D_chunk%set('refine', 'snhc_smpl')
            call cline_cluster2D_pool%set('refine',  'snhc_smpl')
        case DEFAULT
            THROW_HARD('UNSUPPORTED REFINE PARAMETER!')
        end select
        ! Determines dimensions for downscaling
        call set_scaling_dims
        ! updates command-lines with resolution limits
        call set_resolution_limits( cline )
        ! Initialize subsets
        if( .not.l_no_chunks )then
            allocate(chunks(params_glob%nchunks))
            ! deal with nthr2d .ne. nthr
            ! Joe: the whole nthr/2d is confusing. Why not pass the number of threads to chunk%init?
            ! also why not introduce params%nthr_chunk/pool and we do not have to deal with environment
            ! variables at all, everything is set on startup. Same goes for qsys_partition?
            nthr2D             = params_glob%nthr2D
            params_glob%nthr2D = cline_cluster2D_chunk%get_iarg('nthr')
            glob_chunk_id      = 0
            do ichunk = 1,params_glob%nchunks
                glob_chunk_id = glob_chunk_id + 1
                call chunks(ichunk)%init(ichunk, cline_cluster2D_chunk, pool_proj)
            enddo
            params_glob%nthr2D = nthr2D
        endif
        ! module variables
        stream2D_active = .true.
    end subroutine init_cluster2D_stream

    subroutine set_scaling_dims
        real    :: SMPD_TARGET = MAX_SMPD  ! target sampling distance
        real    :: smpd, scale_factor
        integer :: box
        ! Determines dimensions for downscaling
        if( params_glob%box == 0 ) THROW_HARD('FATAL ERROR')
        scale_factor          = 1.0
        params_glob%smpd_crop = params_glob%smpd
        params_glob%box_crop  = params_glob%box
        if( l_scaling .and. params_glob%box >= MINBOXSZ )then
            call autoscale(params_glob%box, params_glob%smpd, SMPD_TARGET, box, smpd, scale_factor, minbox=MINBOXSZ)
            l_scaling = box < params_glob%box
            if( l_scaling )then
                write(logfhandle,'(A,I3,A1,I3)')'>>> ORIGINAL/CROPPED IMAGE SIZE (pixels): ',params_glob%box,'/',box
                params_glob%smpd_crop = smpd
                params_glob%box_crop  = box
            endif
        endif
        params_glob%msk_crop = round2even(params_glob%mskdiam / params_glob%smpd_crop / 2.)
        pool_dims%smpd  = params_glob%smpd_crop
        pool_dims%box   = params_glob%box_crop
        pool_dims%boxpd = 2 * round2even(params_glob%alpha * real(params_glob%box_crop/2)) ! logics from parameters
        pool_dims%msk   = params_glob%msk_crop
        chunk_dims = pool_dims  ! chunk & pool have the same dimensions to start with
        ! Scaling-related command lines update
        call cline_cluster2D_chunk%set('smpd_crop', chunk_dims%smpd)
        call cline_cluster2D_chunk%set('box_crop',  chunk_dims%box)
        call cline_cluster2D_chunk%set('msk_crop',  chunk_dims%msk)
        call cline_cluster2D_chunk%set('box',       params_glob%box)
        call cline_cluster2D_chunk%set('smpd',      params_glob%smpd)
        call cline_cluster2D_pool%set('smpd_crop',  pool_dims%smpd)
        call cline_cluster2D_pool%set('box_crop',   pool_dims%box)
        call cline_cluster2D_pool%set('msk_crop',   pool_dims%msk)
        call cline_cluster2D_pool%set('box',        params_glob%box)
        call cline_cluster2D_pool%set('smpd',       params_glob%smpd)
    end subroutine set_scaling_dims

    ! private routine for resolution-related updates to command-lines
    subroutine set_resolution_limits( master_cline )
        type(cmdline), intent(in) :: master_cline
        lpstart = max(lpstart, 2.0*params_glob%smpd_crop)
        if( l_no_chunks )then
            params_glob%lpstop = lpstop
        else
            if( master_cline%defined('lpstop') )then
                params_glob%lpstop = max(2.0*params_glob%smpd_crop,params_glob%lpstop)
            else
                params_glob%lpstop = 2.0*params_glob%smpd_crop
            endif
            call cline_cluster2D_chunk%delete('lp')
            call cline_cluster2D_chunk%set('lpstart', lpstart)
            call cline_cluster2D_chunk%set('lpstop',  lpstart)
        endif
        call cline_cluster2D_pool%set('lpstart',  lpstart)
        call cline_cluster2D_pool%set('lpstop',   params_glob%lpstop)
        if( .not.master_cline%defined('cenlp') )then
            call cline_cluster2D_chunk%set('cenlp', lpcen)
            call cline_cluster2D_pool%set( 'cenlp', lpcen)
        else
            call cline_cluster2D_chunk%set('cenlp', params_glob%cenlp)
            call cline_cluster2D_pool%set( 'cenlp', params_glob%cenlp)
        endif
        ! Will use resolution update scheme from abinitio2D
        if( l_abinitio2D .and. (.not.l_no_chunks))then
            if( master_cline%defined('lpstop') )then
                ! already set above
            else
                call cline_cluster2D_chunk%delete('lpstop')
            endif
        endif
        write(logfhandle,'(A,F5.1)') '>>> POOL STARTING LOW-PASS LIMIT (IN A): ', lpstart
        write(logfhandle,'(A,F5.1)') '>>> POOL   HARD RESOLUTION LIMIT (IN A): ', params_glob%lpstop
        write(logfhandle,'(A,F5.1)') '>>> CENTERING     LOW-PASS LIMIT (IN A): ', lpcen
    end subroutine set_resolution_limits

    !> Updates current parameters with user input
    subroutine update_user_params2D( cline_here, updated )
        type(cmdline), intent(inout) :: cline_here
        logical,       intent(out)   :: updated
        type(oris)            :: os
        character(len=STDLEN) :: val
        real                  :: lpthres, ndev
        updated = .false.
        call os%new(1, is_ptcl=.false.)
        if( file_exists(USER_PARAMS) )then
            call os%read(USER_PARAMS)
            ! class resolution threshold for rejection
            if( os%isthere(1,'lpthres') )then
                lpthres = os%get(1,'lpthres')
                if( abs(lpthres-params_glob%lpthres) > 0.001 )then
                    if( lpthres < 3.0*chunk_dims%smpd )then
                        write(logfhandle,'(A,F8.2)')'>>> REJECTION lpthres TOO LOW: ',lpthres
                    else
                        params_glob%lpthres = lpthres
                        write(logfhandle,'(A,F8.2)')'>>> REJECTION lpthres UPDATED TO: ',params_glob%lpthres
                        updated = .true.
                    endif
                endif
            endif
            ! class standard deviation of resolution threshold for rejection
            if( os%isthere(1,'ndev2D') )then
                ndev = os%get(1,'ndev2D')
                if( abs(ndev-params_glob%ndev) > 0.001 )then
                    if( ndev < 0.1 )then
                        write(logfhandle,'(A,F8.2)')'>>> REJECTION NDEV TOO LOW: ',ndev
                    else
                        params_glob%ndev = ndev
                        write(logfhandle,'(A,F8.2)')'>>> REJECTION NDEV   UPDATED TO: ',params_glob%ndev
                        updated = .true.
                    endif
                endif
            endif
            ! class rejection
            if( os%isthere(1,'reject_cls') )then
                val = os%get_static(1, 'reject_cls')
                if( trim(val) .ne. trim(params_glob%reject_cls) )then
                    select case(trim(val))
                    case('yes')
                        write(logfhandle,'(A)')'>>> ACTIVATING CLASS REJECTION'
                        params_glob%reject_cls = trim(val)
                        updated = .true.
                    case('no')
                        write(logfhandle,'(A)')'>>> DE-ACTIVATING CLASS REJECTION'
                        params_glob%reject_cls = trim(val)
                        updated = .true.
                    case('old')
                        write(logfhandle,'(A)')'>>> DE-ACTIVATING IMAGE MOMENTS-BASED CLASS REJECTION'
                        params_glob%reject_cls = trim(val)
                        updated = .true.
                    case DEFAULT
                        THROW_WARN('Unknown flag for class rejection: '//trim(val))
                    end select
                endif
            endif
            ! remove once processed
            call del_file(USER_PARAMS)
        endif
        call os%kill
    end subroutine update_user_params2D

    ! ends processing, generates project & cleanup
    subroutine terminate_stream2D( records )
        type(projrecord), allocatable, intent(in) :: records(:)
        integer :: ichunk, ipart
        do ichunk = 1,params_glob%nchunks
            call chunks(ichunk)%terminate
        enddo
        if( pool_iter == 0 )then
            ! no pool classification performed, all available info is written down
            if( allocated(records) )then
                call projrecords2proj(records, pool_proj)
                call starproj_stream%copy_micrographs_optics(pool_proj, verbose=DEBUG_HERE)
                call starproj_stream%stream_export_micrographs(pool_proj, params_glob%outdir, optics_set=.true.)
                call starproj_stream%stream_export_particles_2D(pool_proj, params_glob%outdir, optics_set=.true.)
                call pool_proj%write(orig_projfile)
            endif
        else
            if( .not.pool_available )then
                pool_iter = pool_iter-1 ! iteration pool_iter not complete so fall back on previous iteration
                refs_glob = trim(CAVGS_ITER_FBODY)//trim(int2str_pad(pool_iter,3))//trim(params_glob%ext)
                ! tricking the asynchronous master process to come to a hard stop
                call simple_touch(trim(POOL_DIR)//trim(TERM_STREAM))
                do ipart = 1,params_glob%nparts_pool
                    call simple_touch(trim(POOL_DIR)//trim(JOB_FINISHED_FBODY)//int2str_pad(ipart,numlen))
                enddo
                call simple_touch(trim(POOL_DIR)//'CAVGASSEMBLE_FINISHED')
            endif
            call write_project_stream2D(write_star=.true., clspath=.true.)
            ! rank cavgs
            if( pool_iter >= 1 ) call rank_cavgs
        endif
        ! cleanup
        call simple_rmdir(SIGMAS_DIR)
        call del_file(trim(POOL_DIR)//trim(PROJFILE_POOL))
        call del_file(projfile4gui)
        if( .not.debug_here )then
            call qsys_cleanup
        endif
    end subroutine terminate_stream2D

    !> produces consolidated project
    subroutine write_project_stream2D( write_star, clspath)
        logical, optional, intent(in) :: write_star
        logical, optional, intent(in) :: clspath
        type(class_frcs)              :: frcs, frcs_sc
        type(oris)                    :: os_backup
        character(len=:), allocatable :: projfile,projfname, cavgsfname, frcsfname, src, dest
        character(len=:), allocatable :: pool_refs
        logical                       :: l_write_star, l_clspath
        logical,     parameter        :: DEBUG_HERE      = .true.
        l_write_star = .false.
        l_clspath    = .false.
        if(present(write_star)) l_write_star = write_star
        if(present(clspath))    l_clspath    = clspath
        ! file naming
        projfname  = get_fbody(orig_projfile, METADATA_EXT, separator=.false.)
        cavgsfname = get_fbody(refs_glob, params_glob%ext, separator=.false.)
        frcsfname  = get_fbody(FRCS_FILE, BIN_EXT, separator=.false.)
        call pool_proj%projinfo%set(1,'projname', projfname)
        projfile   = trim(projfname)//trim(METADATA_EXT)
        call pool_proj%projinfo%set(1,'projfile', projfile)
        cavgsfname = trim(cavgsfname)//trim(params_glob%ext)
        frcsfname  = trim(frcsfname)//trim(BIN_EXT)
        write(logfhandle,'(A,A,A,A)')'>>> WRITING PROJECT ',trim(projfile), ' AT: ',cast_time_char(simple_gettime())
        pool_refs = trim(POOL_DIR)//trim(refs_glob)
        if( l_scaling )then
            os_backup = pool_proj%os_cls2D
            ! rescale classes
            if( l_wfilt )then
                src  = add2fbody(pool_refs, params_glob%ext,trim(WFILT_SUFFIX))
                dest = add2fbody(cavgsfname,params_glob%ext,trim(WFILT_SUFFIX))
                call rescale_cavgs(src, dest)
                src  = add2fbody(pool_refs, params_glob%ext,trim(WFILT_SUFFIX)//'_even')
                dest = add2fbody(cavgsfname,params_glob%ext,trim(WFILT_SUFFIX)//'_even')
                call rescale_cavgs(src, dest)
                src  = add2fbody(pool_refs, params_glob%ext,trim(WFILT_SUFFIX)//'_odd')
                dest = add2fbody(cavgsfname,params_glob%ext,trim(WFILT_SUFFIX)//'_odd')
                call rescale_cavgs(src, dest)
            endif
            call rescale_cavgs(pool_refs, cavgsfname)
            src  = add2fbody(pool_refs, params_glob%ext,'_even')
            dest = add2fbody(cavgsfname,params_glob%ext,'_even')
            call rescale_cavgs(src, dest)
            src  = add2fbody(pool_refs, params_glob%ext,'_odd')
            dest = add2fbody(cavgsfname,params_glob%ext,'_odd')
            call rescale_cavgs(src, dest)
            call pool_proj%os_out%kill
            call pool_proj%add_cavgs2os_out(cavgsfname, params_glob%smpd, 'cavg', clspath=l_clspath)
            if( l_wfilt )then
                src = add2fbody(cavgsfname,params_glob%ext,trim(WFILT_SUFFIX))
                call pool_proj%add_cavgs2os_out(src, params_glob%smpd, 'cavg'//trim(WFILT_SUFFIX), clspath=l_clspath)
            endif
            pool_proj%os_cls2D = os_backup
            call os_backup%kill
            ! rescale frcs
            call frcs_sc%read(trim(POOL_DIR)//trim(FRCS_FILE))
            call frcs_sc%pad(params_glob%smpd, params_glob%box, frcs)
            call frcs%write(frcsfname)
            call frcs%kill
            call frcs_sc%kill
            call pool_proj%add_frcs2os_out(frcsfname, 'frc2D')
        else
            call pool_proj%os_out%kill
            call pool_proj%add_cavgs2os_out(cavgsfname, params_glob%smpd, 'cavg', clspath=l_clspath)
            if( l_wfilt )then
                src = add2fbody(cavgsfname,params_glob%ext,trim(WFILT_SUFFIX))
                call pool_proj%add_cavgs2os_out(src, params_glob%smpd, 'cavg'//trim(WFILT_SUFFIX))
            endif
            call pool_proj%add_frcs2os_out(frcsfname, 'frc2D')
        endif
        ! 3d field
        pool_proj%os_ptcl3D = pool_proj%os_ptcl2D
        call pool_proj%os_ptcl3D%delete_2Dclustering
        call pool_proj%os_ptcl3D%clean_entry('updatecnt', 'sampled')
        ! write starfiles
        call starproj%export_cls2D(pool_proj)
        if(l_write_star) then
            call starproj_stream%copy_micrographs_optics(pool_proj, verbose=DEBUG_HERE)
            if( DEBUG_HERE ) t = tic()
            call starproj_stream%stream_export_micrographs(pool_proj, params_glob%outdir, optics_set=.true.)
            if( DEBUG_HERE ) print *,'ms_export  : ', toc(t); call flush(6); t = tic()
            call starproj_stream%stream_export_particles_2D(pool_proj, params_glob%outdir, optics_set=.true.)
            if( DEBUG_HERE ) print *,'ptcl_export  : ', toc(t); call flush(6)
        end if
        call pool_proj%write(projfile)
        call pool_proj%os_ptcl3D%kill
        call pool_proj%os_cls2D%delete_entry('stk')
    end subroutine write_project_stream2D

    ! POOL

    ! Appends new data for processing
    subroutine import_records_into_pool( records )
        type(projrecord), allocatable, intent(inout) :: records(:)
        type(sp_project)      :: spproj
        character(LONGSTRLEN) :: projname
        integer :: nptcls2import, nmics2import, imic, nrecords
        integer :: fromp, i, nmics_imported, nptcls_imported, iptcl, irec
        if( .not. allocated(records) ) return
        if( .not. stream2D_active )    return
        if( .not.pool_available )      return
        if( all(records(:)%included) ) return
        nrecords        = size(records)
        nmics_imported  = pool_proj%os_mic%get_noris()
        nptcls_imported = pool_proj%os_ptcl2D%get_noris()
        nmics2import    = count(.not.records(:)%included)
        nptcls2import   = sum(records(:)%nptcls, mask=.not.records(:)%included)
        ! reallocations
        nmics_imported  = pool_proj%os_mic%get_noris()
        nptcls_imported = pool_proj%os_ptcl2D%get_noris()
        if( nmics_imported == 0 )then
            call pool_proj%os_mic%new(nmics2import, is_ptcl=.false.)
            call pool_proj%os_stk%new(nmics2import, is_ptcl=.false.)
            call pool_proj%os_ptcl2D%new(nptcls2import, is_ptcl=.true.)
            fromp = 1
        else
            call pool_proj%os_mic%reallocate(nmics_imported+nmics2import)
            call pool_proj%os_stk%reallocate(nmics_imported+nmics2import)
            call pool_proj%os_ptcl2D%reallocate(nptcls_imported+nptcls2import)
            fromp = pool_proj%os_stk%get_top(nmics_imported)+1
        endif
        imic     = nmics_imported
        projname = ''
        do irec = 1,nrecords
            if( records(irec)%included ) cycle
            if( trim(projname) /= records(irec)%projname )then
                call spproj%read_mic_stk_ptcl2D_segments(records(irec)%projname)
                projname = trim(records(irec)%projname)
            endif
            ! mic & stack
            imic = imic + 1
            call pool_proj%os_mic%transfer_ori(imic, spproj%os_mic, records(irec)%micind)
            call pool_proj%os_stk%transfer_ori(imic, spproj%os_stk, records(irec)%micind)
            call pool_proj%os_stk%set(imic, 'fromp', fromp)
            call pool_proj%os_stk%set(imic, 'top',   fromp+records(irec)%nptcls-1)
            ! particles
            !$omp parallel do private(i,iptcl) proc_bind(close) default(shared)
            do i = 1,records(irec)%nptcls
                iptcl = fromp + i - 1
                call pool_proj%os_ptcl2D%transfer_ori(iptcl, spproj%os_ptcl2D, i)
                call pool_proj%os_ptcl2D%set_stkind(iptcl, imic)
                call pool_proj%os_ptcl2D%set(iptcl, 'updatecnt', 0)
                call pool_proj%os_ptcl2D%set(iptcl, 'frac',      0.0)
                call pool_proj%os_ptcl2D%set(iptcl, 'eo',        merge(0, 1, is_even(iptcl)))
                call pool_proj%os_ptcl2D%set(iptcl, 'w',         1.0)
                call pool_proj%os_ptcl2D%set_class(iptcl, irnd_uni(params_glob%ncls))
            enddo
            !$omp end parallel do
            fromp = fromp + records(irec)%nptcls
            records(irec)%included = .true. ! record update
        enddo
        call spproj%kill
    end subroutine import_records_into_pool

    ! Performs one classification iteration:
    ! updates to command-line, particles sampling, temporary project & execution
    subroutine classify_pool
        use simple_ran_tabu
        logical,                   parameter   :: L_BENCH = .false.
        type(ran_tabu)                         :: random_generator
        type(sp_project)                       :: spproj
        type(cmdline),             allocatable :: clines(:)
        integer,                   allocatable :: min_update_cnts_per_stk(:), nptcls_per_stk(:), stk_order(:)
        integer,                   allocatable :: prev_eo_pops(:,:), prev_eo_pops_thread(:,:)
        character(len=:),          allocatable :: stack_fname, ext, fbody
        character(len=LONGSTRLEN), allocatable :: sigma_fnames(:)
        real                    :: frac_update
        integer                 :: iptcl,i, nptcls_tot, nptcls_old, fromp, top, nstks_tot, jptcl
        integer                 :: eo, icls, nptcls_sel, istk, nptcls2update, nstks2update, jjptcl
        integer(timer_int_kind) :: t_tot
        if( .not. stream2D_active ) return
        if( .not.pool_available )   return
        if( L_BENCH ) t_tot  = tic()
        nptcls_tot           = pool_proj%os_ptcl2D%get_noris()
        nptcls_glob          = nptcls_tot
        nptcls_rejected_glob = 0
        if( nptcls_tot == 0 ) return
        pool_iter = pool_iter + 1 ! Global iteration counter update
        call cline_cluster2D_pool%set('refs',    refs_glob)
        call cline_cluster2D_pool%set('ncls',    ncls_glob)
        call cline_cluster2D_pool%set('startit', pool_iter)
        call cline_cluster2D_pool%set('maxits',  pool_iter)
        call cline_cluster2D_pool%set('frcs',    FRCS_FILE)
        if( l_no_chunks )then
            ! for reference generation everything is defined here
            call cline_cluster2D_pool%set('extr_iter', CHUNK_EXTR_ITER+pool_iter-1)
            if( pool_iter == 1 )then
                call cline_cluster2D_pool%delete('frcs')
                call cline_cluster2D_pool%delete('refs')
            endif
            call cline_cluster2D_pool%set('center','no')
            if( pool_iter < 5 )then
                call cline_cluster2D_pool%delete('lpstart')
                call cline_cluster2D_pool%delete('lpstop')
                call cline_cluster2D_pool%set('lp', lpstart)
                call cline_cluster2D_pool%set('trs', 0)
            else
                call cline_cluster2D_pool%set('trs',    MINSHIFT)
                call cline_cluster2D_pool%set('center', params_glob%center)
            endif
            call cline_cluster2D_pool%set('needs_sigma', 'no')
            call cline_cluster2D_pool%set('objfun',      'cc')
            call cline_cluster2D_pool%set('ml_reg',      'no')
            call cline_cluster2D_pool%delete('cc_iters')
            if( params_glob%cc_objfun .eq. OBJFUN_EUCLID )then
                if( iterswitch2euclid == 0 )then
                    ! switch to objfun=euclid when good enough resolution
                    if( current_resolution < lpstart .and. pool_iter > CHUNK_CC_ITERS )then
                        iterswitch2euclid = pool_iter+1
                    endif
                else if( iterswitch2euclid == pool_iter )then
                    ! switch
                    call cline_cluster2D_pool%set('needs_sigma','yes')
                    call cline_cluster2D_pool%set('objfun',     'euclid')
                    call cline_cluster2D_pool%set('cc_iters',    0)
                    call cline_cluster2D_pool%set('sigma_est',  'global')
                    call cline_cluster2D_pool%set('ml_reg',     params_glob%ml_reg_pool)
                    call cline_cluster2D_pool%set('lpstart',    lpstart)
                    call cline_cluster2D_pool%set('lpstop',     params_glob%lpstop)
                    call cline_cluster2D_pool%delete('lp')
                    allocate(clines(2))
                    ! sigmas2 are calculated first thing
                    call clines(1)%set('prg',        'calc_pspec_distr')
                    call clines(1)%set('oritype',    'ptcl2D')
                    call clines(1)%set('projfile',   PROJFILE_POOL)
                    call clines(1)%set('nthr',       cline_cluster2D_pool%get_iarg('nthr'))
                    call clines(1)%set('which_iter', pool_iter)
                    call clines(1)%set('mkdir',      'yes')
                    call clines(1)%set('sigma_est',  'global')
                    call clines(1)%set('nparts',     params_glob%nparts_pool)
                    clines(2) = cline_cluster2D_pool
                else
                    ! after switch
                    call cline_cluster2D_pool%set('needs_sigma','yes')
                    call cline_cluster2D_pool%set('objfun',     'euclid')
                    call cline_cluster2D_pool%set('cc_iters',   0)
                    call cline_cluster2D_pool%set('sigma_est',  'global')
                    call cline_cluster2D_pool%set('ml_reg',      params_glob%ml_reg_pool)
                    call cline_cluster2D_pool%set('lpstart',     lpstart)
                    call cline_cluster2D_pool%set('lpstop',      params_glob%lpstop)
                    do i = 1,params_glob%nparts_pool
                        call del_file(SIGMA2_FBODY//int2str_pad(i,numlen)//'.dat')
                    enddo
                endif
            else
                ! objfun = cc
                if( current_resolution < lpstart .and. pool_iter > CHUNK_CC_ITERS )then
                    call cline_cluster2D_pool%set('lpstart',lpstart)
                    call cline_cluster2D_pool%set('lpstop', params_glob%lpstop)
                    call cline_cluster2D_pool%delete('lp')
                endif
            endif
        endif
        ! project metadata update 
        spproj%projinfo = pool_proj%projinfo
        spproj%compenv  = pool_proj%compenv
        call spproj%projinfo%delete_entry('projname')
        call spproj%projinfo%delete_entry('projfile')
        call spproj%update_projinfo( cline_cluster2D_pool )
        ! Sampling of stacks that will be used for this iteration
        ! counting number of stacks & particles (old and newer)
        nstks_tot  = pool_proj%os_stk%get_noris()
        allocate(nptcls_per_stk(nstks_tot), min_update_cnts_per_stk(nstks_tot), source=0)
        nptcls_old = 0
        !$omp parallel do schedule(static) proc_bind(close) private(istk,fromp,top,iptcl)&
        !$omp default(shared) reduction(+:nptcls_old)
        do istk = 1,nstks_tot
            fromp = pool_proj%os_stk%get_fromp(istk)
            top   = pool_proj%os_stk%get_top(istk)
            min_update_cnts_per_stk(istk) = huge(istk)
            do iptcl = fromp,top
                if( pool_proj%os_ptcl2D%get_state(iptcl) > 0 )then
                    nptcls_per_stk(istk)          = nptcls_per_stk(istk) + 1 ! # ptcls with state=1
                    min_update_cnts_per_stk(istk) = min(min_update_cnts_per_stk(istk), pool_proj%os_ptcl2D%get_updatecnt(iptcl))
                endif
            enddo
            if( min_update_cnts_per_stk(istk) >= STREAM_SRCHLIM )then
                nptcls_old = nptcls_old + nptcls_per_stk(istk)
            endif
        enddo
        !$omp end parallel do
        nptcls_rejected_glob = nptcls_glob - sum(nptcls_per_stk)
        ! update info for gui
        call spproj%projinfo%set(1,'nptcls_tot',     nptcls_glob)
        call spproj%projinfo%set(1,'nptcls_rejected',nptcls_rejected_glob)
        ! flagging stacks to be skipped
        if( allocated(pool_stacks_mask) ) deallocate(pool_stacks_mask)
        allocate(pool_stacks_mask(nstks_tot), source=.false.)
        if( nptcls_old > params_glob%ncls_start*params_glob%nptcls_per_cls )then
            allocate(stk_order(nstks_tot), source=(/(istk,istk=1,nstks_tot)/))
            random_generator = ran_tabu(nstks_tot)
            call random_generator%shuffle(stk_order)
            nptcls2update = 0 ! # of ptcls including state=0 within selected stacks
            nptcls_sel    = 0 ! # of ptcls excluding state=0 within selected stacks
            do i = 1,nstks_tot
                istk = stk_order(i)
                if( (min_update_cnts_per_stk(istk) > STREAM_SRCHLIM) .and. (nptcls_sel > MAX_STREAM_NPTCLS) ) cycle
                nptcls_sel    = nptcls_sel + nptcls_per_stk(istk)
                nptcls2update = nptcls2update + pool_proj%os_stk%get_int(istk, 'nptcls')
                pool_stacks_mask(istk) = .true.
            enddo
            call random_generator%kill
        else
            nptcls2update    = nptcls_tot
            nptcls_sel       = sum(nptcls_per_stk)
            pool_stacks_mask = nptcls_per_stk > 0
        endif
        nstks2update = count(pool_stacks_mask)
        ! transfer stacks and particles
        call spproj%os_stk%new(nstks2update, is_ptcl=.false.)
        call spproj%os_ptcl2D%new(nptcls2update, is_ptcl=.true.)
        allocate(prev_eo_pops(ncls_glob,2),prev_eo_pops_thread(ncls_glob,2),source=0)
        i     = 0
        jptcl = 0
        do istk = 1,nstks_tot
            fromp = pool_proj%os_stk%get_fromp(istk)
            top   = pool_proj%os_stk%get_top(istk)
            if( pool_stacks_mask(istk) )then
                ! transfer alignement parameters for selected particles
                i = i + 1 ! stack index in spproj
                call spproj%os_stk%transfer_ori(i, pool_proj%os_stk, istk)
                call spproj%os_stk%set(i, 'fromp', jptcl+1)
                !$omp parallel do private(iptcl,jjptcl) proc_bind(close) default(shared)
                do iptcl = fromp,top
                    jjptcl = jptcl+iptcl-fromp+1
                    call spproj%os_ptcl2D%transfer_ori(jjptcl, pool_proj%os_ptcl2D, iptcl)
                    call spproj%os_ptcl2D%set_stkind(jjptcl, i)
                enddo
                !$omp end parallel do
                jptcl = jptcl + (top-fromp+1)
                call spproj%os_stk%set(i, 'top', jptcl)
            else
                ! keeps track of skipped particles
                prev_eo_pops_thread = 0
                !$omp parallel do private(iptcl,icls,eo) proc_bind(close) default(shared)&
                !$omp reduction(+:prev_eo_pops_thread)
                do iptcl = fromp,top
                    if( pool_proj%os_ptcl2D%get_state(iptcl) == 0 ) cycle
                    icls = pool_proj%os_ptcl2D%get_class(iptcl)
                    eo   = pool_proj%os_ptcl2D%get_eo(iptcl) + 1
                    prev_eo_pops_thread(icls,eo) = prev_eo_pops_thread(icls,eo) + 1
                enddo
                !$omp end parallel do
                prev_eo_pops = prev_eo_pops + prev_eo_pops_thread
            endif
        enddo
        call spproj%os_ptcl3D%new(nptcls2update, is_ptcl=.true.)
        spproj%os_cls2D = pool_proj%os_cls2D
        ! consolidate sigmas doc
        if( l_update_sigmas )then
            allocate(sigma_fnames(nstks2update))
            do istk = 1,nstks2update
                call spproj%os_stk%getter(istk,'stk',stack_fname)
                stack_fname = basename(stack_fname)
                ext         = fname2ext(stack_fname)
                fbody       = get_fbody(stack_fname, ext)
                sigma_fnames(istk) = trim(SIGMAS_DIR)//'/'//trim(fbody)//'.star'
            enddo
            call consolidate_sigma2_groups(sigma2_star_from_iter(pool_iter), sigma_fnames)
            deallocate(sigma_fnames)
            do i = 1,params_glob%nparts_pool
                call del_file(SIGMA2_FBODY//int2str_pad(i,numlen)//'.dat')
            enddo
        endif
        ! update command line with fractional update parameters
        call cline_cluster2D_pool%delete('update_frac')
        if( nptcls_sel > MAX_STREAM_NPTCLS )then
            if( (sum(prev_eo_pops) > 0) .and. (nptcls_old > 0))then
                frac_update = real(nptcls_old-sum(prev_eo_pops)) / real(nptcls_old)
                call cline_cluster2D_pool%set('update_frac', frac_update)
                call cline_cluster2D_pool%set('center',      'no')
                do icls = 1,ncls_glob
                    call spproj%os_cls2D%set(icls,'prev_pop_even',prev_eo_pops(icls,1))
                    call spproj%os_cls2D%set(icls,'prev_pop_odd', prev_eo_pops(icls,2))
                enddo
            endif
        endif
        ! write project
        call spproj%write(trim(POOL_DIR)//trim(PROJFILE_POOL))
        call spproj%kill
        ! pool stats
        call generate_pool_stats
        ! execution
        if( l_no_chunks .and. pool_iter == iterswitch2euclid )then
            write(logfhandle,'(A)')'>>> SWITCHING TO OBJFUN=EUCLID'
            call qenv_pool%exec_simple_prgs_in_queue_async(clines, DISTR_EXEC_FNAME, LOGFILE)
            call clines(:)%kill
            deallocate(clines)
        else
            call qenv_pool%exec_simple_prg_in_queue_async(cline_cluster2D_pool, DISTR_EXEC_FNAME, LOGFILE)
        endif
        pool_available = .false.
        write(logfhandle,'(A,I6,A,I8,A3,I8,A)')'>>> POOL         INITIATED ITERATION ',pool_iter,' WITH ',nptcls_sel,&
        &' / ', sum(nptcls_per_stk),' PARTICLES'
        if( L_BENCH ) print *,'timer classify_pool tot : ',toc(t_tot)
        call tidy_2Dstream_iter
    end subroutine classify_pool

    ! Flags pool availibility & updates the global name of references
    subroutine update_pool_status
        if( .not. stream2D_active ) return
        if( .not.pool_available )then
            pool_available = file_exists(trim(POOL_DIR)//trim(CLUSTER2D_FINISHED))
            if( pool_available .and. (pool_iter >= 1) )then
                refs_glob = trim(CAVGS_ITER_FBODY)//trim(int2str_pad(pool_iter,3))//trim(params_glob%ext)
            endif
        endif
    end subroutine update_pool_status

    ! Reports alignment info from completed iteration of subset
    ! of particles back to the pool
    subroutine update_pool
        type(sp_project)                       :: spproj
        type(oris)                             :: os
        type(class_frcs)                       :: frcs
        character(len=:),          allocatable :: stack_fname, ext, fbody
        character(len=LONGSTRLEN), allocatable :: sigma_fnames(:)
        integer,                   allocatable :: pops(:)
        character(len=STDLEN) :: fname
        integer               :: i, it, jptcl, iptcl, istk, nstks
        if( .not. stream2D_active ) return
        if( .not.pool_available )   return
        call del_file(trim(POOL_DIR)//trim(CLUSTER2D_FINISHED))
        ! iteration info
        fname = trim(POOL_DIR)//trim(STATS_FILE)
        if( file_exists(fname) )then
            call os%new(1,is_ptcl=.false.)
            call os%read(fname)
            it = os%get_int(1,'ITERATION')
            if( it == pool_iter )then
                conv_mi_class = os%get(1,'CLASS_OVERLAP')
                conv_frac     = os%get(1,'SEARCH_SPACE_SCANNED')
                conv_score    = os%get(1,'SCORE')
                write(logfhandle,'(A,I6,A,F7.3,A,F7.3,A,F7.3)')'>>> POOL         ITERATION ',it,&
                    &'; CLASS OVERLAP: ',conv_mi_class,'; SEARCH SPACE SCANNED: ',conv_frac,'; SCORE: ',conv_score
            endif
            call os%kill
        endif
        ! transfer to pool
        call spproj%read_segment('cls2D', trim(POOL_DIR)//trim(PROJFILE_POOL))
        if( spproj%os_cls2D%get_noris() == 0 )then
            ! not executed yet, do nothing
        else
            if( .not.allocated(pool_stacks_mask) )then
                THROW_HARD('Critical ERROR 0') ! first time
            endif
            ! transfer particles parameters
            call spproj%read_segment('stk',   trim(POOL_DIR)//trim(PROJFILE_POOL))
            call spproj%read_segment('ptcl2D',trim(POOL_DIR)//trim(PROJFILE_POOL))
            i = 0
            do istk = 1,size(pool_stacks_mask)
                if( pool_stacks_mask(istk) )then
                    i = i+1
                    iptcl = pool_proj%os_stk%get_fromp(istk)
                    do jptcl = spproj%os_stk%get_fromp(i),spproj%os_stk%get_top(i)
                        if( spproj%os_ptcl2D%get_state(jptcl) > 0 )then
                            call pool_proj%os_ptcl2D%transfer_2Dparams(iptcl, spproj%os_ptcl2D, jptcl)
                        endif
                        iptcl = iptcl+1
                    enddo
                endif
            enddo
            ! update classes info
            call pool_proj%os_ptcl2D%get_pops(pops, 'class', maxn=ncls_glob)
            pool_proj%os_cls2D = spproj%os_cls2D
            call pool_proj%os_cls2D%set_all('pop', real(pops))
            ! updates sigmas
            if( l_update_sigmas )then
                nstks = spproj%os_stk%get_noris()
                allocate(sigma_fnames(nstks))
                do istk = 1,nstks
                    call spproj%os_stk%getter(istk,'stk',stack_fname)
                    stack_fname = basename(stack_fname)
                    ext         = fname2ext(stack_fname)
                    fbody       = get_fbody(stack_fname, ext)
                    sigma_fnames(istk) = trim(SIGMAS_DIR)//'/'//trim(fbody)//'.star'
                enddo
                call split_sigma2_into_groups(sigma2_star_from_iter(pool_iter+1), sigma_fnames)
                deallocate(sigma_fnames)
            endif
            call frcs%read(trim(POOL_DIR)//trim(FRCS_FILE))
            current_resolution = frcs%estimate_lp_for_align()
            write(logfhandle,'(A,F5.1)')'>>> CURRENT POOL RESOLUTION: ',current_resolution
            call frcs%kill
            ! for gui
            call update_pool_for_gui
        endif
        call spproj%kill
    end subroutine update_pool

    ! Handles automated rejection scheme
    subroutine reject_from_pool
        type(image)          :: img
        integer, allocatable :: pops(:)
        logical, allocatable :: cls_mask(:), moments_mask(:), corres_mask(:)
        real                 :: ndev_here
        integer              :: nptcls_rejected, ncls_rejected, ncls2reject, iptcl
        integer              :: icls, ncls2reject_populated, ncls_populated
        if( .not. stream2D_active )                return       ! has been initiated
        if( trim(params_glob%reject_cls).eq.'no' ) return       ! obviously
        if( .not.pool_available )                  return       ! parameters accessible and synched
        if( ncls_glob < max_ncls )                 return       ! pool has been filled
        if( (pool_iter <= 2*FREQ_POOL_REJECTION) .or.&          ! From 3xFREQ_POOL_REJECTION
            &(mod(pool_iter,FREQ_POOL_REJECTION)/=0) ) return   ! occurs every FREQ_POOL_REJECTION
        if( nptcls_glob < MIN_NPTCLS_REJECTION )  return        ! More than MIN_NPTCLS_REJECTION in pool
        if( pool_proj%os_cls2D%get_noris() == 0 ) return        ! safeguard
        ncls_rejected   = 0
        nptcls_rejected = 0
        allocate(cls_mask(ncls_glob),moments_mask(ncls_glob),corres_mask(ncls_glob),source=.true.)
        allocate(pops(ncls_glob),source=nint(pool_proj%os_cls2D%get_all('pop')))
        ! moments & total variation distance
        if( trim(params_glob%reject_cls).ne.'old' )then
            call class_rejection(pool_proj%os_cls2D, moments_mask, adjust=params_glob%pool_threshold_factor)
        endif
        ! correlation & resolution
        if( params_glob%lpthres < LOWRES_REJECT_THRESHOLD )then
            ndev_here = params_glob%pool_threshold_factor*params_glob%ndev
            call pool_proj%os_cls2D%find_best_classes(pool_dims%box,pool_dims%smpd,params_glob%lpthres,corres_mask,ndev_here)
        endif
        ! overall class rejection
        cls_mask = moments_mask .and. corres_mask
        ! rejecting associated particles
        ncls2reject           = count(.not.cls_mask)
        ncls_populated        = count(pops>0)
        ncls2reject_populated = count((.not.cls_mask).and.(pops>0))
        if( ncls2reject > 0 .and.&
            & ncls2reject_populated < min(ncls_populated,nint(real(ncls_populated)*FRAC_SKIP_REJECTION)) )then
            ncls_rejected = 0
            !$omp parallel do private(iptcl,icls) reduction(+:nptcls_rejected) proc_bind(close)
            do iptcl = 1,pool_proj%os_ptcl2D%get_noris()
                if( pool_proj%os_ptcl2D%get_state(iptcl) == 0 )cycle
                icls = pool_proj%os_ptcl2D%get_class(iptcl)
                if( cls_mask(icls) ) cycle
                nptcls_rejected = nptcls_rejected+1
                call pool_proj%os_ptcl2D%set_state(iptcl,0)
                call pool_proj%os_ptcl2D%delete_2Dclustering(iptcl)
            enddo
            !$omp end parallel do
            if( nptcls_rejected > 0 )then
                ! classes
                call img%new([pool_dims%box,pool_dims%box,1], pool_dims%smpd)
                do icls = 1,ncls_glob
                    if( cls_mask(icls) ) cycle
                    if( pops(icls) > 0 )then
                        ncls_rejected_glob = ncls_rejected_glob + 1
                        call img%read(trim(POOL_DIR)//trim(refs_glob),icls)
                        call img%write(trim(POOL_DIR)//trim(CLS_POOL_REJECTED),ncls_rejected_glob)
                        img = 0.
                        call img%write(trim(POOL_DIR)//trim(refs_glob),icls)
                        if( l_wfilt )then
                            call img%write(trim(POOL_DIR)//trim(add2fbody(refs_glob, params_glob%ext,trim(WFILT_SUFFIX))),icls)
                        endif
                    endif
                enddo
                call img%read(trim(POOL_DIR)//trim(refs_glob), ncls_glob)
                call img%write(trim(POOL_DIR)//trim(refs_glob), ncls_glob)
                if( l_wfilt )then
                    call img%read(trim(POOL_DIR)//trim(add2fbody(refs_glob, params_glob%ext,trim(WFILT_SUFFIX))), ncls_glob)
                    call img%write(trim(POOL_DIR)//trim(add2fbody(refs_glob, params_glob%ext,trim(WFILT_SUFFIX))), ncls_glob)
                endif
                ! cls2D field
                do icls=1,ncls_glob
                    if( .not.cls_mask(icls) )then
                        if( pops(icls) > 0 ) ncls_rejected = ncls_rejected+1
                        call pool_proj%os_cls2D%set(icls, 'pop',         0)
                        call pool_proj%os_cls2D%set(icls, 'corr',       -1.0)
                        call pool_proj%os_cls2D%set_state(icls,          0)
                        call pool_proj%os_cls2D%set(icls,'prev_pop_even',0)
                        call pool_proj%os_cls2D%set(icls,'prev_pop_odd', 0)
                    endif
                enddo
                deallocate(cls_mask)
                call img%kill
                write(logfhandle,'(A,I6,A,I6,A)')'>>> REJECTED FROM POOL: ',nptcls_rejected,' PARTICLES IN ',ncls_rejected,' CLUSTER(S)'
                ! write stream2d.star with ptcl numbers post rejection 
                call starproj%export_cls2D(pool_proj, pool_iter)
            endif
        else
            write(logfhandle,'(A,I4,A,I6,A)')'>>> NO PARTICLES FLAGGED FOR REJECTION FROM POOL'
        endif
    end subroutine reject_from_pool

    ! Handles user inputted class rejection
    subroutine reject_from_pool_user
        type(image)          :: img
        type(oris)           :: cls2reject
        logical, allocatable :: cls_mask(:)
        integer              :: nptcls_rejected, ncls_rejected, iptcl
        integer              :: icls, jcls, i, nl
        if( .not. stream2D_active ) return
        if( .not.pool_available )   return
        if( pool_proj%os_cls2D%get_noris() == 0 ) return
        if( .not.file_exists(STREAM_REJECT_CLS) ) return
        nl = nlines(STREAM_REJECT_CLS)
        if( nl == 0 ) return
        call cls2reject%new(nl,is_ptcl=.false.)
        call cls2reject%read(STREAM_REJECT_CLS)
        call del_file(STREAM_REJECT_CLS)
        if( cls2reject%get_noris() == 0 ) return
        allocate(cls_mask(ncls_glob), source=.false.)
        do i = 1,cls2reject%get_noris()
            icls = cls2reject%get_class(i)
            if( icls == 0 ) cycle
            if( icls > ncls_glob ) cycle
            if( pool_proj%os_cls2D%get_int(icls,'pop') == 0 ) cycle
            cls_mask(icls) = .true.
        enddo
        call cls2reject%kill
        if( count(cls_mask) == 0 ) return
        call img%new([pool_dims%box,pool_dims%box,1], pool_dims%smpd)
        img = 0.
        ncls_rejected   = 0
        do icls = 1,ncls_glob
            if( .not.cls_mask(icls) ) cycle
            nptcls_rejected = 0
            !$omp parallel do private(iptcl,jcls) reduction(+:nptcls_rejected) proc_bind(close)
            do iptcl = 1,pool_proj%os_ptcl2D%get_noris()
                if( pool_proj%os_ptcl2D%get_state(iptcl) == 0 )cycle
                jcls = pool_proj%os_ptcl2D%get_class(iptcl)
                if( jcls == icls )then
                    call pool_proj%os_ptcl2D%reject(iptcl)
                    call pool_proj%os_ptcl2D%delete_2Dclustering(iptcl)
                    nptcls_rejected = nptcls_rejected + 1
                endif
            enddo
            !$omp end parallel do
            if( nptcls_rejected > 0 )then
                ncls_rejected = ncls_rejected + 1
                call pool_proj%os_cls2D%set_state(icls,0)
                call pool_proj%os_cls2D%set(icls,'pop',0.)
                call pool_proj%os_cls2D%set(icls,'corr',-1.)
                call pool_proj%os_cls2D%set(icls,'prev_pop_even',0.)
                call pool_proj%os_cls2D%set(icls,'prev_pop_odd', 0.)
                call img%write(trim(POOL_DIR)//trim(refs_glob),icls)
                if( l_wfilt )then
                    call img%write(trim(POOL_DIR)//trim(add2fbody(refs_glob, params_glob%ext,trim(WFILT_SUFFIX))), icls)
                endif
                write(logfhandle,'(A,I6,A,I4)')'>>> USER REJECTED FROM POOL: ',nptcls_rejected,' PARTICLE(S) IN CLASS ',icls
            endif
        enddo
        call img%read(trim(POOL_DIR)//trim(refs_glob), ncls_glob)
        call img%write(trim(POOL_DIR)//trim(refs_glob), ncls_glob)
        if( l_wfilt )then
            call img%read(trim(POOL_DIR)//trim(add2fbody(refs_glob, params_glob%ext,trim(WFILT_SUFFIX))), ncls_glob)
            call img%write(trim(POOL_DIR)//trim(add2fbody(refs_glob, params_glob%ext,trim(WFILT_SUFFIX))), ncls_glob)
        endif
        call img%kill
        ! write stream2d.star with ptcl numbers post rejection 
        call starproj%export_cls2D(pool_proj, pool_iter)
    end subroutine reject_from_pool_user

    ! GUI class selection/reporting, only used in gen_picking_refs
    subroutine write_pool_cls_selected_user
        type(image)              :: img, jpegimg
        type(stack_io)           :: stkio_r, stkio_w
        type(oris)               :: cls2reject
        logical, allocatable     :: cls_mask(:)
        integer                  :: i, nl, icls, isel
        if( .not. stream2D_active ) return
        if( pool_proj%os_cls2D%get_noris() == 0 ) return
        if( .not.file_exists(STREAM_REJECT_CLS) ) return
        nl = nlines(STREAM_REJECT_CLS)
        if( nl == 0 ) return
        call cls2reject%new(nl,is_ptcl=.false.)
        call cls2reject%read(STREAM_REJECT_CLS)
        call del_file(STREAM_REJECT_CLS)
        if( cls2reject%get_noris() == 0 ) return
        allocate(cls_mask(ncls_glob), source=.true.)
        do i = 1,pool_proj%os_cls2D%get_noris()
            if( pool_proj%os_cls2D%get_int(i,'pop') == 0 ) cls_mask(i) = .false.
            if( pool_proj%os_cls2D%get_state(i)     == 0 ) cls_mask(i) = .false.
        enddo
        do i = 1,cls2reject%get_noris()
            icls = cls2reject%get_class(i)
            if( icls == 0 ) cycle
            if( icls > ncls_glob ) cycle
            cls_mask(icls) = .false.
        enddo
        call cls2reject%kill
        write(logfhandle,'(A,I6,A)')'>>> USER SELECTED FROM POOL: ',count(cls_mask),' clusters'
        if( count(cls_mask) == 0 ) return
        write(logfhandle,'(A,A)')'>>> WRITING SELECTED CLUSTERS TO: ', trim(POOL_DIR) // STREAM_SELECTED_REFS//trim(STK_EXT)
        call img%new([params_glob%box,params_glob%box,1], params_glob%smpd)
        call jpegimg%new([params_glob%box, params_glob%box * count(cls_mask), 1], params_glob%smpd) 
        call stkio_r%open(trim(POOL_DIR) // trim(refs_glob), params_glob%smpd, 'read', bufsz=ncls_glob)
        call stkio_r%read_whole
        call stkio_w%open(trim(POOL_DIR) // STREAM_SELECTED_REFS//trim(STK_EXT), params_glob%smpd, 'write', box=params_glob%box, bufsz=count(cls_mask))
        isel = 1
        do icls = 1,ncls_glob
            if( .not. cls_mask(icls) ) then
                call pool_proj%os_cls2D%set_state(icls, 0)
            else
                call pool_proj%os_cls2D%set_state(icls, 1)
                call pool_proj%os_cls2D%set(icls,'stk', trim(cwd_glob) // '/' // STREAM_SELECTED_REFS // trim(STK_EXT))
                call pool_proj%os_cls2D%set_stkind(icls, isel)
                call stkio_r%get_image(icls, img)
                call stkio_w%write(isel, img)
                call jpegimg%tile(img, 1, isel) 
                isel = isel + 1
            endif
        enddo
        call jpegimg%write_jpg(trim(POOL_DIR) // STREAM_SELECTED_REFS // trim(JPG_EXT))
        call stkio_r%close
        call stkio_w%close
        call img%kill
        call jpegimg%kill
        call starproj_stream%stream_export_picking_references(pool_proj, params_glob%outdir)
        if(allocated(cls_mask)) deallocate(cls_mask)
    end subroutine write_pool_cls_selected_user

    ! Reports stats to GUI
    subroutine generate_pool_stats
        type(guistats)            :: pool_stats
        character(len=LONGSTRLEN) :: cwd
        integer                   :: iter_loc
        real                      :: lpthres_sugg
        call simple_getcwd(cwd)
        if(file_exists(trim(adjustl(cwd))//'/'//trim(CLS2D_STARFBODY)//'_iter'//int2str_pad(pool_iter,3)//'.star')) then
            iter_loc = pool_iter
        else if(file_exists(trim(adjustl(cwd))//'/'//trim(CLS2D_STARFBODY)//'_iter'//int2str_pad(pool_iter - 1,3)//'.star')) then
            iter_loc = pool_iter - 1
        endif
        call pool_stats%init
        call pool_stats%set('particles', 'particles_assigned',  int2str(nptcls_glob - nptcls_rejected_glob) // '_(' // int2str(ceiling(100.0 * real(nptcls_glob - nptcls_rejected_glob) / real(nptcls_glob))) // '%)')
        call pool_stats%set('particles', 'particles_rejected',  int2str(nptcls_rejected_glob) // '_(' // int2str(floor(100.0 * real(nptcls_rejected_glob) / real(nptcls_glob))) // '%)')
        call pool_stats%set('2D', 'iteration',                  iter_loc,             primary=.true.)
        call pool_stats%set('2D', 'number_classes',             ncls_glob,            primary=.true.)
        call pool_stats%set('2D', 'number_classes_rejected',    ncls_rejected_glob,   primary=.true.)
        call mskdiam2streamresthreshold(params_glob%mskdiam, lpthres_sugg)
        if(current_resolution < lpthres_sugg / 4 .and. params_glob%lpthres > lpthres_sugg) then
            call pool_stats%set('2D', 'maximum_resolution', current_resolution, primary=.true., alert=.true., alerttext='maximum_resolution_suggests_&
            &using_a_cutoff_of_' // int2str(int(lpthres_sugg)) // 'Å_or_better' , notify=.false.)
        else
            call pool_stats%set('2D', 'maximum_resolution', current_resolution, primary=.true., alert=.false., notify=.true.)
        endif
        if(.not. file_exists(trim(adjustl(cwd)) // '/' // trim(CAVGS_ITER_FBODY) // int2str_pad(iter_loc, 3) // '.jpg')) then
            if(iter_loc > 0) call pool_stats%set_now('2D', 'iteration_time')
            call pool_stats%generate_2D_thumbnail('2D', 'top_classes', pool_proj%os_cls2D, iter_loc)
            call pool_stats%generate_2D_jpeg('latest', '', pool_proj%os_cls2D, iter_loc, pool_dims%smpd)
        endif
        call pool_stats%write(POOLSTATS_FILE)
        call pool_stats%kill
    end subroutine generate_pool_stats

    !> Sets xml beamtilts in pool
    subroutine read_pool_xml_beamtilts()
        type(Node), pointer     :: xmldoc, beamtiltnode, beamtiltnodex, beamtiltnodey
        integer                 :: i, iread
        integer(timer_int_kind) :: bt0
        real(timer_int_kind)    :: bt_read
        if( DEBUG_HERE ) bt0 = tic()
        iread = 0
        do i = 1, pool_proj%os_mic%get_noris()
            if ( pool_proj%os_mic%get(i, "tiltx") == 0.0 .and. pool_proj%os_mic%get(i, "tilty") == 0.0) then
                if(file_exists(pool_proj%os_mic%get_static(i, "meta"))) then
                    xmldoc        => parseFile(trim(adjustl(pool_proj%os_mic%get_static(i,"meta"))))
                    beamtiltnode  => item(getElementsByTagname(xmldoc, "BeamShift"),0)
                    beamtiltnodex => item(getElementsByTagname(beamtiltnode, "a:_x"), 0)
                    beamtiltnodey => item(getElementsByTagname(beamtiltnode, "a:_y"), 0)
                    call pool_proj%os_mic%set(i, "tiltx", str2real(getTextContent(beamtiltnodex)))
                    call pool_proj%os_mic%set(i, "tilty", str2real(getTextContent(beamtiltnodey)))
                    call destroy(xmldoc)
                    iread = iread + 1
                endif
            endif
        end do
        if(iread > 0) write(logfhandle,'(A,A,A)') '>>> READ POOL METADATA FOR ', int2str(iread), ' MOVIES'
        if( DEBUG_HERE )then
            bt_read = toc(bt0)
            print *,'bt_read  : ', bt_read; call flush(6)
        endif
    end subroutine read_pool_xml_beamtilts
    
    ! Sets optics groups in pool
    subroutine assign_pool_optics(cline_here, propagate)
        type(cmdline), intent(inout) :: cline_here
        logical, optional            :: propagate
        logical                      :: l_propagate
        integer(timer_int_kind)      :: ot0
        real(timer_int_kind)         :: ot_assign
        if( DEBUG_HERE ) ot0 = tic()
        l_propagate = .false.
        if(present(propagate)) l_propagate = propagate
        if(pool_proj%os_mic%get_noris() > nmics_last) then
            nmics_last = pool_proj%os_mic%get_noris()
            call starproj%assign_optics(cline_here, pool_proj, propagate=l_propagate)
            write(logfhandle,'(A,A,A)') '>>> ASSIGNED POOL OPTICS INTO ', int2str(pool_proj%os_optics%get_noris()), ' GROUPS'
        end if
        if( DEBUG_HERE )then
            ot_assign = toc(ot0)
            print *,'ot_assign  : ', ot_assign; call flush(6)
        endif
    end subroutine assign_pool_optics

    !> Updates the project watched by the gui for display
    subroutine update_pool_for_gui
        type(oris)                    :: os_backup
        type(starproject)             :: starproj
        character(len=:), allocatable :: src
        os_backup = pool_proj%os_cls2D
        call pool_proj%add_cavgs2os_out(trim(POOL_DIR)//trim(refs_glob), pool_dims%smpd, 'cavg')
        if( l_wfilt )then
            src = trim(POOL_DIR)//add2fbody(refs_glob,params_glob%ext,trim(WFILT_SUFFIX))
            call pool_proj%add_cavgs2os_out(src, pool_dims%smpd, 'cavg'//trim(WFILT_SUFFIX))
        endif
        pool_proj%os_cls2D = os_backup
        call pool_proj%write_segment_inside('out',   projfile4gui)
        call pool_proj%write_segment_inside('cls2D', projfile4gui)
        ! Write star file for iteration
        call starproj%export_cls2D(pool_proj, pool_iter)
        call pool_proj%os_cls2D%delete_entry('stk')
        call os_backup%kill
        call starproj%kill
    end subroutine update_pool_for_gui

    ! whether the pool available for another iteration
    logical function is_pool_available()
        is_pool_available = pool_available
    end function is_pool_available

    ! returns current pool iteration
    integer function get_pool_iter()
        get_pool_iter = pool_iter
    end function get_pool_iter

    ! CHUNKS RELATED

    ! Initiates classification of all available chunks
    subroutine classify_new_chunks( micproj_records )
        type(projrecord), intent(inout) :: micproj_records(:)
        integer :: ichunk, n_avail_chunks, n_spprojs_in, iproj, nptcls, n2fill
        integer :: first2import, last2import, n2import
        if( .not. stream2D_active ) return
        n_avail_chunks = count(chunks(:)%available)
        ! cannot import yet
        if( n_avail_chunks == 0 ) return
        n_spprojs_in = size(micproj_records)
        if( n_spprojs_in == 0 ) return
        ! how many n2fill chunks to load
        n2fill       = 0
        nptcls       = 0
        first2import = 0
        do iproj = 1,n_spprojs_in
            if( micproj_records(iproj)%included )cycle
            if( micproj_records(iproj)%nptcls_sel > 0 )then
                if( first2import == 0 ) first2import = iproj
                nptcls = nptcls + micproj_records(iproj)%nptcls_sel
                if( nptcls > nptcls_per_chunk )then
                    n2fill = n2fill+1
                    if( n2fill >= n_avail_chunks )exit
                    nptcls = 0
                endif
            else
                micproj_records(iproj)%included = .true. ! mask out empty stacks
            endif
        enddo
        if( n2fill == 0 ) return ! not enough particles
        do ichunk = 1,params_glob%nchunks
            if(.not.chunks(ichunk)%available) cycle
            if( n2fill == 0 ) exit
            n2fill   = n2fill - 1
            nptcls   = 0
            n2import = 0
            do iproj = first2import,n_spprojs_in
                nptcls   = nptcls   + micproj_records(iproj)%nptcls_sel
                n2import = n2import + 1
                if( nptcls > nptcls_per_chunk )then
                    last2import = iproj
                    exit
                endif
            enddo
            if( nptcls > nptcls_per_chunk )then
                call chunks(ichunk)%generate(micproj_records(first2import:last2import))
                micproj_records(first2import:last2import)%included = .true.
                ! execution
                call chunks(ichunk)%classify(l_update_sigmas)
                first2import = last2import + 1 ! to avoid cycling through all projects
            endif
        enddo
    end subroutine classify_new_chunks

    ! Deals with chunk completion, rejection, reset
    subroutine update_chunks
        type(stream_chunk), allocatable :: tmpchunks(:)
        integer :: ichunk, jchunk, nthr2D, n
        logical :: chunk_complete
        if( .not. stream2D_active ) return
        do ichunk = 1,params_glob%nchunks
            if( chunks(ichunk)%available ) cycle
            chunk_complete = .false.
            if( chunks(ichunk)%toclassify )then
                ! chunk meant to be classified
                if( chunks(ichunk)%has_converged() )then
                    chunk_complete = .true.
                    call chunks(ichunk)%display_iter
                    ! rejection
                    if( trim(params_glob%reject_cls).ne.'no' )then
                        call chunks(ichunk)%reject(params_glob%lpthres, params_glob%ndev)
                    endif
                endif
            else
                ! placeholder chunk (no classification performed, sigma2 only)
                if( chunks(ichunk)%has_converged() ) chunk_complete = .true.
            endif
            if( chunk_complete )then
                ! updates list of chunks to import
                if( allocated(converged_chunks) )then
                    ! append item
                    n = size(converged_chunks)
                    allocate(tmpchunks(n+1),source=[converged_chunks(:), chunks(ichunk)])
                    do jchunk = 1,n
                        call converged_chunks(jchunk)%kill
                    enddo
                    deallocate(converged_chunks)
                    allocate(converged_chunks(n+1),source=tmpchunks)
                    do jchunk = 1,n+1
                        call tmpchunks(jchunk)%kill
                    enddo
                    deallocate(tmpchunks)
                else
                    ! first item
                    allocate(converged_chunks(1),source=[chunks(ichunk)])
                endif
                ! reinit and deal with nthr2D != nthr
                glob_chunk_id = glob_chunk_id + 1
                ! deal with nthr2d .ne. nthr
                nthr2D = params_glob%nthr2D
                params_glob%nthr2D = cline_cluster2D_chunk%get_iarg('nthr')
                call chunks(ichunk)%init(glob_chunk_id, cline_cluster2D_chunk, pool_proj)
                params_glob%nthr2D = nthr2D
            endif
        enddo
    end subroutine update_chunks

    ! Transfer chunk into pool (alignment parameters, references)
    subroutine import_chunks_into_pool( nchunks_imported )
        integer, intent(out) :: nchunks_imported
        type(class_frcs)              :: frcs_glob, frcs_chunk, frcs_prev
        character(len=:), allocatable :: cavgs_chunk, dir_chunk
        integer,          allocatable :: cls_pop(:), cls_chunk_pop(:), pinds(:), states(:)
        real    :: smpd_here
        integer :: ichunk, nchunks2import, nptcls2import, nmics2import, nptcls, imic, iproj
        integer :: ncls_tmp, fromp_prev, fromp, ii, jptcl, i, poolind, n_remap, pop, nptcls_sel
        integer :: nmics_imported, nptcls_imported, iptcl, ind, ncls_here, icls
        logical :: l_maxed
        nchunks_imported = 0
        if( .not. stream2D_active )            return
        if( .not.pool_available )              return
        if( .not.allocated(converged_chunks) ) return
        nchunks2import = size(converged_chunks)
        if( nchunks2import == 0 ) return
        nptcls2import   = 0
        nmics2import    = 0
        do ichunk = 1,nchunks2import
            nptcls2import = nptcls2import + converged_chunks(ichunk)%nptcls
            nmics2import  = nmics2import  + converged_chunks(ichunk)%nmics
        enddo
        if( nptcls2import == 0 ) return
        call debug_print('in import_chunks_into_pool 1 '//int2str(nptcls2import))
        ! reallocations
        nmics_imported  = pool_proj%os_mic%get_noris()
        nptcls_imported = pool_proj%os_ptcl2D%get_noris()
        if( nmics_imported == 0 )then
            call pool_proj%os_mic%new(nmics2import, is_ptcl=.false.)
            call pool_proj%os_stk%new(nmics2import, is_ptcl=.false.)
            call pool_proj%os_ptcl2D%new(nptcls2import, is_ptcl=.true.)
            fromp = 1
        else
            call pool_proj%os_mic%reallocate(nmics_imported+nmics2import)
            call pool_proj%os_stk%reallocate(nmics_imported+nmics2import)
            call pool_proj%os_ptcl2D%reallocate(nptcls_imported+nptcls2import)
            fromp = pool_proj%os_stk%get_top(nmics_imported)+1
        endif
        imic  = nmics_imported
        call debug_print('in import_chunks_into_pool 2 '//int2str(imic)//' '//int2str(nptcls_imported))
        do ichunk = 1,nchunks2import
            fromp_prev = fromp
            call converged_chunks(ichunk)%read(chunk_dims%boxpd)
            ! transfer micrographs, stacks & particles parameters
            ind = 1
            do iproj = 1,converged_chunks(ichunk)%nmics
                imic  = imic+1
                ! micrographs
                call pool_proj%os_mic%transfer_ori(imic, converged_chunks(ichunk)%spproj%os_mic, iproj)
                ! stacks
                call pool_proj%os_stk%transfer_ori(imic, converged_chunks(ichunk)%spproj%os_stk, iproj)
                nptcls = converged_chunks(ichunk)%spproj%os_stk%get_int(iproj,'nptcls')
                call pool_proj%os_stk%set(imic, 'fromp', fromp)
                call pool_proj%os_stk%set(imic, 'top',   fromp+nptcls-1)
                ! particles
                !$omp parallel do private(i,iptcl,jptcl) default(shared) proc_bind(close)
                do i = 1,nptcls
                    iptcl = fromp + i - 1
                    jptcl = ind   + i - 1
                    call pool_proj%os_ptcl2D%transfer_ori(iptcl, converged_chunks(ichunk)%spproj%os_ptcl2D, jptcl)
                    call pool_proj%os_ptcl2D%set_stkind(iptcl, imic)
                    call pool_proj%os_ptcl2D%set(iptcl, 'updatecnt', 0)  ! new particle
                    call pool_proj%os_ptcl2D%set(iptcl, 'frac',      0.) ! new particle
                enddo
                !$omp end parallel do
                ind   = ind   + nptcls
                fromp = fromp + nptcls
            enddo
            nptcls_sel = converged_chunks(ichunk)%spproj%os_ptcl2D%get_noris(consider_state=.true.)
            ! storing sigmas as per stack individual documents
            if( l_update_sigmas ) call converged_chunks(ichunk)%split_sigmas_into(SIGMAS_DIR)
            ! display
            write(logfhandle,'(A,I6,A,I6,A)')'>>> TRANSFERRED ',nptcls_sel,' PARTICLES FROM CHUNK ',converged_chunks(ichunk)%id,' TO POOL'
            call flush(logfhandle)
            if( converged_chunks(ichunk)%toclassify )then
                ! this chunk underwent 2D classification, particles & classes are mapped
                ! transfer classes
                l_maxed   = ncls_glob >= max_ncls ! max # of classes reached
                ncls_here = ncls_glob
                if( .not.l_maxed ) ncls_here = ncls_glob + params_glob%ncls_start
                states = nint(converged_chunks(ichunk)%spproj%os_ptcl2D%get_all('state'))
                call converged_chunks(ichunk)%spproj%get_cavgs_stk(cavgs_chunk, ncls_tmp, smpd_here)
                dir_chunk   = trim(converged_chunks(ichunk)%path)
                cavgs_chunk = trim(dir_chunk)//basename(cavgs_chunk)
                call frcs_chunk%new(params_glob%ncls_start, chunk_dims%box, chunk_dims%smpd, nstates=1)
                call frcs_chunk%read(trim(dir_chunk)//trim(FRCS_FILE))
                if( l_maxed )then
                    ! the pool has been previously filled, some re-mapping of classes may occur
                    call debug_print('in import_chunks_into_pool 3 '//int2str(ichunk))
                    ! transfer all others
                    cls_pop = nint(pool_proj%os_cls2D%get_all('pop'))
                    n_remap = 0
                    if( any(cls_pop==0) )then
                        if( all(cls_pop==0) ) THROW_HARD('Empty os_cls2D!')
                        ! remapping
                        cls_chunk_pop = nint(converged_chunks(ichunk)%spproj%os_cls2D%get_all('pop'))
                        call frcs_glob%new(ncls_glob, pool_dims%box, pool_dims%smpd, nstates=1)
                        call frcs_glob%read(trim(POOL_DIR)//trim(FRCS_FILE))
                        do icls=1,ncls_glob
                            if( cls_pop(icls)>0 ) cycle          ! class already filled
                            if( all(cls_chunk_pop == 0 ) ) exit  ! no more chunk class available
                            ind = irnd_uni(params_glob%ncls_start)    ! selects chunk class stochastically
                            do while( cls_chunk_pop(ind) == 0 )
                                ind = irnd_uni(params_glob%ncls_start)
                            enddo
                            cls_chunk_pop(ind) = 0             ! excludes from being picked again
                            n_remap = n_remap+1
                            ! class average
                            call transfer_cavg(cavgs_chunk, dir_chunk, ind, refs_glob, icls)
                            ! frcs
                            call frcs_glob%set_frc(icls,frcs_chunk%get_frc(ind, chunk_dims%box, 1), 1)
                            ! class parameters transfer
                            call pool_proj%os_cls2D%transfer_ori(icls, converged_chunks(ichunk)%spproj%os_cls2D, ind)
                            call pool_proj%os_cls2D%set_class(icls, icls)
                            ! particles
                            call converged_chunks(ichunk)%spproj%os_ptcl2D%get_pinds(ind,'class',pinds)
                            pop = size(pinds)
                            do i=1,pop
                                ii      = pinds(i)            ! in chunk
                                poolind = fromp_prev + ii - 1 ! in pool
                                call pool_proj%os_ptcl2D%set_class(poolind,icls)
                            enddo
                            cls_pop(icls) = cls_pop(icls) + pop ! updates class populations
                        enddo
                        ! now transfer particles that were not remapped
                        do icls = 1,params_glob%ncls_start
                            if( cls_chunk_pop(icls) == 0 ) cycle
                            call converged_chunks(ichunk)%spproj%os_ptcl2D%get_pinds(icls,'class',pinds)
                            pop = size(pinds)
                            do i = 1,pop
                                ii      = pinds(i)              ! in chunk
                                poolind = fromp_prev + ii - 1   ! in pool
                                ind     = irnd_uni(ncls_glob)   ! stochastic labelling followed by greedy search
                                do while( cls_pop(ind) == 0 )   ! ignore empty classes
                                    ind = irnd_uni(ncls_glob)
                                enddo
                                call pool_proj%os_ptcl2D%set_class(poolind, ind)
                                cls_pop(ind) = cls_pop(ind) + 1 ! updates class populations
                            enddo
                        enddo
                        if( n_remap > 0 )then
                            call transfer_cavg(refs_glob,dir_chunk,ncls_glob,refs_glob,ncls_glob, self_transfer=.true.)
                            call frcs_glob%write(trim(POOL_DIR)//trim(FRCS_FILE))
                            write(logfhandle,'(A,I4)')'>>> # OF RE-MAPPED CLASS AVERAGES: ',n_remap
                        endif
                    else
                        call debug_print('in import_chunks_into_pool 4 '//int2str(ichunk))
                        ! no remapping, just transfer particles & updates 2D population
                        !$omp parallel do private(ii,poolind,icls) default(shared)&
                        !$omp proc_bind(close) reduction(+:cls_pop)
                        do ii = 1,converged_chunks(ichunk)%nptcls
                            if( states(ii) /= 0 )then
                                icls          = irnd_uni(ncls_glob) ! stochastic labelling followed by greedy search
                                cls_pop(icls) = cls_pop(icls) + 1   ! updates populations
                                poolind       = fromp_prev + ii - 1
                                call pool_proj%os_ptcl2D%set_class(poolind, icls)
                            endif
                        enddo
                        !$omp end parallel do
                    endif
                    ! updates class populations
                    call pool_proj%os_cls2D%set_all('pop',real(cls_pop))
                    call debug_print('in import_chunks_into_pool 5 '//int2str(ichunk))
                else
                    ! all new classes can be imported, no remapping
                    if( ncls_glob == 0 )then
                        ! first transfer : copy classes, frcs & class parameters
                        refs_glob = 'start_cavgs'//params_glob%ext
                        do icls= 1,params_glob%ncls_start
                            call transfer_cavg(cavgs_chunk,dir_chunk,icls,refs_glob,icls)
                        enddo
                        call simple_copy_file(trim(dir_chunk)//trim(FRCS_FILE),trim(POOL_DIR)//trim(FRCS_FILE))
                        pool_proj%os_cls2D = converged_chunks(ichunk)%spproj%os_cls2D
                    else
                        ! append new classes
                        do icls=1,params_glob%ncls_start
                            call transfer_cavg(cavgs_chunk, dir_chunk, icls, refs_glob, ncls_glob+icls)
                        enddo
                        ! FRCs
                        call frcs_glob%new(ncls_here, pool_dims%box, pool_dims%smpd, nstates=1)
                        call frcs_prev%new(ncls_glob, pool_dims%box, pool_dims%smpd, nstates=1)
                        call frcs_prev%read(trim(POOL_DIR)//trim(FRCS_FILE))
                        do icls=1,ncls_glob
                            call frcs_glob%set_frc(icls,frcs_prev%get_frc(icls, pool_dims%box, 1), 1)
                        enddo
                        do icls=1,params_glob%ncls_start
                            call frcs_glob%set_frc(ncls_glob+icls,frcs_chunk%get_frc(icls, pool_dims%box, 1), 1)
                        enddo
                        call frcs_glob%write(trim(POOL_DIR)//trim(FRCS_FILE))
                        ! class parameters
                        call pool_proj%os_cls2D%reallocate(ncls_here)
                        do icls = 1,params_glob%ncls_start
                            ind = ncls_glob+icls
                            call pool_proj%os_cls2D%transfer_ori(ind, converged_chunks(ichunk)%spproj%os_cls2D, icls)
                            call pool_proj%os_cls2D%set_class(ind, ind)
                        enddo
                    endif
                    call debug_print('in import_chunks_into_pool 7'//' '//int2str(ichunk))
                    ! particles 2D
                    !$omp parallel do private(ii,poolind,icls) default(shared) proc_bind(close)
                    do ii = 1,converged_chunks(ichunk)%nptcls
                        if( states(ii) /= 0 )then
                            poolind = fromp_prev+ii-1
                            icls    = ncls_glob + converged_chunks(ichunk)%spproj%os_ptcl2D%get_class(ii)
                            call pool_proj%os_ptcl2D%set_class(poolind, icls)
                        endif
                    enddo
                    !$omp end parallel do
                    ! global # of classes
                    ncls_glob = ncls_here
                endif
            else
                ! this chunk did not undergo 2D classification,
                ! particles are mapped to non-empty classes
                cls_pop = nint(pool_proj%os_cls2D%get_all('pop'))
                states  = nint(converged_chunks(ichunk)%spproj%os_ptcl2D%get_all('state'))
                do ii = 1,converged_chunks(ichunk)%nptcls
                    if( states(ii) /= 0 )then
                        icls = irnd_uni(ncls_glob)
                        do while( cls_pop(icls) == 0 )
                            icls = irnd_uni(ncls_glob)
                        enddo
                        cls_pop(icls) = cls_pop(icls) + 1
                        poolind       = fromp_prev + ii - 1
                        call pool_proj%os_ptcl2D%set_class(poolind, icls)
                        call pool_proj%os_ptcl2D%set(poolind, 'w', 1.0)
                    else
                        call pool_proj%os_ptcl2D%set_class(poolind, 0)
                    endif
                enddo
                call pool_proj%os_cls2D%set_all('pop',real(cls_pop))
            endif
            ! deactivating centering when chunks are imported
            if( nchunks_imported > 0 )then
                call cline_cluster2D_pool%set('center','no')
            else
                call cline_cluster2D_pool%set('center', params_glob%center)
            endif
            ! tidy
            if( trim(params_glob%remove_chunks).eq.'yes' ) call converged_chunks(ichunk)%remove_folder
            call converged_chunks(ichunk)%kill
        enddo
        nchunks_imported = nchunks2import
        call update_pool_for_gui
        ! cleanup
        deallocate(converged_chunks)
        call frcs_prev%kill
        call frcs_glob%kill
        call frcs_chunk%kill
        call debug_print('end import_chunks_into_pool')
    end subroutine import_chunks_into_pool

    !>  Transfers references & partial arrays from a chunk to the pool
    subroutine transfer_cavg( refs_in, dir, indin, refs_out, indout, self_transfer )
        character(len=*),  intent(in) :: refs_in, dir, refs_out
        integer,           intent(in) :: indin, indout
        logical, optional, intent(in) :: self_transfer
        type(image)                   :: img
        character(len=:), allocatable :: stkout, stkin, refs_out_here, refs_in_here
        integer :: ipart
        logical :: l_self
        call debug_print('in transfer_cavg '//int2str(indin)//' '//int2str(indout))
        l_self = .false.
        if( present(self_transfer) ) l_self = self_transfer
        if( l_self )then
            call debug_print('in transfer_cavg self_transfer')
            refs_in_here = trim(POOL_DIR)//trim(refs_in)
        else
            refs_in_here = trim(refs_in)
        endif
        ! making sure we are writing to the correct folder
        refs_out_here = trim(POOL_DIR)//trim(refs_out)
        ! merged class
        call img%new([chunk_dims%box,chunk_dims%box,1], chunk_dims%smpd) ! will need to be different chunk/pool
        call img%read( refs_in_here, indin)
        call img%write(refs_out_here,indout)
        if( l_wfilt )then
            stkout = add2fbody(refs_out_here,params_glob%ext,trim(WFILT_SUFFIX))
            call img%write(stkout,indout)
        endif
        ! e/o
        stkin  = add2fbody(refs_in_here, params_glob%ext,'_even')
        stkout = add2fbody(refs_out_here,params_glob%ext,'_even')
        call img%read( stkin, indin)
        call img%write(stkout,indout)
        stkin  = add2fbody(refs_in_here,params_glob%ext,'_odd')
        stkout = add2fbody(refs_out_here,params_glob%ext,'_odd')
        call img%read( stkin, indin)
        call img%write(stkout,indout)
        ! temporary matrices, logics from chunk%read
        call img%new([chunk_dims%boxpd,chunk_dims%boxpd,1], chunk_dims%smpd)
        call img%zero_and_flag_ft
        if( l_self )then
            do ipart = 1,params_glob%nparts_pool
                stkin = trim(POOL_DIR)//'cavgs_even_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                call img%read(stkin, indin)
                call img%write(stkin,indout)
                stkin = trim(POOL_DIR)//'cavgs_odd_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                call img%read(stkin, indin)
                call img%write(stkin,indout)
                stkin = trim(POOL_DIR)//'ctfsqsums_even_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                call img%read(stkin, indin)
                call img%write(stkin,indout)
                stkin = trim(POOL_DIR)//'ctfsqsums_odd_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                call img%read(stkin, indin)
                call img%write(stkin,indout)
                if( l_wfilt )then
                    stkin = trim(POOL_DIR)//'cavgs_even_wfilt_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                    call img%read(stkin, indin)
                    call img%write(stkin,indout)
                    stkin = trim(POOL_DIR)//'cavgs_odd_wfilt_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                    call img%read(stkin, indin)
                    call img%write(stkin,indout)
                    stkin = trim(POOL_DIR)//'ctfsqsums_even_wfilt_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                    call img%read(stkin, indin)
                    call img%write(stkin,indout)
                    stkin = trim(POOL_DIR)//'ctfsqsums_odd_wfilt_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                    call img%read(stkin, indin)
                    call img%write(stkin,indout)
                endif
            enddo
        else
            stkin  = trim(dir)//'/cavgs_even_part'//trim(params_glob%ext)
            call img%read(stkin, indin)
            do ipart = 1,params_glob%nparts_pool
                stkout = trim(POOL_DIR)//'cavgs_even_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                call img%write(stkout,indout)
                if( l_wfilt )then
                    stkout = trim(POOL_DIR)//'cavgs_even_wfilt_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                    call img%write(stkout,indout)
                endif
            enddo
            stkin  = trim(dir)//'/cavgs_odd_part'//trim(params_glob%ext)
            call img%read(stkin, indin)
            do ipart = 1,params_glob%nparts_pool
                stkout = trim(POOL_DIR)//'cavgs_odd_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                call img%write(stkout,indout)
                if( l_wfilt )then
                    stkout = trim(POOL_DIR)//'cavgs_odd_wfilt_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                    call img%write(stkout,indout)
                endif
            enddo
            stkin  = trim(dir)//'/ctfsqsums_even_part'//trim(params_glob%ext)
            call img%read(stkin, indin)
            do ipart = 1,params_glob%nparts_pool
                stkout = trim(POOL_DIR)//'ctfsqsums_even_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                call img%write(stkout,indout)
                if( l_wfilt )then
                    stkout = trim(POOL_DIR)//'ctfsqsums_even_wfilt_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                    call img%write(stkout,indout)
                endif
            enddo
            stkin  = trim(dir)//'/ctfsqsums_odd_part'//trim(params_glob%ext)
            call img%read(stkin, indin)
            do ipart = 1,params_glob%nparts_pool
                stkout = trim(POOL_DIR)//'ctfsqsums_odd_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                call img%write(stkout,indout)
                if( l_wfilt )then
                    stkout = trim(POOL_DIR)//'ctfsqsums_odd_wfilt_part'//int2str_pad(ipart,numlen)//trim(params_glob%ext)
                    call img%write(stkout,indout)
                endif
            enddo
        endif
        ! cleanup
        call img%kill
    end subroutine transfer_cavg

    ! To transfer unclassified particles to the pool
    ! a chunk is generated to calculate noise power
    subroutine flush_remaining_particles( micproj_records )
        type(projrecord), intent(inout) :: micproj_records(:)
        integer :: ichunk, n_avail_chunks, n_spprojs_in, iproj, nptcls
        integer :: first2import
        if( .not. stream2D_active ) return
        n_avail_chunks = count(chunks(:)%available)
        ! cannot import yet
        if( n_avail_chunks == 0 ) return
        n_spprojs_in = size(micproj_records)
        if( n_spprojs_in == 0 ) return
        ! how many n2fill chunks to load
        nptcls       = 0
        first2import = 0
        do iproj = 1,n_spprojs_in
            if( micproj_records(iproj)%included )cycle
            if( micproj_records(iproj)%nptcls_sel > 0 )then
                if( first2import == 0 ) first2import = iproj
                nptcls = nptcls + micproj_records(iproj)%nptcls_sel
            else
                micproj_records(iproj)%included = .true. ! mask out empty stacks
            endif
        enddo
        if( (nptcls==0) .or. (nptcls >= nptcls_per_chunk) )then
            ! zero or enough particles to build one chunk in classify_new_chunks
            return
        endif
        ! One chunk is generated with all unclassified particles
        do ichunk = 1,params_glob%nchunks
            if( chunks(ichunk)%available )then
                call chunks(ichunk)%generate(micproj_records(first2import:n_spprojs_in))
                micproj_records(first2import:n_spprojs_in)%included = .true.
                call chunks(ichunk)%calc_sigma2(cline_cluster2D_chunk, l_update_sigmas)
                exit !!
            endif
        enddo
    end subroutine flush_remaining_particles

    ! Are all chunks inactive
    logical function all_chunks_available()
        if( params_glob%nchunks == 0 )then
            all_chunks_available = .true.
        else
            all_chunks_available = all(chunks(:)%available)
        endif
    end function all_chunks_available

    ! CHECKPOINTING (IN PROGRESS)

    subroutine write_checkpoint
        character(len=:), allocatable :: dest, tmpl
        if( pool_iter < 1 )return
        call simple_mkdir(CHECKPOINT_DIR)
        call cline_cluster2D_pool%writeline(trim(CHECKPOINT_DIR)//'pool.cline')
        call cline_cluster2D_chunk%writeline(trim(CHECKPOINT_DIR)//'chunk.cline')
        call pool_proj%write(fname=trim(CHECKPOINT_DIR)//'mics.simple',  isegment=MIC_SEG)
        call pool_proj%write(fname=trim(CHECKPOINT_DIR)//'stks.simple',  isegment=STK_SEG)
        call pool_proj%write(fname=trim(CHECKPOINT_DIR)//'ptcls.simple', isegment=PTCL2D_SEG)
        call pool_proj%write(fname=trim(CHECKPOINT_DIR)//'cls.simple',   isegment=CLS2D_SEG)
        call simple_copy_file(refs_glob, trim(CHECKPOINT_DIR)//refs_glob)
        tmpl = get_fbody(refs_glob, params_glob%ext, separator=.false.)
        dest = add2fbody(tmpl,params_glob%ext,'_even')
        call simple_copy_file(dest, trim(CHECKPOINT_DIR)//dest)
        if( l_wfilt )then
            dest = add2fbody(dest,params_glob%ext,trim(WFILT_SUFFIX))
            call simple_copy_file(dest, trim(CHECKPOINT_DIR)//dest)
        endif
        dest = add2fbody(tmpl,params_glob%ext,'_odd')
        call simple_copy_file(dest, trim(CHECKPOINT_DIR)//dest)
        if( l_wfilt )then
            dest = add2fbody(dest,params_glob%ext,trim(WFILT_SUFFIX))
            call simple_copy_file(dest, trim(CHECKPOINT_DIR)//dest)
        endif
        call simple_copy_file(FRCS_FILE, trim(CHECKPOINT_DIR)//FRCS_FILE)
        call simple_copy_file(STATS_FILE, trim(CHECKPOINT_DIR)//STATS_FILE)
    end subroutine write_checkpoint

    subroutine read_checkpoint( found )
        logical, intent(out) :: found
        type(oris) :: os
        integer    :: iter
        found = .false.
        if( .not.dir_exists(CHECKPOINT_DIR) ) return
        if( .not.file_exists(trim(CHECKPOINT_DIR)//'mics.simple') ) return
        if( .not.file_exists(trim(CHECKPOINT_DIR)//'stks.simple') ) return
        if( .not.file_exists(trim(CHECKPOINT_DIR)//'ptcls.simple')) return
        if( .not.file_exists(trim(CHECKPOINT_DIR)//'cls.simple')  ) return
        if( .not.file_exists(trim(CHECKPOINT_DIR)//FRCS_FILE)     ) return
        if( .not.file_exists(trim(CHECKPOINT_DIR)//STATS_FILE)    ) return
        found = .true.
        call os%new(1,is_ptcl=.false.)
        call os%read(trim(CHECKPOINT_DIR)//STATS_FILE)
        iter = os%get_int(1,'ITERATION')
        call os%kill
    end subroutine read_checkpoint

    ! UTILITIES

    ! Remove previous files from folder to restart
    subroutine cleanup_root_folder( all )
        logical, optional, intent(in)  :: all
        character(len=LONGSTRLEN), allocatable :: files(:)
        character(len=STDLEN),     allocatable :: folders(:)
        integer :: i
        call qsys_cleanup(nparts=params_glob%nparts_pool)
        call simple_rmdir(SIGMAS_DIR)
        call del_file(USER_PARAMS)
        call del_file(PROJFILE_POOL)
        call del_file(DISTR_EXEC_FNAME)
        call del_file(TERM_STREAM)
        call simple_list_files_regexp('.', '\.mrc$|\.mrcs$|\.txt$|\.star$|\.eps$|\.jpeg$|\.jpg$|\.dat$|\.bin$', files)
        if( allocated(files) )then
            do i = 1,size(files)
                call del_file(files(i))
            enddo
        endif
        folders = simple_list_dirs('.')
        if( allocated(folders) )then
            do i = 1,size(folders)
                if( str_has_substr(folders(i),trim(DIR_CHUNK)) ) call simple_rmdir(folders(i))
            enddo
        endif
        if( present(all) )then
            if( all )then
                call del_file(LOGFILE)
                call del_file(CLUSTER2D_FINISHED)
                call del_file('simple_script_single')
            endif
        endif
    end subroutine cleanup_root_folder

    ! For ranking class-averages
    subroutine rank_cavgs
        type(rank_cavgs_commander) :: xrank_cavgs
        type(cmdline)              :: cline_rank_cavgs
        character(len=STDLEN)      :: refs_ranked, stk
        refs_ranked = add2fbody(refs_glob, params_glob%ext ,'_ranked')
        call cline_rank_cavgs%set('projfile', orig_projfile)
        if( l_wfilt )then
            stk = trim(POOL_DIR)//add2fbody(refs_glob,params_glob%ext,trim(WFILT_SUFFIX))
        else
            stk = trim(POOL_DIR)//trim(refs_glob)
        endif
        call cline_rank_cavgs%set('stk', stk)
        call cline_rank_cavgs%set('outstk',   trim(refs_ranked))
        call xrank_cavgs%execute_safe(cline_rank_cavgs)
        call cline_rank_cavgs%kill
    end subroutine rank_cavgs

    ! Final rescaling of references
    subroutine rescale_cavgs( src, dest )
        character(len=*), intent(in) :: src, dest
        type(image)          :: img, img_pad
        type(stack_io)       :: stkio_r, stkio_w
        character(len=:), allocatable :: dest_here
        integer, allocatable :: cls_pop(:)
        integer              :: ldim(3),icls, ncls_here
        call debug_print('in rescale_cavgs '//trim(src))
        call debug_print('in rescale_cavgs '//trim(dest))
        if(trim(src) == trim(dest))then
            dest_here = 'tmp_cavgs.mrc'
        else
            dest_here = trim(dest)
        endif
        call img%new([pool_dims%box,pool_dims%box,1],pool_dims%smpd)
        call img_pad%new([params_glob%box,params_glob%box,1],params_glob%smpd)
        cls_pop = nint(pool_proj%os_cls2D%get_all('pop'))
        call find_ldim_nptcls(src,ldim,ncls_here)
        call stkio_r%open(trim(src), pool_dims%smpd, 'read', bufsz=ncls_here)
        call stkio_r%read_whole
        call stkio_w%open(dest_here, params_glob%smpd, 'write', box=params_glob%box, bufsz=ncls_here)
        do icls = 1,ncls_here
            if( cls_pop(icls) > 0 )then
                call img%zero_and_unflag_ft
                call stkio_r%get_image(icls, img)
                call img%fft
                call img%pad(img_pad, backgr=0., antialiasing=.false.)
                call img_pad%ifft
            else
                img_pad = 0.
            endif
            call stkio_w%write(icls, img_pad)
        enddo
        call stkio_r%close
        call stkio_w%close
        if (trim(src) == trim(dest) ) call simple_rename('tmp_cavgs.mrc',dest)
        call img%kill
        call img_pad%kill
        call debug_print('end rescale_cavgs')
    end subroutine rescale_cavgs

    ! Removes some unnecessary files
    subroutine tidy_2Dstream_iter
        character(len=:), allocatable :: prefix
        if( pool_iter > 3 )then
            prefix = trim(POOL_DIR)//trim(CAVGS_ITER_FBODY)//trim(int2str_pad(pool_iter-3,3))
            call del_file(prefix//trim(JPG_EXT))
            call del_file(prefix//'_even'//trim(params_glob%ext))
            call del_file(prefix//'_odd'//trim(params_glob%ext))
            call del_file(prefix//trim(params_glob%ext))
            if( l_wfilt )then
                call del_file(prefix//trim(WFILT_SUFFIX)//'_even'//trim(params_glob%ext))
                call del_file(prefix//trim(WFILT_SUFFIX)//'_odd'//trim(params_glob%ext))
                call del_file(prefix//trim(WFILT_SUFFIX)//trim(params_glob%ext))
            endif
            call del_file(trim(POOL_DIR)//trim(CLS2D_STARFBODY)//'_iter'//int2str_pad(pool_iter-3,3)//'.star')
            call del_file(trim(prefix) // '.jpg')
            if( l_update_sigmas ) call del_file(trim(POOL_DIR)//trim(sigma2_star_from_iter(pool_iter-3)))
        endif
    end subroutine tidy_2Dstream_iter

    subroutine debug_print( string )
        character(len=*), intent(in) :: string
        if( DEBUG_HERE )then
            write(logfhandle,*) trim(string)
            call flush(logfhandle)
        endif
    end subroutine debug_print

    !
    ! cluster2D_subsets (=cluster2d_stream offline)
    !
    subroutine exec_cluster2D_subsets( self, cline )
        use simple_class_frcs, only: class_frcs
        class(cluster2D_commander_subsets), intent(inout) :: self
        class(cmdline),                     intent(inout) :: cline
        character(len=STDLEN), parameter :: DIR_PROJS   = trim(PATH_HERE)//'spprojs/'
        integer,               parameter :: WAITTIME    = 5
        type(projrecord),         allocatable  :: micproj_records(:)
        type(parameters)                       :: params
        type(sp_project)                       :: spproj_glob
        type(class_frcs)                       :: frcs, frcs_sc
        character(len=LONGSTRLEN), allocatable :: pool_stacks(:)
        character(len=:),          allocatable :: fname, stack_fname
        character(len=:),          allocatable :: frcsfname, src, orig_stack_fname
        integer,                   allocatable :: stk_nptcls(:), stk_all_nptcls(:), chunks_map(:,:)
        logical,                   allocatable :: pool_stk_mask(:)
        integer :: ichunk, istk, nstks, nptcls, nptcls_tot, ntot_chunks, cnt, ic, fromp, top
        integer :: maxits, pool_nstks, iptcl, jptcl, jstk, nchunks_imported, tot_nchunks_imported
        integer :: minits, nsplit
        logical :: all_chunks_submitted, all_chunks_imported, l_once, l_converged
        call cline%set('wiener', 'full')
        call cline%set('kweight_chunk','default')
        call cline%set('kweight_pool', 'default')
        call cline%set('autoscale',   'yes')
        call cline%set('ml_reg_chunk', 'no')
        call cline%set('ml_reg_pool',  'no')
        call cline%set('nthr2D', cline%get_iarg('nthr'))
        if( .not. cline%defined('mkdir')        ) call cline%set('mkdir',       'yes')
        if( .not. cline%defined('center')       ) call cline%set('center',      'yes')
        if( .not. cline%defined('lpthres')      ) call cline%set('lpthres',      30.0)
        if( .not. cline%defined('ndev')         ) call cline%set('ndev',         1.5)
        if( .not. cline%defined('oritype')      ) call cline%set('oritype',      'ptcl2D')
        if( .not. cline%defined('walltime')     ) call cline%set('walltime',     29*60) ! 29 minutes
        if( .not. cline%defined('nparts_chunk') ) call cline%set('nparts_chunk', 1)
        if( .not. cline%defined('nchunks')      ) call cline%set('nchunks',      2)
        if( .not. cline%defined('numlen')       ) call cline%set('numlen',       5)
        if( .not. cline%defined('objfun')       ) call cline%set('objfun',       'euclid')
        if( .not. cline%defined('sigma_est')    ) call cline%set('sigma_est',    'group')
        if( .not. cline%defined('reject_cls')   ) call cline%set('reject_cls',   'no')
        if( .not. cline%defined('remove_chunks')) call cline%set('remove_chunks','yes')
        call mskdiam2lplimits(cline%get_rarg('mskdiam'), lpstart, lpstop, lpcen)
        if( .not. cline%defined('lp') ) call cline%set('lp', lpstart)
        call seed_rnd
        call params%new(cline)
        if( cline%defined('lp') ) lpstart = params%lp
        l_wfilt         = trim(params%wiener) .eq. 'partial'
        l_update_sigmas = params%l_needs_sigma
        ! sanity
        if( .not.file_exists(params%projfile) )then
            THROW_HARD('project file: '//trim(params%projfile)//' does not exist!')
        endif
        orig_projfile = trim(params%projfile)
        call cline%set('mkdir','no')
        ! init
        l_scaling          = trim(params%autoscale) .eq. 'yes'
        max_ncls           = floor(real(params%ncls)/real(params%ncls_start))*params%ncls_start ! effective maximum # of classes
        nptcls_per_chunk   = params%nptcls_per_cls*params%ncls_start         ! # of particles in each chunk
        ncls_glob          = 0
        ncls_rejected_glob = 0
        l_abinitio2D       = cline%defined('algorithm')
        if( l_abinitio2D ) l_abinitio2D = str_has_substr(params_glob%algorithm,'abinitio')
        ! init command-lines
        call cline%delete('lp')
        call cline%delete('refine')
        call cline%delete('nptcls_per_cls')
        call cline%delete('ncls_start')
        call cline%delete('numlen')
        call cline%delete('kweight_chunk')
        call cline%delete('kweight_pool')
        call cline%delete('ml_reg_chunk')
        call cline%delete('ml_reg_pool')
        call cline%delete('autoscale')
        cline_cluster2D_pool   = cline
        cline_cluster2D_chunk  = cline
        ! scaling dimensions (fourier cropping)
        call set_scaling_dims
        ! subset classification
        if( l_abinitio2D )then
            ! prg=abinitio2D
            call cline_cluster2D_chunk%set('prg', 'abinitio2D')
            if( params_glob%nparts_chunk > 1 )then
                call cline_cluster2D_chunk%set('nparts', params_glob%nparts_chunk)
            endif
            if( cline%defined('cls_init') )then
                call cline_cluster2D_chunk%set('cls_init', params_glob%cls_init)
            else
                call cline_cluster2D_chunk%set('cls_init','rand')
            endif
        else
            ! prg=cluster2D
            if( params_glob%nparts_chunk > 1 )then
                call cline_cluster2D_chunk%set('prg',    'cluster2D_distr')
                call cline_cluster2D_chunk%set('nparts', params_glob%nparts_chunk)
            else
                call cline_cluster2D_chunk%set('prg',    'cluster2D')
            endif
            call cline_cluster2D_chunk%set('minits',    CHUNK_MINITS)
            call cline_cluster2D_chunk%set('maxits',    CHUNK_MAXITS)
            call cline_cluster2D_chunk%set('extr_iter', CHUNK_EXTR_ITER)
            call cline_cluster2D_chunk%set('extr_lim',  MAX_EXTRLIM2D)
            call cline_cluster2D_chunk%set('startit',   1)
            if( l_update_sigmas ) call cline_cluster2D_chunk%set('cc_iters', CHUNK_CC_ITERS)
            if( cline%defined('cls_init') )then
                call cline_cluster2D_chunk%set('cls_init', params_glob%cls_init)
            else
                call cline_cluster2D_chunk%set('cls_init','ptcl')
            endif
        endif
        call cline_cluster2D_chunk%delete('projfile')
        call cline_cluster2D_chunk%delete('projname')
        call cline_cluster2D_chunk%set('autoscale', 'no')
        call cline_cluster2D_chunk%set('mkdir',     'no')
        call cline_cluster2D_chunk%set('stream',    'no')
        call cline_cluster2D_chunk%set('ncls',      params%ncls_start)
        call cline_cluster2D_chunk%set('kweight',   params%kweight_chunk)
        call cline_cluster2D_chunk%set('ml_reg',    params%ml_reg_chunk)
        if( l_wfilt ) call cline_cluster2D_chunk%set('wiener',  'partial')
        call cline_cluster2D_chunk%delete('update_frac')
        call cline_cluster2D_chunk%delete('lpstop')
        ! pool classification: optional stochastic optimisation, optional match filter
        ! automated incremental learning
        call cline_cluster2D_pool%set('prg',       'cluster2D_distr')
        call cline_cluster2D_pool%set('autoscale', 'no')
        call cline_cluster2D_pool%set('trs',       MINSHIFT)
        call cline_cluster2D_pool%set('projfile',  PROJFILE_POOL)
        call cline_cluster2D_pool%set('projname',  trim(get_fbody(trim(PROJFILE_POOL),trim('simple'))))
        call cline_cluster2D_pool%set('extr_iter', 100)
        call cline_cluster2D_pool%set('mkdir',     'no')
        call cline_cluster2D_pool%set('async',     'yes') ! to enable hard termination
        call cline_cluster2D_pool%set('stream',    'yes') ! use for dual CTF treatment, sigma bookkeeping
        call cline_cluster2D_pool%set('nparts',    params%nparts_pool)
        call cline_cluster2D_pool%set('kweight',   params%kweight_pool)
        call cline_cluster2D_pool%set('ml_reg',    params%ml_reg_pool)
        if( l_wfilt ) call cline_cluster2D_pool%set('wiener', 'partial')
        if( l_update_sigmas ) call cline_cluster2D_pool%set('cc_iters', 0)
        call cline_cluster2D_pool%delete('lpstop')
        ! read strictly required fields
        call spproj_glob%read_non_data_segments(params%projfile)
        call spproj_glob%read_segment('mic',   params%projfile)
        call spproj_glob%read_segment('stk',   params%projfile)
        call spproj_glob%read_segment('ptcl2D',params%projfile)
        nstks = spproj_glob%os_stk%get_noris()
        ! sanity checks
        nptcls = spproj_glob%get_nptcls()
        if( nptcls == 0 )then
            THROW_HARD('No particles found in project file: '//trim(params%projfile)//'; exec_cluster2d_subsets')
        endif
        if ( nptcls < 2*nptcls_per_chunk )then
            THROW_WARN('Not enough particles to classify more than one subset')
            THROW_HARD('Review parameters or use cleanup2D/cluster2D instead')
        endif
        ! splitting
        if( spproj_glob%os_stk%get_noris() == 1 )then
            spproj_glob%os_ptcl3D = spproj_glob%os_ptcl2D
            nsplit = floor(real(spproj_glob%os_ptcl2D%get_noris())/real(nptcls_per_chunk))
            call spproj_glob%split_stk(nsplit, dir=PATH_PARENT)
            call spproj_glob%os_ptcl3D%kill
            nstks = nsplit
        endif
        ! directory structure & temporary project handling
        projfile4gui   = trim(orig_projfile)
        numlen         = len(int2str(params%nparts_pool))
        refs_glob      = 'start_cavgs'//params%ext
        pool_available = .true.
        pool_iter      = 0
        minits         = huge(minits)
        if( trim(POOL_DIR) /= '' ) call simple_mkdir(POOL_DIR)
        call simple_mkdir(trim(POOL_DIR)//trim(STDERROUT_DIR))
        call simple_mkdir(DIR_PROJS)
        if( l_update_sigmas ) call simple_mkdir(SIGMAS_DIR)
        call simple_touch(trim(POOL_DIR)//trim(CLUSTER2D_FINISHED))
        call pool_proj%kill
        pool_proj%projinfo = spproj_glob%projinfo
        pool_proj%compenv  = spproj_glob%compenv
        if( spproj_glob%jobproc%get_noris()>0 ) pool_proj%jobproc = spproj_glob%jobproc
        call pool_proj%projinfo%delete_entry('projname')
        call pool_proj%projinfo%delete_entry('projfile')
        call pool_proj%write(trim(POOL_DIR)//PROJFILE_POOL)
        ! updates command-lines with resolution limits
        call set_resolution_limits( cline )
        ! initialize chunks
        allocate(chunks(params%nchunks))
        do ichunk = 1,params%nchunks
            call chunks(ichunk)%init(ichunk, cline_cluster2D_chunk, pool_proj)
        enddo
        glob_chunk_id = params%nchunks
        ! Pool execution init
        call qenv_pool%new(params%nparts_pool,exec_bin='simple_private_exec',qsys_name='local')
        stream2D_active = .true.
        ! Particles/stacks, number of chunks
        allocate(stk_all_nptcls(nstks),stk_nptcls(nstks),source=0)
        ntot_chunks = 0
        cnt         = 0
        do istk = 1,nstks
            if( (spproj_glob%os_stk%get_state(istk)==0) .or. (spproj_glob%os_stk%get_int(istk,'nptcls')==0) )cycle
            fromp = spproj_glob%os_stk%get_fromp(istk)
            top   = spproj_glob%os_stk%get_top(istk)
            do iptcl = fromp,top
                stk_all_nptcls(istk) = stk_all_nptcls(istk) + 1 ! including state=0
                if( spproj_glob%os_ptcl2D%get_state(iptcl) == 0 ) cycle
                stk_nptcls(istk) = stk_nptcls(istk) + 1 ! excluding state=0
            enddo
            cnt = cnt + stk_nptcls(istk)
            if( cnt > nptcls_per_chunk )then
                ntot_chunks = ntot_chunks + 1
                cnt = 0
            endif
        enddo
        nptcls_tot = sum(stk_nptcls)
        write(logfhandle,'(A,I8)')'>>> # OF STACKS   : ', nstks
        write(logfhandle,'(A,I8)')'>>> # OF PARTICLES: ', nptcls_tot
        write(logfhandle,'(A,I8)')'>>> # OF CHUNKS   : ', ntot_chunks
        ! reformatting
        call generate_chunk_projects
        ! Near-infinite loop
        maxits = huge(maxits)     ! for convergence
        ichunk = 0                ! # of chunks that have been submitted
        tot_nchunks_imported = 0  ! Total # of chunks that are completed and imported into pool
        all_chunks_submitted = .false.
        all_chunks_imported  = .false.
        l_once      = .true.
        l_converged = .false.
        do
            ! sequential chunk prep
            if( .not.all_chunks_submitted )then
                do ic = 1,params%nchunks
                    if( all_chunks_submitted ) exit
                    if( chunks(ic)%available )then
                        ichunk = ichunk + 1
                        call classify_new_chunks(micproj_records)
                        if( ichunk == ntot_chunks )then
                            all_chunks_submitted = .true.
                            deallocate(micproj_records)
                            exit
                        endif
                    endif
                enddo
            endif
            ! streaming-like flow
            call update_chunks
            call update_pool_status
            call update_pool
            call reject_from_pool
            call reject_from_pool_user
            if( l_converged )then
                if( pool_available ) exit
            else
                l_converged = .false.
                if( all_chunks_imported )then
                    if( l_once )then
                        ! setting default min/max number of iterations
                        maxits = pool_iter + 2*STREAM_SRCHLIM
                        minits = pool_iter + STREAM_SRCHLIM
                        l_once = .false.
                        write(logfhandle,'(A)')'>>> ALL CHUNKS HAVE CONVERGED'
                        write(logfhandle,'(A,I6)')'>>> TERMINATING NO LATER THAN ITERATION: ',maxits
                    endif
                    if( pool_available )then
                        ! convergence
                        l_converged = (pool_iter >= minits)&
                            &.and. ((conv_mi_class > OVERLAP_2D_FRAC) .and. (conv_frac > FRACSRCHSPACE_2D))
                        l_converged = l_converged .or. (pool_iter >= maxits)
                    endif
                else
                    call import_chunks_into_pool(nchunks_imported)
                    tot_nchunks_imported = tot_nchunks_imported + nchunks_imported
                    all_chunks_imported  = tot_nchunks_imported == ntot_chunks
                endif
                if( .not.l_converged ) call classify_pool
                call sleep(WAITTIME)
            endif
        end do
        deallocate(stk_all_nptcls,stk_nptcls,chunks_map)
        ! maps stacks & gathering particles parameters
        ! only 2D parameters are transferred, everything else untouched
        pool_nstks = pool_proj%os_stk%get_noris()
        allocate(pool_stacks(pool_nstks), pool_stk_mask(pool_nstks))
        do istk = 1,pool_nstks
            call pool_proj%os_stk%getter(istk,'stk',fname)
            pool_stacks(istk) = basename(fname)
        enddo
        pool_stk_mask = .true.
        do istk = 1,nstks
            if( (spproj_glob%os_stk%get_state(istk)==0) .or. (spproj_glob%os_stk%get_int(istk,'nptcls')==0) )cycle
            call spproj_glob%os_stk%getter(istk,'stk',fname)
            orig_stack_fname = basename(fname)
            stack_fname = trim(orig_stack_fname)
            do jstk = 1,pool_nstks
                if( pool_stk_mask(jstk) )then
                    if( trim(stack_fname) == pool_stacks(jstk) )then
                        fromp  = spproj_glob%os_stk%get_fromp(istk)
                        top    = spproj_glob%os_stk%get_top(istk)
                        jptcl  = pool_proj%os_stk%get_fromp(jstk)
                        do iptcl = fromp,top
                            call spproj_glob%os_ptcl2D%transfer_2Dparams(iptcl, pool_proj%os_ptcl2D, jptcl)
                            jptcl = jptcl+1
                        enddo
                        pool_stk_mask(jstk) = .false. ! to be excluded from now on
                    endif
                endif
            enddo
        enddo
        ! rescale class-averages & parameters
        refs_glob = trim(POOL_DIR)//trim(refs_glob)
        frcsfname = trim(POOL_DIR)//trim(FRCS_FILE)
        if( l_scaling )then
            ! classes
            call rescale_cavgs(refs_glob, refs_glob)
            src  = add2fbody(refs_glob, params%ext,'_even')
            call rescale_cavgs(src, src)
            src  = add2fbody(refs_glob, params%ext,'_odd')
            call rescale_cavgs(src, src)
            if( l_wfilt )then
                src  = add2fbody(refs_glob, params%ext,trim(WFILT_SUFFIX))
                call rescale_cavgs(src, src)
                src  = add2fbody(refs_glob, params%ext,trim(WFILT_SUFFIX)//'_even')
                call rescale_cavgs(src, src)
                src  = add2fbody(refs_glob, params%ext,trim(WFILT_SUFFIX)//'_odd')
                call rescale_cavgs(src, src)
            endif
            ! frcs
            call frcs_sc%read(trim(POOL_DIR)//trim(FRCS_FILE))
            call frcs_sc%pad(params%smpd, params%box, frcs)
            call frcs%write(frcsfname)
            call frcs%kill
            call frcs_sc%kill
        endif
        call spproj_glob%os_out%kill
        call spproj_glob%add_cavgs2os_out(refs_glob, params%smpd, 'cavg')
        if( l_wfilt )then
            src = add2fbody(refs_glob,params%ext,trim(WFILT_SUFFIX))
            call spproj_glob%add_cavgs2os_out(src, params%smpd, 'cavg'//trim(WFILT_SUFFIX))
        endif
        spproj_glob%os_cls2D = pool_proj%os_cls2D
        call spproj_glob%add_frcs2os_out(frcsfname, 'frc2D')
        call pool_proj%kill
        ! classes export
        call starproj%export_cls2D(spproj_glob)
        call spproj_glob%os_cls2D%delete_entry('stk')
        ! 3D field
        spproj_glob%os_ptcl3D = spproj_glob%os_ptcl2D
        call spproj_glob%os_ptcl3D%delete_2Dclustering
        call spproj_glob%write(orig_projfile)
        ! ranking
        call rank_cavgs
        ! cleanup
        call simple_rmdir(STDERROUT_DIR)
        call simple_rmdir(DIR_PROJS)
        call del_file(trim(POOL_DIR)//trim(PROJFILE_POOL))
        call simple_rmdir(SIGMAS_DIR)
        call qsys_cleanup
        ! graceful end
        call simple_end('**** SIMPLE_CLUSTER2D_SUBSETS NORMAL STOP ****')

    contains

        subroutine generate_chunk_projects
            type(sp_project)              :: spproj
            character(len=:), allocatable :: fname,absfname,path,projname,projfile
            integer :: cnt,ichunk, istk, iptcl,jptcl,fromp,top,cfromp,ctop,n
            ! chnuks map
            allocate(chunks_map(ntot_chunks,2),source=0)
            cnt    = 0
            ichunk = 1
            do istk = 1,nstks
                if( ichunk > ntot_chunks ) exit
                if( cnt==0 ) chunks_map(ichunk,1) = istk
                cnt = cnt + stk_nptcls(istk)
                if( cnt > nptcls_per_chunk )then
                    chunks_map(ichunk,2) = istk
                    ichunk = ichunk + 1
                    cnt = 0
                endif
            enddo
            chunks_map(ntot_chunks,2) = nstks ! border effect
            write(logfhandle,'(A)')'>>> CHUNKS MAP: '
            spproj%compenv = spproj_glob%compenv
            spproj%jobproc = spproj_glob%jobproc
            call spproj%projinfo%new(1, is_ptcl=.false.)
            path = trim(cwd_glob)//'/'//trim(DIR_PROJS)
            call spproj%projinfo%set(1,'cwd', path)
            ! stacks/ptcls transfer
            allocate(micproj_records(nstks))
            do ichunk = 1,ntot_chunks
                projname = trim(int2str_pad(ichunk,6))
                projfile = trim(path)//trim(projname)//trim(METADATA_EXT)
                call spproj%projinfo%set(1,'projname', projname)
                call spproj%projinfo%set(1,'projfile', projfile)
                nstks  = chunks_map(ichunk,2) - chunks_map(ichunk,1) + 1
                nptcls = sum(stk_all_nptcls(chunks_map(ichunk,1):chunks_map(ichunk,2)))
                call spproj%os_stk%new(nstks, is_ptcl=.false.)
                call spproj%os_mic%new(nstks, is_ptcl=.false.)
                call spproj%os_ptcl2D%new(nptcls, is_ptcl=.true.)
                cnt   = 0
                ctop  = 0
                jptcl = 0 ! particle index in local project
                do istk = chunks_map(ichunk,1),chunks_map(ichunk,2)
                    cnt = cnt + 1
                    n   = stk_all_nptcls(istk)
                    ! dummy micrograph field
                    call spproj%os_mic%set(cnt,'nptcls', n)
                    call spproj%os_mic%set_state(cnt,spproj_glob%os_stk%get_state(istk))
                    ! stack
                    call spproj%os_stk%transfer_ori(cnt, spproj_glob%os_stk, istk)
                    call spproj%os_stk%getter(cnt,'stk',fname)
                    absfname = simple_abspath(fname)
                    call spproj%os_stk%set(cnt,'stk',absfname)
                    ! particle
                    fromp = spproj_glob%os_stk%get_fromp(istk)
                    top   = spproj_glob%os_stk%get_top(istk)
                    do iptcl = fromp,top
                        jptcl = jptcl + 1
                        call spproj%os_ptcl2D%transfer_ori(jptcl, spproj_glob%os_ptcl2D, iptcl)
                        call spproj%os_ptcl2D%set_stkind(jptcl, cnt)
                    enddo
                    cfromp = ctop + 1
                    ctop   = cfromp + n - 1
                    call spproj%os_stk%set(cnt,'fromp',cfromp)
                    call spproj%os_stk%set(cnt,'top',  ctop)
                    micproj_records(istk)%projname   = trim(projfile)
                    micproj_records(istk)%micind     = cnt
                    micproj_records(istk)%nptcls     = n
                    micproj_records(istk)%nptcls_sel = stk_nptcls(istk)
                    micproj_records(istk)%included   = .false.
                enddo
                call spproj%os_ptcl2D%delete_2Dclustering(keepshifts=.true., keepcls=.false.)
                call spproj%write(projfile)
                nptcls = sum(micproj_records(chunks_map(ichunk,1):chunks_map(ichunk,2))%nptcls_sel)
                write(logfhandle,'(A,I8,A,I8,A,I8)')'>>> CHUNK ID; # OF PARTICLES  : ',  ichunk,&
                    &' ; ',nptcls,' / ',sum(stk_nptcls)
            enddo
            call spproj%kill
        end subroutine generate_chunk_projects

    end subroutine exec_cluster2D_subsets

end module simple_commander_cluster2D_stream
