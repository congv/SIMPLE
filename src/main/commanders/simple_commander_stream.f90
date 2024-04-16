! concrete commander: streaming pre-processing routines
module simple_commander_stream
include 'simple_lib.f08'
use simple_binoris_io
use simple_cmdline,            only: cmdline
use simple_parameters,         only: parameters, params_glob
use simple_commander_base,     only: commander_base
use simple_sp_project,         only: sp_project
use simple_qsys_env,           only: qsys_env
use simple_starproject_stream, only: starproject_stream
use simple_guistats,           only: guistats
use simple_qsys_funs
use simple_commander_preprocess
use simple_progress
implicit none

public :: commander_stream_preprocess
public :: commander_stream_pick_extract
public :: commander_stream_assign_optics
public :: commander_stream_cluster2D

private
#include "simple_local_flags.inc"

type, extends(commander_base) :: commander_stream_preprocess
  contains
    procedure :: execute => exec_stream_preprocess
end type commander_stream_preprocess

type, extends(commander_base) :: commander_stream_pick_extract
  contains
    procedure :: execute => exec_stream_pick_extract
end type commander_stream_pick_extract

type, extends(commander_base) :: commander_stream_assign_optics
  contains
    procedure :: execute => exec_stream_assign_optics
end type commander_stream_assign_optics

type, extends(commander_base) :: commander_stream_cluster2D
  contains
    procedure :: execute => exec_stream_cluster2D
end type commander_stream_cluster2D

! module constants
character(len=STDLEN), parameter :: DIR_STREAM           = trim(PATH_HERE)//'spprojs/'           ! location for projects to be processed
character(len=STDLEN), parameter :: DIR_STREAM_COMPLETED = trim(PATH_HERE)//'spprojs_completed/' ! location for projects processed
character(len=STDLEN), parameter :: USER_PARAMS     = 'stream_user_params.txt'                   
integer,               parameter :: NMOVS_SET       = 5                                          ! number of movies processed at once (>1)
integer,               parameter :: LONGTIME        = 60                                        ! time lag after which a movie/project is processed
integer,               parameter :: WAITTIME        = 3    ! movie folder watched every WAITTIME seconds

contains

    subroutine exec_stream_preprocess( self, cline )
        use simple_moviewatcher, only: moviewatcher
        class(commander_stream_preprocess), intent(inout) :: self
        class(cmdline),                     intent(inout) :: cline
        type(parameters)                       :: params
        type(guistats)                         :: gui_stats
        integer,                   parameter   :: INACTIVE_TIME   = 900  ! inactive time trigger for writing project file
        logical,                   parameter   :: DEBUG_HERE      = .false.
        class(cmdline),            allocatable :: completed_jobs_clines(:), failed_jobs_clines(:)
        type(cmdline)                          :: cline_exec
        type(qsys_env)                         :: qenv
        type(moviewatcher)                     :: movie_buff
        type(sp_project)                       :: spproj_glob    ! global project
        type(starproject_stream)               :: starproj_stream
        character(len=LONGSTRLEN), allocatable :: movies(:)
        character(len=:),          allocatable :: output_dir, output_dir_ctf_estimate, output_dir_motion_correct
        integer                                :: movies_set_counter
        integer                                :: nmovies, imovie, stacksz, prev_stacksz, iter, last_injection, nsets, i,j
        integer                                :: cnt, n_imported, n_added, n_failed_jobs, n_fail_iter, nmic_star, iset
        logical                                :: l_movies_left, l_haschanged
        real                                   :: avg_tmp
        call cline%set('oritype',     'mic')
        call cline%set('mkdir',       'yes')
        call cline%set('reject_mics', 'no')
        call cline%set('groupframes', 'no')
        if( .not. cline%defined('walltime')         ) call cline%set('walltime',   29.0*60.0) ! 29 minutes
        ! motion correction
        if( .not. cline%defined('trs')              ) call cline%set('trs',              20.)
        if( .not. cline%defined('lpstart')          ) call cline%set('lpstart',           8.)
        if( .not. cline%defined('lpstop')           ) call cline%set('lpstop',            5.)
        if( .not. cline%defined('bfac')             ) call cline%set('bfac',             50.)
        if( .not. cline%defined('mcconvention')     ) call cline%set('mcconvention','simple')
        if( .not. cline%defined('eer_upsampling')   ) call cline%set('eer_upsampling',    1.)
        if( .not. cline%defined('algorithm')        ) call cline%set('algorithm',    'patch')
        if( .not. cline%defined('mcpatch')          ) call cline%set('mcpatch',        'yes')
        if( .not. cline%defined('mcpatch_thres')    ) call cline%set('mcpatch_thres','  yes')
        if( .not. cline%defined('tilt_thres')       ) call cline%set('tilt_thres',      0.05)
        if( .not. cline%defined('beamtilt')         ) call cline%set('beamtilt',        'no')
        ! ctf estimation
        if( .not. cline%defined('pspecsz')          ) call cline%set('pspecsz',         512.)
        if( .not. cline%defined('hp_ctf_estimate')  ) call cline%set('hp_ctf_estimate', HP_CTF_ESTIMATE)
        if( .not. cline%defined('lp_ctf_estimate')  ) call cline%set('lp_ctf_estimate', LP_CTF_ESTIMATE)
        if( .not. cline%defined('dfmin')            ) call cline%set('dfmin',           DFMIN_DEFAULT)
        if( .not. cline%defined('dfmax')            ) call cline%set('dfmax',           DFMAX_DEFAULT)
        if( .not. cline%defined('ctfpatch')         ) call cline%set('ctfpatch',        'yes')
        ! write cmdline for GUI
        call cline%writeline(".cline")
        ! sanity check for restart
        if( cline%defined('dir_exec') )then
            if( .not.file_exists(cline%get_carg('dir_exec')) )then
                THROW_HARD('Previous directory does not exists: '//trim(cline%get_carg('dir_exec')))
            endif
        endif
        ! master parameters
        call cline%set('numlen', 5.)
        call cline%set('stream','yes')
        call params%new(cline)
        params_glob%split_mode = 'stream'
        params_glob%ncunits    = params%nparts
        call cline%set('mkdir', 'no')
        call cline%set('prg',   'preprocess')
        ! master project file
        call spproj_glob%read( params%projfile )
        call spproj_glob%update_projinfo(cline)
        if( spproj_glob%os_mic%get_noris() /= 0 ) THROW_HARD('PREPROCESS_STREAM must start from an empty project (eg from root project folder)')
        ! movie watcher init
        movie_buff = moviewatcher(LONGTIME, params%dir_movies)
        ! guistats init
        call gui_stats%init
        call gui_stats%set('movies',      'movies_imported',      int2str(0), primary=.true.)
        call gui_stats%set('movies',      'movies_processed',     int2str(0), primary=.true.)
        call gui_stats%set('micrographs', 'micrographs',          int2str(0), primary=.true.)
        call gui_stats%set('micrographs', 'micrographs_rejected', int2str(0), primary=.true.)
        call gui_stats%set('compute',     'compute_in_use',       int2str(0) // '/' // int2str(params%nparts), primary=.true.)
        ! restart
        movies_set_counter = 0  ! global number of movies set
        nmic_star          = 0
        if( cline%defined('dir_exec') )then
            call del_file(TERM_STREAM)
            call cline%delete('dir_exec')
            call import_previous_projects
            nmic_star = spproj_glob%os_mic%get_noris()
            call write_mic_star_and_field(write_field=.true.)
            ! guistats
            call gui_stats%set('movies',      'movies_imported',      int2str(nmic_star),              primary=.true.)
            call gui_stats%set('movies',      'movies_processed',     int2str(nmic_star) // ' (100%)', primary=.true.)
            call gui_stats%set('micrographs', 'micrographs',          int2str(nmic_star),              primary=.true.)
            if(spproj_glob%os_mic%isthere("ctfres")) then
                avg_tmp = spproj_glob%os_mic%get_avg("ctfres")
                if(spproj_glob%os_mic%get_noris() > 50 .and. avg_tmp > 7.0) then
                    call gui_stats%set('micrographs', 'avg_ctf_resolution', avg_tmp, primary=.true., alert=.true., alerttext='average CTF resolution &
                        &lower than expected for high resolution structure determination', notify=.false.)
                else
                    call gui_stats%set('micrographs', 'avg_ctf_resolution', avg_tmp, primary=.true., alert=.false., notify=.true., notifytext='tick')
                end if
            end if
            if(spproj_glob%os_mic%isthere("icefrac")) then
                avg_tmp = spproj_glob%os_mic%get_avg("icefrac")
                if(spproj_glob%os_mic%get_noris() > 50 .and. avg_tmp > 1.0) then
                    call gui_stats%set('micrographs', 'avg_ice_score', avg_tmp, primary=.true., alert=.true., alerttext='average ice score &
                        &greater than expected for high resolution structure determination', notify=.false.)
                else
                    call gui_stats%set('micrographs', 'avg_ice_score', avg_tmp, primary=.true., alert=.false., notify=.true., notifytext='tick')
                end if
            end if
            if(spproj_glob%os_mic%isthere("astig")) then
                avg_tmp = spproj_glob%os_mic%get_avg("astig")
                if(spproj_glob%os_mic%get_noris() > 50 .and. avg_tmp > 0.1) then
                    call gui_stats%set('micrographs', 'avg_astigmatism', avg_tmp, primary=.true., alert=.true., alerttext='average astigmatism &
                        &greater than expected for high resolution structure determination', notify=.false.)
                else
                    call gui_stats%set('micrographs', 'avg_astigmatism', avg_tmp, primary=.true., alert=.false., notify=.true., notifytext='tick')
                end if
            end if
            if(spproj_glob%os_mic%isthere('thumb')) then
                call gui_stats%set('latest', '', trim(adjustl(CWD_GLOB))//'/'//&
                    &trim(adjustl(spproj_glob%os_mic%get_static(spproj_glob%os_mic%get_noris(),'thumb'))), thumbnail=.true.)
            end if
        endif
        ! output directories
        call simple_mkdir(trim(PATH_HERE)//trim(DIR_STREAM_COMPLETED))
        output_dir = trim(PATH_HERE)//trim(DIR_STREAM)
        call simple_mkdir(output_dir)
        call simple_mkdir(trim(output_dir)//trim(STDERROUT_DIR))
        output_dir_ctf_estimate   = filepath(trim(PATH_HERE), trim(DIR_CTF_ESTIMATE))
        output_dir_motion_correct = filepath(trim(PATH_HERE), trim(DIR_MOTION_CORRECT))
        call simple_mkdir(output_dir_ctf_estimate,errmsg="commander_stream :: exec_preprocess_stream;  ")
        call simple_mkdir(output_dir_motion_correct,errmsg="commander_stream :: exec_preprocess_stream;  ")
        call cline%set('dir','../')
        ! initialise progress monitor
        call progressfile_init()
        ! setup the environment for distributed execution
        call qenv%new(1,stream=.true.)
        ! Infinite loop
        last_injection = simple_gettime()
        prev_stacksz   = 0
        iter           = 0
        n_imported     = 0
        n_failed_jobs  = 0
        n_added        = 0
        l_movies_left  = .false.
        l_haschanged   = .false.
        cline_exec     = cline
        call cline_exec%set('fromp',1)
        call cline_exec%set('top',  NMOVS_SET)
        do
            if( file_exists(trim(TERM_STREAM)) )then
                ! termination
                write(logfhandle,'(A)')'>>> TERMINATING PREPROCESS STREAM'
                exit
            endif
            iter = iter + 1
            ! detection of new movies
            call movie_buff%watch( nmovies, movies, max_nmovies=params%nparts*NMOVS_SET )
            ! append movies to processing stack
            if( nmovies >= NMOVS_SET )then
                nsets = floor(real(nmovies) / real(NMOVS_SET))
                cnt   = 0
                do iset = 1,nsets
                    i = (iset-1)*NMOVS_SET+1
                    j = iset*NMOVS_SET
                    call create_movies_set_project(movies(i:j))
                    call qenv%qscripts%add_to_streaming( cline_exec )
                    do imovie = i,j
                        call movie_buff%add2history( movies(imovie) )
                        cnt     = cnt     + 1
                        n_added = n_added + 1 ! global number of movie sets
                    enddo
                    if( cnt == min(params%nparts*NMOVS_SET,nmovies) ) exit
                enddo
                write(logfhandle,'(A,I4,A,A)')'>>> ',cnt,' NEW MOVIES ADDED; ', cast_time_char(simple_gettime())
                l_movies_left = cnt .ne. nmovies
                ! guistats
                call gui_stats%set('movies', 'movies_imported', int2str(movie_buff%n_history), primary=.true.)
                call gui_stats%set_now('movies', 'last_movie_imported')
            else
                l_movies_left = .false.
            endif
            ! submit jobs
            call qenv%qscripts%schedule_streaming( qenv%qdescr, path=output_dir )
            stacksz = qenv%qscripts%get_stacksz()
            ! guistats
            call gui_stats%set('compute', 'compute_in_use', int2str(qenv%get_navail_computing_units()) // '/' // int2str(params%nparts))
            if( stacksz .ne. prev_stacksz )then
                prev_stacksz = stacksz
                write(logfhandle,'(A,I6)')'>>> MOVIES TO PROCESS:                ', stacksz*NMOVS_SET
            endif
            ! fetch completed jobs list
            if( qenv%qscripts%get_done_stacksz() > 0 )then
                call qenv%qscripts%get_stream_done_stack( completed_jobs_clines )
                call update_projects_list( n_imported )
            else
                n_imported = 0 ! newly imported
            endif
            ! failed jobs
            if( qenv%qscripts%get_failed_stacksz() > 0 )then
                call qenv%qscripts%get_stream_fail_stack( failed_jobs_clines, n_fail_iter )
                if( n_fail_iter > 0 )then
                    n_failed_jobs = n_failed_jobs + n_fail_iter
                    do cnt = 1,n_fail_iter
                        call failed_jobs_clines(cnt)%kill
                    enddo
                    deallocate(failed_jobs_clines)
                endif
            endif
            ! project update
            if( n_imported > 0 )then
                n_imported = spproj_glob%os_mic%get_noris()
                write(logfhandle,'(A,I8)')                         '>>> # MOVIES PROCESSED & IMPORTED       : ',n_imported
                write(logfhandle,'(A,I3,A2,I3)')                   '>>> # OF COMPUTING UNITS IN USE/TOTAL   : ',qenv%get_navail_computing_units(),'/ ',params%nparts
                if( n_failed_jobs > 0 ) write(logfhandle,'(A,I8)') '>>> # DESELECTED MICROGRAPHS/FAILED JOBS: ',n_failed_jobs
                ! guistats
                call gui_stats%set('movies',      'movies_processed', int2str(n_imported) // ' (' // int2str(ceiling(100.0 * real(n_imported) / real(movie_buff%n_history))) // '%)', primary=.true.)
                call gui_stats%set('micrographs', 'micrographs',      int2str(n_imported), primary=.true.)
                if( n_failed_jobs > 0 ) call gui_stats%set('micrographs', 'micrographs_rejected', n_failed_jobs, primary=.true.)
                if(spproj_glob%os_mic%isthere("ctfres")) then
                    avg_tmp = spproj_glob%os_mic%get_avg("ctfres")
                    if(spproj_glob%os_mic%get_noris() > 50 .and. avg_tmp > 7.0) then
                        call gui_stats%set('micrographs', 'avg_ctf_resolution', avg_tmp, primary=.true., alert=.true., alerttext='average CTF resolution &
                            &lower than expected for high resolution structure determination', notify=.false.)
                    else
                        call gui_stats%set('micrographs', 'avg_ctf_resolution', avg_tmp, primary=.true., alert=.false., notify=.true., notifytext='tick')
                    end if
                end if
                if(spproj_glob%os_mic%isthere("icefrac")) then
                    avg_tmp = spproj_glob%os_mic%get_avg("icefrac")
                    if(spproj_glob%os_mic%get_noris() > 50 .and. avg_tmp > 1.0) then
                        call gui_stats%set('micrographs', 'avg_ice_score', avg_tmp, primary=.true., alert=.true., alerttext='average ice score &
                            &greater than expected for high resolution structure determination', notify=.false.)
                    else
                        call gui_stats%set('micrographs', 'avg_ice_score', avg_tmp, primary=.true., alert=.false., notify=.true., notifytext='tick')
                    end if
                end if
                if(spproj_glob%os_mic%isthere("astig")) then
                    avg_tmp = spproj_glob%os_mic%get_avg("astig")
                    if(spproj_glob%os_mic%get_noris() > 50 .and. avg_tmp > 0.1) then
                        call gui_stats%set('micrographs', 'avg_astigmatism', avg_tmp, primary=.true., alert=.true., alerttext='average astigmatism &
                            &greater than expected for high resolution structure determination', notify=.false.)
                    else
                        call gui_stats%set('micrographs', 'avg_astigmatism', avg_tmp, primary=.true., alert=.false., notify=.true., notifytext='tick')
                    end if
                end if
                if(spproj_glob%os_mic%isthere('thumb')) then
                    call gui_stats%set('latest', '', trim(adjustl(CWD_GLOB))//'/'//&
                        &trim(adjustl(spproj_glob%os_mic%get_static(spproj_glob%os_mic%get_noris(),'thumb'))), thumbnail=.true.)
                end if
                ! update progress monitor
                call progressfile_update(progress_estimate_preprocess_stream(n_imported, n_added))
                last_injection = simple_gettime()
                l_haschanged = .true.
                n_imported   = spproj_glob%os_mic%get_noris()
                ! always write micrographs snapshot if less than 1000 mics, else every 100
                if( n_imported < 1000 .and. l_haschanged )then
                    call update_user_params(cline)
                    call write_mic_star_and_field
                else if( n_imported > nmic_star + 100 .and. l_haschanged )then
                    call update_user_params(cline)
                    call write_mic_star_and_field
                    nmic_star = n_imported
                endif
            else
                ! wait & write snapshot
                if( .not.l_movies_left )then
                    if( (simple_gettime()-last_injection > INACTIVE_TIME) .and. l_haschanged )then
                        ! write project when inactive...
                        call update_user_params(cline)
                        call write_mic_star_and_field
                        l_haschanged = .false.
                    else
                        ! ...or wait
                        call sleep(WAITTIME)
                    endif
                endif
            endif
            ! guistats
            call gui_stats%write_json
        end do
        ! termination
        call update_user_params(cline)
        call write_mic_star_and_field(write_field=.true.)
        ! final stats
        call gui_stats%hide('compute', 'compute_in_use')
        call gui_stats%write_json
        call gui_stats%kill
        ! cleanup
        call spproj_glob%kill
        call qsys_cleanup
        ! end gracefully
        call simple_end('**** SIMPLE_STREAM_PREPROC NORMAL STOP ****')
        contains

            subroutine write_mic_star_and_field( write_field )
                logical, optional, intent(in) :: write_field
                logical :: l_wfield
                l_wfield = .false.
                if( present(write_field) ) l_wfield = write_field
                call write_migrographs_starfile
                if( l_wfield )then
                    call spproj_glob%write_segment_inside('mic', params%projfile)
                    call spproj_glob%write_non_data_segments(params%projfile)
                endif
            end subroutine write_mic_star_and_field

            !>  write starfile snapshot
            subroutine write_migrographs_starfile
                integer(timer_int_kind)      :: ms0
                real(timer_int_kind)         :: ms_export
                if (spproj_glob%os_mic%get_noris() > 0) then
                    if( DEBUG_HERE ) ms0 = tic()
                    call starproj_stream%stream_export_micrographs(spproj_glob, params%outdir)
                    if( DEBUG_HERE )then
                        ms_export = toc(ms0)
                        print *,'ms_export  : ', ms_export; call flush(6)
                    endif
                end if
            end subroutine write_migrographs_starfile

            ! returns list of completed jobs
            subroutine update_projects_list( nimported )
                integer,                   intent(out) :: nimported
                type(sp_project),          allocatable :: streamspprojs(:)
                character(len=LONGSTRLEN), allocatable :: completed_fnames(:)
                character(len=:),          allocatable :: fname, abs_fname
                logical,                   allocatable :: mics_mask(:)
                integer :: i, n_spprojs, n_old, j, n2import, n_completed, iproj, nmics, imic, cnt
                n_completed = 0
                nimported   = 0
                n_spprojs = size(completed_jobs_clines) ! projects to import
                if( n_spprojs == 0 )return
                n_old = spproj_glob%os_mic%get_noris()       ! previously processed mmovies
                nmics = NMOVS_SET * n_spprojs           ! incoming number of processed movies
                allocate(streamspprojs(n_spprojs), completed_fnames(n_spprojs), mics_mask(nmics))
                ! read all
                do iproj = 1,n_spprojs
                    fname     = trim(output_dir)//trim(completed_jobs_clines(iproj)%get_carg('projfile'))
                    abs_fname = simple_abspath(fname, errmsg='preprocess_stream :: update_projects_list 1')
                    completed_fnames(iproj) = trim(abs_fname)
                    call streamspprojs(iproj)%read_segment('mic', completed_fnames(iproj))
                    cnt = 0
                    do imic = (iproj-1)*NMOVS_SET+1, iproj*NMOVS_SET
                        cnt = cnt + 1
                        mics_mask(imic) = streamspprojs(iproj)%os_mic%get_state(cnt) == 1
                    enddo
                enddo
                n2import      = count(mics_mask)
                n_failed_jobs = n_failed_jobs + (nmics-n2import)
                if( n2import > 0 )then
                    ! reallocate global project
                    n_completed = n_old + n2import
                    nimported   = n2import
                    if( n_old == 0 )then
                        ! first time
                        call spproj_glob%os_mic%new(n2import, is_ptcl=.false.)
                    else
                        call spproj_glob%os_mic%reallocate(n_completed)
                    endif
                    ! actual import
                    imic = 0
                    j    = n_old
                    do iproj = 1,n_spprojs
                        do i = 1,NMOVS_SET
                            imic = imic+1
                            if( mics_mask(imic) )then
                                j   = j + 1
                                ! From now on all MC/CTF metadata use absolute path
                                call update_relative_path_to_absolute(streamspprojs(iproj)%os_mic, i, 'mc_starfile')
                                call update_relative_path_to_absolute(streamspprojs(iproj)%os_mic, i, 'intg')
                                call update_relative_path_to_absolute(streamspprojs(iproj)%os_mic, i, 'thumb')
                                call update_relative_path_to_absolute(streamspprojs(iproj)%os_mic, i, 'mceps')
                                call update_relative_path_to_absolute(streamspprojs(iproj)%os_mic, i, 'ctfdoc')
                                call update_relative_path_to_absolute(streamspprojs(iproj)%os_mic, i, 'ctfjpg')
                                ! transfer info
                                call spproj_glob%os_mic%transfer_ori(j, streamspprojs(iproj)%os_mic, i)
                            endif
                        enddo
                        call streamspprojs(iproj)%write_segment_inside('mic', completed_fnames(iproj))
                        call streamspprojs(iproj)%kill
                    enddo
                endif
                ! finally we move the completed projects to appropriate directory
                do iproj = 1,n_spprojs
                    imic = (iproj-1)*NMOVS_SET+1
                    if( any(mics_mask(imic:imic+NMOVS_SET-1)) )then
                        fname = trim(DIR_STREAM_COMPLETED)//trim(basename(completed_fnames(iproj)))
                        call simple_rename(completed_fnames(iproj), fname)
                    endif
                enddo
                ! cleanup
                call completed_jobs_clines(:)%kill
                deallocate(completed_jobs_clines,streamspprojs,mics_mask,completed_fnames)
            end subroutine update_projects_list

            subroutine update_relative_path_to_absolute(os, i, key)
                class(oris),      intent(inout) :: os
                integer,          intent(in)    :: i
                character(len=*), intent(in)    :: key
                character(len=:), allocatable :: fname
                character(len=LONGSTRLEN)     :: newfname
                if( os%isthere(i,key) )then
                    call os%getter(i,key,fname)
                    if( fname(1:1) == '/' )then
                        ! already absolute path
                        call os%set(i,key,fname)
                    else
                        ! is relative to ./spprojs
                        newfname = simple_abspath(fname(4:len_trim(fname)))
                        call os%set(i,key,newfname)
                    endif
                endif
            end subroutine update_relative_path_to_absolute

            subroutine create_movies_set_project( movie_names )
                character(len=LONGSTRLEN), intent(in) :: movie_names(NMOVS_SET)
                type(sp_project)             :: spproj_here
                type(ctfparams)              :: ctfvars
                character(len=LONGSTRLEN)    :: projname, projfile, xmlfile, xmldir
                character(len=XLONGSTRLEN)   :: cwd, cwd_old
                integer :: imov
                cwd_old = trim(cwd_glob)
                call chdir(output_dir)
                call simple_getcwd(cwd)
                cwd_glob = trim(cwd)
                ! movies set
                movies_set_counter = movies_set_counter + 1
                projname   = int2str_pad(movies_set_counter,params%numlen)
                projfile   = trim(projname)//trim(METADATA_EXT)
                call cline_exec%set('projname', trim(projname))
                call cline_exec%set('projfile', trim(projfile))
                call spproj_here%update_projinfo(cline_exec)
                spproj_here%compenv  = spproj_glob%compenv
                spproj_here%jobproc  = spproj_glob%jobproc
                ! movies parameters
                ctfvars%ctfflag      = CTFFLAG_YES
                ctfvars%smpd         = params%smpd
                ctfvars%cs           = params%cs
                ctfvars%kv           = params%kv
                ctfvars%fraca        = params%fraca
                ctfvars%l_phaseplate = params%phaseplate.eq.'yes'
                call spproj_here%add_movies(movie_names(1:NMOVS_SET), ctfvars, verbose = .false.)
                do imov = 1,NMOVS_SET
                    call spproj_here%os_mic%set(imov, "tiltgrp", 0.0)
                    call spproj_here%os_mic%set(imov, "shiftx",  0.0)
                    call spproj_here%os_mic%set(imov, "shifty",  0.0)
                    call spproj_here%os_mic%set(imov, "flsht",   0.0)
                    if(cline%defined('dir_meta')) then
                        xmldir = cline%get_carg('dir_meta')
                        xmlfile = basename(trim(movie_names(imov)))
                        if(index(xmlfile, '_fractions') > 0) xmlfile = xmlfile(:index(xmlfile, '_fractions') - 1)
                        if(index(xmlfile, '_EER') > 0)       xmlfile = xmlfile(:index(xmlfile, '_EER') - 1)
                        xmlfile = trim(adjustl(xmldir))//'/'//trim(adjustl(xmlfile))//'.xml'
                        call spproj_here%os_mic%set(imov, "meta", trim(adjustl(xmlfile)))
                    end if
                enddo
                call spproj_here%write
                call chdir(cwd_old)
                cwd_glob = trim(cwd_old)
                call spproj_here%kill
            end subroutine create_movies_set_project

            !>  import previous movies and updates global project & variables
            subroutine import_previous_projects
                type(sp_project),          allocatable :: spprojs(:)
                character(len=LONGSTRLEN), allocatable :: completed_fnames(:)
                character(len=:),          allocatable :: fname
                logical,                   allocatable :: mics_mask(:)
                character(len=LONGSTRLEN)              :: moviename
                integer :: n_spprojs, iproj, nmics, imic, jmic, cnt, iostat,id
                ! previously completed projects
                call simple_list_files_regexp(DIR_STREAM_COMPLETED, '\.simple$', completed_fnames)
                if( .not.allocated(completed_fnames) )then
                    return ! nothing was previously completed
                endif
                n_spprojs = size(completed_fnames)
                ! import into global project
                allocate(spprojs(n_spprojs), mics_mask(n_spprojs*NMOVS_SET))
                jmic = 0
                do iproj = 1,n_spprojs
                    call spprojs(iproj)%read_segment('mic', completed_fnames(iproj))
                    do imic = 1,spprojs(iproj)%os_mic%get_noris()
                        jmic = jmic + 1
                        mics_mask(jmic) = spprojs(iproj)%os_mic%get_state(imic) == 1
                    enddo
                enddo
                nmics = count(mics_mask)
                if( nmics ==0 )then
                    ! nothing to import
                    do iproj = 1,n_spprojs
                        call spprojs(iproj)%kill
                        fname = trim(DIR_STREAM_COMPLETED)//trim(completed_fnames(iproj))
                        call del_file(fname)
                    enddo
                    deallocate(spprojs,mics_mask)
                    return
                endif
                call spproj_glob%os_mic%new(nmics, is_ptcl=.false.)
                jmic = 0
                cnt  = 0
                do iproj = 1,n_spprojs
                    do imic = 1,spprojs(iproj)%os_mic%get_noris()
                        cnt = cnt + 1
                        if( mics_mask(cnt) )then
                            jmic = jmic + 1
                            call spproj_glob%os_mic%transfer_ori(jmic, spprojs(iproj)%os_mic, imic)
                        endif
                    enddo
                    call spprojs(iproj)%kill
                enddo
                deallocate(spprojs)
                ! update global movie set counter
                movies_set_counter = 0
                do iproj = 1,n_spprojs
                    fname = basename_safe(completed_fnames(iproj))
                    fname = trim(get_fbody(trim(fname),trim(METADATA_EXT),separator=.false.))
                    call str2int(fname, iostat, id)
                    if( iostat==0 ) movies_set_counter = max(movies_set_counter, id)
                enddo
                ! add previous movies to history
                do imic = 1,spproj_glob%os_mic%get_noris()
                    moviename = spproj_glob%os_mic%get_static(imic,'movie')
                    call movie_buff%add2history(moviename)
                enddo
                ! tidy files
                call simple_rmdir(DIR_STREAM)
                write(logfhandle,'(A,I6,A)')'>>> IMPORTED ',nmics,' PREVIOUSLY PROCESSED MOVIES'
            end subroutine import_previous_projects

    end subroutine exec_stream_preprocess

    subroutine exec_stream_pick_extract( self, cline )
        use simple_moviewatcher, only: moviewatcher
        use simple_stream_chunk, only: micproj_record
        use simple_timer
        class(commander_stream_pick_extract), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        type(make_pickrefs_commander)          :: xmake_pickrefs
        type(parameters)                       :: params
        type(guistats)                         :: gui_stats
        integer,                   parameter   :: INACTIVE_TIME   = 900  ! inactive time triggers writing of project file
        logical,                   parameter   :: DEBUG_HERE      = .false.
        class(cmdline),            allocatable :: completed_jobs_clines(:), failed_jobs_clines(:)
        type(micproj_record),      allocatable :: micproj_records(:)
        type(qsys_env)                         :: qenv
        type(cmdline)                          :: cline_make_pickrefs, cline_pick_extract
        type(moviewatcher)                     :: project_buff
        type(sp_project)                       :: spproj_glob, stream_spproj
        type(starproject_stream)               :: starproj_stream
        character(len=LONGSTRLEN), allocatable :: projects(:)
        character(len=:),          allocatable :: output_dir, output_dir_extract, output_dir_picker
        character(len=LONGSTRLEN)              :: cwd_job, latest_boxfile
        integer                                :: nptcls_limit_for_references ! Limit to # of particles picked, not extracted, to generate refrences
        integer                                :: pick_extract_set_counter    ! Internal counter of projects to be processed
        integer                                :: nmics_sel, nmics_rej, nmics_rejected_glob
        integer                                :: nmics, nprojects, stacksz, prev_stacksz, iter, last_injection, iproj
        integer                                :: cnt, n_imported, n_added, nptcls_glob, n_failed_jobs, n_fail_iter, nmic_star
        logical                                :: l_templates_provided, l_projects_left, l_haschanged, l_multipick, l_extract
        integer(timer_int_kind) :: t0
        real(timer_int_kind)    :: rt_write
        call cline%set('oritype',   'mic')
        call cline%set('mkdir',     'yes')
        if( .not. cline%defined('outdir')     ) call cline%set('outdir',            '')
        if( .not. cline%defined('walltime')   ) call cline%set('walltime',   29.0*60.0) ! 29 minutes
        ! micrograph selection
        if( .not. cline%defined('reject_mics')     ) call cline%set('reject_mics',      'yes')
        if( .not. cline%defined('ctfresthreshold') ) call cline%set('ctfresthreshold',  CTFRES_THRESHOLD_STREAM)
        if( .not. cline%defined('icefracthreshold')) call cline%set('icefracthreshold', ICEFRAC_THRESHOLD_STREAM)
        ! picking
        if( .not. cline%defined('picker')      ) call cline%set('picker',         'new')
        if( .not. cline%defined('lp_pick')     ) call cline%set('lp_pick',         PICK_LP_DEFAULT)
        if( .not. cline%defined('ndev')        ) call cline%set('ndev',              2.)
        if( .not. cline%defined('thres')       ) call cline%set('thres',            24.)
        if( .not. cline%defined('pick_roi')    ) call cline%set('pick_roi',        'no')
        if( .not. cline%defined('backgr_subtr')) call cline%set('backgr_subtr',    'no')
        ! extraction
        if( .not. cline%defined('pcontrast')     ) call cline%set('pcontrast',    'black')
        if( .not. cline%defined('extractfrommov')) call cline%set('extractfrommov',  'no')
        ! write cmdline for GUI
        call cline%writeline(".cline")
        ! sanity check for restart
        if( cline%defined('dir_exec') )then
            if( .not.file_exists(cline%get_carg('dir_exec')) )then
                THROW_HARD('Previous directory does not exists: '//trim(cline%get_carg('dir_exec')))
            endif
        endif
        ! master parameters
        call cline%set('numlen', 5.)
        call cline%set('stream','yes')
        call params%new(cline)
        params_glob%split_mode = 'stream'
        params_glob%ncunits    = params%nparts
        call simple_getcwd(cwd_job)
        call cline%set('mkdir', 'no')
        ! picking
        l_multipick = cline%defined('nmoldiams')
        if( l_multipick )then
            l_extract            = .false.
            l_templates_provided = .false.
            call cline%set('picker','new')
            write(logfhandle,'(A)')'>>> PERFORMING MULTI-DIAMETER PICKING'
        else
            l_extract            = .true.
            l_templates_provided = cline%defined('pickrefs')
            if( cline%defined('picker') )then
                select case(trim(params%picker))
                case('old')
                    if( .not.l_templates_provided ) THROW_HARD('PICKREFS required for picker=old')
                    write(logfhandle,'(A)')'>>> PERFORMING REFERENCE-BASED PICKING'
                case('new')
                    if( l_templates_provided )then
                        if( .not. cline%defined('mskdiam') )then
                            THROW_HARD('New picker requires mask diameter (in A) in conjunction with pickrefs')
                            write(logfhandle,'(A)')'>>> PERFORMING REFERENCE-BASED PICKING'
                        endif
                    else if( .not.cline%defined('moldiam') )then
                        THROW_HARD('MOLDIAM required for picker=new reference-free picking')
                        write(logfhandle,'(A)')'>>> PERFORMING SINGLE DIAMETER PICKING'
                    endif
                case('seg')
                    THROW_HARD('SEG picker not supported yet')
                case DEFAULT
                    THROW_HARD('Unsupported picker')
                end select
            endif
        endif
        ! master project file
        call spproj_glob%read( params%projfile )
        call spproj_glob%update_projinfo(cline)
        if( spproj_glob%os_mic%get_noris() /= 0 ) THROW_HARD('stream_cluster2D must start from an empty project (eg from root project folder)')
        ! movie watcher init
        project_buff = moviewatcher(LONGTIME, trim(params%dir_target)//'/'//trim(DIR_STREAM_COMPLETED), spproj=.true.)
        ! guistats init
        call gui_stats%init
        call gui_stats%set('micrographs', 'micrographs_imported', int2str(0), primary=.true.)
        call gui_stats%set('micrographs', 'micrographs_rejected', int2str(0), primary=.true.)
        call gui_stats%set('micrographs', 'micrographs_picked',   int2str(0), primary=.true.)
        call gui_stats%set('compute',     'compute_in_use',       int2str(0) // '/' // int2str(params%nparts), primary=.true.)
        ! restart
        pick_extract_set_counter = 0
        nptcls_glob              = 0     ! global number of particles
        nmics_rejected_glob      = 0     ! global number of micrographs rejected
        nmic_star                = 0
        if( cline%defined('dir_exec') )then
            call del_file(TERM_STREAM)
            call cline%delete('dir_exec')
            call import_previous_mics( micproj_records )
            nptcls_glob = sum(micproj_records(:)%nptcls)
            nmic_star   = spproj_glob%os_mic%get_noris()
            call gui_stats%set('micrographs', 'micrographs_imported', int2str(nmic_star),              primary=.true.)
            call gui_stats%set('micrographs', 'micrographs_picked',   int2str(nmic_star) // ' (100%)', primary=.true.)
            if(spproj_glob%os_mic%isthere("nptcls")) then
                call gui_stats%set('micrographs', 'avg_number_picks', ceiling(spproj_glob%os_mic%get_avg("nptcls")), primary=.true.)
            end if
            call gui_stats%set('particles', 'total_extracted_particles', nptcls_glob, primary=.true.)
            if(spproj_glob%os_mic%isthere('intg') .and. spproj_glob%os_mic%isthere('boxfile')) then
                latest_boxfile = trim(spproj_glob%os_mic%get_static(spproj_glob%os_mic%get_noris(), 'boxfile'))
                if(file_exists(trim(latest_boxfile))) call gui_stats%set('latest', '', trim(spproj_glob%os_mic%get_static(spproj_glob%os_mic%get_noris(), 'intg')), thumbnail=.true., boxfile=trim(latest_boxfile))
            end if
        endif
        ! output directories
        output_dir = trim(PATH_HERE)//trim(DIR_STREAM)
        call simple_mkdir(output_dir)
        call simple_mkdir(trim(output_dir)//trim(STDERROUT_DIR))
        call simple_mkdir(trim(PATH_HERE)//trim(DIR_STREAM_COMPLETED))
        output_dir_picker  = filepath(trim(PATH_HERE), trim(DIR_PICKER))
        if( l_extract ) output_dir_extract = filepath(trim(PATH_HERE), trim(DIR_EXTRACT))
        call simple_mkdir(output_dir_picker, errmsg="commander_stream :: exec_stream_pick_extract;  ")
        if( l_extract ) call simple_mkdir(output_dir_extract,errmsg="commander_stream :: exec_stream_pick_extract;  ")
        ! initialise progress monitor
        call progressfile_init()
        ! setup the environment for distributed execution
        call qenv%new(1,stream=.true.)
        ! prepares picking references
        if( l_templates_provided )then
            if( trim(params%picker).eq.'old' )then
                cline_make_pickrefs = cline
                call cline_make_pickrefs%set('prg','make_pickrefs')
                call cline_make_pickrefs%set('stream','no')
                call cline_make_pickrefs%delete('ncls')
                call cline_make_pickrefs%delete('mskdiam')
                call xmake_pickrefs%execute_shmem(cline_make_pickrefs)
                call cline%set('pickrefs', '../'//trim(PICKREFS_FBODY)//trim(params%ext))
                write(logfhandle,'(A)')'>>> PREPARED PICKING TEMPLATES'
                call qsys_cleanup
            endif
        endif
        ! command line for execution
        cline_pick_extract = cline
        call cline_pick_extract%set('prg', 'pick_extract')
        call cline_pick_extract%set('dir','../')
        if( l_extract )then
            call cline_pick_extract%set('extract','yes')
        else
            call cline_pick_extract%set('extract','no')
        endif
        ! Infinite loop
        last_injection        = simple_gettime()
        prev_stacksz          = 0
        iter                  = 0
        n_imported            = 0   ! global number of imported processed micrographs
        n_failed_jobs         = 0
        n_added               = 0   ! global number of micrographs added to processing stack
        l_projects_left       = .false.
        l_haschanged          = .false.
        nptcls_limit_for_references = 20000 ! obviously will have to be an input
        do
            if( file_exists(trim(TERM_STREAM)) )then
                ! termination
                write(logfhandle,'(A)')'>>> TERMINATING STREAM PICK_EXTRACT'
                exit
            endif
            iter = iter + 1
            ! detection of new projects
            call project_buff%watch( nprojects, projects, max_nmovies=params%nparts )
            ! append projects to processing stack
            if( nprojects > 0 )then
                cnt   = 0
                nmics = 0
                do iproj = 1, nprojects
                    call create_individual_project(projects(iproj), nmics_sel, nmics_rej)
                    call project_buff%add2history(projects(iproj))
                    if( nmics_sel > 0 )then
                        call qenv%qscripts%add_to_streaming(cline_pick_extract)
                        call qenv%qscripts%schedule_streaming( qenv%qdescr, path=output_dir )
                        cnt   = cnt   + 1
                        nmics = nmics + nmics_sel
                    endif
                    n_added             = n_added + nmics_sel
                    nmics_rejected_glob = nmics_rejected_glob + nmics_rej
                    if( cnt == min(params%nparts, nprojects) ) exit
                enddo
                write(logfhandle,'(A,I4,A,A)')'>>> ',nmics,' NEW MICROGRAPHS ADDED; ',cast_time_char(simple_gettime())
                l_projects_left = cnt .ne. nprojects
                ! guistats
                call gui_stats%set('micrographs', 'micrographs_imported', int2str(project_buff%n_history * NMOVS_SET), primary=.true.)
                call gui_stats%set_now('micrographs', 'last_micrograph_imported')
            else
                l_projects_left = .false.
            endif
            ! submit jobs
            call qenv%qscripts%schedule_streaming( qenv%qdescr, path=output_dir )
            stacksz = qenv%qscripts%get_stacksz()
            ! guistats
            call gui_stats%set('compute', 'compute_in_use', int2str(qenv%get_navail_computing_units()) // '/' // int2str(params%nparts))
            if( stacksz .ne. prev_stacksz )then
                prev_stacksz = stacksz                          ! # of projects
                stacksz      = qenv%qscripts%get_stack_range()  ! # of micrographs
                write(logfhandle,'(A,I6)')'>>> MICROGRAPHS TO PROCESS:                 ', stacksz
            endif
            ! fetch completed jobs list & updates
            if( qenv%qscripts%get_done_stacksz() > 0 )then
                call qenv%qscripts%get_stream_done_stack( completed_jobs_clines )
                call update_projects_list( micproj_records, n_imported )
                call completed_jobs_clines(:)%kill
                deallocate(completed_jobs_clines)
            else
                n_imported = 0 ! newly imported
            endif
            ! failed jobs
            if( qenv%qscripts%get_failed_stacksz() > 0 )then
                call qenv%qscripts%get_stream_fail_stack( failed_jobs_clines, n_fail_iter )
                if( n_fail_iter > 0 )then
                    n_failed_jobs = n_failed_jobs + n_fail_iter
                    call failed_jobs_clines(:)%kill
                    deallocate(failed_jobs_clines)
                endif
            endif
            ! project update
            if( n_imported > 0 )then
                n_imported = spproj_glob%os_mic%get_noris()
                write(logfhandle,'(A,I8)')       '>>> # MICROGRAPS PROCESSED & IMPORTED   : ',n_imported
                if( l_extract )then
                    write(logfhandle,'(A,I8)')   '>>> # PARTICLES EXTRACTED               : ',nptcls_glob
                else
                    write(logfhandle,'(A,I8)')   '>>> # PARTICLES PICKED                  : ',nptcls_glob
                endif
                write(logfhandle,'(A,I3,A2,I3)') '>>> # OF COMPUTING UNITS IN USE/TOTAL   : ',qenv%get_navail_computing_units(),'/ ',params%nparts
                if( n_failed_jobs > 0 ) write(logfhandle,'(A,I8)') '>>> # DESELECTED MICROGRAPHS/FAILED JOBS: ',n_failed_jobs
                ! guistats
                call gui_stats%set('micrographs', 'micrographs_picked', int2str(n_imported) // ' (' // int2str(ceiling(100.0 * real(n_imported) / real(project_buff%n_history * NMOVS_SET))) // '%)', primary=.true.)
                if( n_failed_jobs > 0 ) call gui_stats%set('micrographs', 'micrographs_rejected', n_failed_jobs, primary=.true.)
                if(spproj_glob%os_mic%isthere("nptcls")) then
                    call gui_stats%set('micrographs', 'avg_number_picks', ceiling(spproj_glob%os_mic%get_avg("nptcls")), primary=.true.)
                end if
                call gui_stats%set('particles', 'total_extracted_particles', nptcls_glob, primary=.true.)
                if(spproj_glob%os_mic%isthere('intg') .and. spproj_glob%os_mic%isthere('boxfile')) then
                    latest_boxfile = trim(spproj_glob%os_mic%get_static(spproj_glob%os_mic%get_noris(), 'boxfile'))
                    if(file_exists(trim(latest_boxfile))) call gui_stats%set('latest', '', trim(spproj_glob%os_mic%get_static(spproj_glob%os_mic%get_noris(), 'intg')), thumbnail=.true., boxfile=trim(latest_boxfile))
                end if
                ! update progress monitor
                call progressfile_update(progress_estimate_preprocess_stream(n_imported, n_added))
                ! write project for gui, micrographs field only
                last_injection = simple_gettime()
                l_haschanged = .true.
                ! always write micrographs snapshot if less than 1000 mics, else every 100
                if( n_imported < 1000 .and. l_haschanged )then
                    call update_user_params(cline)
                    call write_migrographs_starfile
                else if( n_imported > nmic_star + 100 .and. l_haschanged )then
                    call update_user_params(cline)
                    call write_migrographs_starfile
                    nmic_star = n_imported
                endif
            else
                ! write snapshot
                if( .not.l_projects_left )then
                    if( (simple_gettime()-last_injection > INACTIVE_TIME) .and. l_haschanged )then
                        ! write project when inactive
                        call write_project
                        call update_user_params(cline)
                        call write_migrographs_starfile
                        l_haschanged = .false.
                    endif
                endif
            endif
            ! multi-picking
            if( l_multipick )then
                if( nptcls_glob > nptcls_limit_for_references )then
                    !!!!!!
                    ! diameter estimation, single picking & clustering happens here
                    !!!!!!
                endif
            endif
            ! guistats
            call gui_stats%write_json
            call sleep(WAITTIME)
        end do
        ! termination
        call write_project
        call update_user_params(cline)
        call write_migrographs_starfile
        ! final stats
        call gui_stats%hide('compute', 'compute_in_use')
        call gui_stats%write_json
        call gui_stats%kill
        ! cleanup
        call spproj_glob%kill
        call qsys_cleanup
        ! end gracefully
        call simple_end('**** SIMPLE_STREAM_PICK_EXTRACT NORMAL STOP ****')
        contains

            !>  write starfile snapshot
            subroutine write_migrographs_starfile
                integer(timer_int_kind)      :: ms0
                real(timer_int_kind)         :: ms_export
                if (spproj_glob%os_mic%get_noris() > 0) then
                    if( DEBUG_HERE ) ms0 = tic()
                    call starproj_stream%stream_export_micrographs(spproj_glob, params%outdir)
                    if( DEBUG_HERE )then
                        ms_export = toc(ms0)
                        print *,'ms_export  : ', ms_export; call flush(6)
                    endif
                end if
            end subroutine write_migrographs_starfile

            subroutine write_project()
                integer, allocatable :: fromps(:)
                integer              :: nptcls,fromp,top,i,iptcl,nmics,imic,micind
                character(len=:), allocatable :: prev_projname
                write(logfhandle,'(A)')'>>> PROJECT UPDATE'
                if( DEBUG_HERE ) t0 = tic()
                ! micrographs
                nmics = spproj_glob%os_mic%get_noris()
                call spproj_glob%write_segment_inside('mic', params%projfile)
                if( l_extract )then
                    ! stacks
                    allocate(fromps(nmics), source=0)
                    call spproj_glob%os_stk%new(nmics, is_ptcl=.false.)
                    nptcls        = 0
                    fromp         = 0
                    top           = 0
                    prev_projname = ''
                    do imic = 1,nmics
                        if( trim(micproj_records(imic)%projname) /= trim(prev_projname) )then
                            call stream_spproj%kill
                            call stream_spproj%read_segment('stk', micproj_records(imic)%projname)
                            prev_projname = trim(micproj_records(imic)%projname)
                        endif
                        micind = micproj_records(imic)%micind
                        fromps(imic) = nint(stream_spproj%os_stk%get(micind,'fromp')) ! fromp from individual project
                        fromp        = nptcls + 1
                        nptcls       = nptcls + micproj_records(imic)%nptcls
                        top          = nptcls
                        call spproj_glob%os_stk%transfer_ori(imic, stream_spproj%os_stk, micind)
                        call spproj_glob%os_stk%set(imic, 'fromp',real(fromp))
                        call spproj_glob%os_stk%set(imic, 'top',  real(top))
                    enddo
                    call spproj_glob%write_segment_inside('stk', params%projfile)
                    call spproj_glob%os_stk%kill
                    ! particles
                    call spproj_glob%os_ptcl2D%new(nptcls, is_ptcl=.true.)
                    iptcl         = 0
                    prev_projname = ''
                    do imic = 1,nmics
                        if( trim(micproj_records(imic)%projname) /= prev_projname )then
                            call stream_spproj%kill
                            call stream_spproj%read_segment('ptcl2D', micproj_records(imic)%projname)
                            prev_projname = trim(micproj_records(imic)%projname)
                        endif
                        fromp = fromps(imic)
                        top   = fromp + micproj_records(imic)%nptcls - 1
                        do i = fromp,top
                            iptcl = iptcl + 1
                            call spproj_glob%os_ptcl2D%transfer_ori(iptcl, stream_spproj%os_ptcl2D, i)
                            call spproj_glob%os_ptcl2D%set_stkind(iptcl, imic)
                        enddo
                    enddo
                    call stream_spproj%kill
                    write(logfhandle,'(A,I8)')'>>> # PARTICLES EXTRACTED:          ',spproj_glob%os_ptcl2D%get_noris()
                    call spproj_glob%write_segment_inside('ptcl2D', params%projfile)
                    spproj_glob%os_ptcl3D = spproj_glob%os_ptcl2D
                    call spproj_glob%os_ptcl2D%kill
                    call spproj_glob%os_ptcl3D%delete_2Dclustering
                    call spproj_glob%write_segment_inside('ptcl3D', params%projfile)
                    call spproj_glob%os_ptcl3D%kill
                endif
                call spproj_glob%write_non_data_segments(params%projfile)
                ! benchmark
                if( DEBUG_HERE )then
                    rt_write = toc(t0)
                    print *,'rt_write  : ', rt_write; call flush(6)
                endif
            end subroutine write_project

            ! updates global project, returns records of processed micrographs
            subroutine update_projects_list( records, nimported )
                type(micproj_record), allocatable, intent(inout) :: records(:)
                integer,                           intent(inout) :: nimported
                type(sp_project),     allocatable :: spprojs(:)
                type(micproj_record), allocatable :: old_records(:)
                character(len=:),     allocatable :: fname, abs_fname, new_fname
                integer :: n_spprojs, n_old, j, nprev_imports, n_completed, nptcls, nmics, imic
                n_completed = 0
                nimported   = 0
                ! previously imported
                n_old = 0 ! on first import
                if( allocated(records) ) n_old = size(records)
                ! projects to import
                n_spprojs = size(completed_jobs_clines)
                if( n_spprojs == 0 )return
                allocate(spprojs(n_spprojs))
                ! because pick_extract purges state=0 and nptcls=0 mics,
                ! all mics can be assumed associated with particles
                nmics = 0
                do iproj = 1,n_spprojs
                    fname = trim(output_dir)//trim(completed_jobs_clines(iproj)%get_carg('projfile'))
                    call spprojs(iproj)%read_segment('mic', fname)
                    nmics = nmics + spprojs(iproj)%os_mic%get_noris()
                enddo
                if( nmics == 0 )then
                    ! nothing to import
                else
                    ! import micrographs
                    n_completed   = n_old + nmics
                    nimported     = nmics
                    nprev_imports = spproj_glob%os_mic%get_noris()
                    ! reallocate global project
                    if( nprev_imports == 0 )then
                        call spproj_glob%os_mic%new(nmics, is_ptcl=.false.) ! first import
                        allocate(micproj_records(nmics))
                    else
                        call spproj_glob%os_mic%reallocate(n_completed)
                        call move_alloc(micproj_records, old_records)
                        allocate(micproj_records(n_completed))
                        if( n_old > 0 ) micproj_records(1:n_old) = old_records(:)
                        deallocate(old_records)
                    endif
                    ! update records and global project
                    j = n_old
                    do iproj = 1,n_spprojs
                        ! move project to appropriate directory
                        fname     = trim(output_dir)//trim(completed_jobs_clines(iproj)%get_carg('projfile'))
                        new_fname = trim(DIR_STREAM_COMPLETED)//trim(completed_jobs_clines(iproj)%get_carg('projfile'))
                        call simple_rename(fname, new_fname)
                        abs_fname = simple_abspath(new_fname, errmsg='stream pick_extract :: update_projects_list 1')
                        ! records & project
                        do imic = 1,spprojs(iproj)%os_mic%get_noris()
                            j = j + 1
                            nptcls      = nint(spprojs(iproj)%os_mic%get(imic,'nptcls'))
                            nptcls_glob = nptcls_glob + nptcls ! global update
                            micproj_records(j)%projname = trim(abs_fname)
                            micproj_records(j)%micind   = imic
                            micproj_records(j)%nptcls   = nptcls
                            call spproj_glob%os_mic%transfer_ori(j, spprojs(iproj)%os_mic, imic)
                        enddo
                    enddo
                endif
                ! cleanup
                do iproj = 1,n_spprojs
                    call spprojs(iproj)%kill
                enddo
                deallocate(spprojs)
            end subroutine update_projects_list

            ! prepares project for processing and performs micrograph selection
            subroutine create_individual_project( project_fname, nselected, nrejected )
                character(len=*), intent(in)  :: project_fname
                integer,          intent(out) :: nselected, nrejected
                type(sp_project)              :: tmp_proj, spproj_here
                integer,         allocatable  :: states(:)
                character(len=STDLEN)         :: proj_fname, projname, projfile
                character(len=LONGSTRLEN)     :: path
                integer :: imic, nmics, cnt
                nselected = 0
                nrejected = 0
                call tmp_proj%read_segment('mic', project_fname)
                allocate(states(tmp_proj%os_mic%get_noris()), source=nint(tmp_proj%os_mic%get_all('state')))
                nmics     = count(states==1)
                nselected = nmics
                nrejected = tmp_proj%os_mic%get_noris() - nselected
                if( nmics == 0 )then
                    call tmp_proj%kill
                    return ! nothing to add to queue
                endif
                ! micrograph rejection
                if( trim(params%reject_mics).eq.'yes' )then
                    do imic = 1,tmp_proj%os_mic%get_noris()
                        if( states(imic) == 0 ) cycle
                        if( tmp_proj%os_mic%isthere(imic, 'ctfres') )then
                            if( tmp_proj%os_mic%get(imic,'ctfres') > (params%ctfresthreshold-0.001) ) states(imic) = 0
                        end if
                        if( states(imic) == 0 ) cycle
                        if( tmp_proj%os_mic%isthere(imic, 'icefrac') )then
                            if( tmp_proj%os_mic%get(imic,'icefrac') > (params%icefracthreshold-0.001) ) states(imic) = 0
                        end if
                    enddo
                    nmics     = count(states==1)
                    nselected = nmics
                    nrejected = tmp_proj%os_mic%get_noris() - nselected
                    if( nselected == 0 )then
                        call tmp_proj%kill
                        return ! nothing to add to queue
                    endif
                endif
                ! as per update_projinfo
                path       = trim(cwd_glob)//'/'//trim(output_dir)
                proj_fname = basename(project_fname)
                projname   = trim(get_fbody(trim(proj_fname), trim(METADATA_EXT), separator=.false.))
                projfile   = trim(projname)//trim(METADATA_EXT)
                call spproj_here%projinfo%new(1, is_ptcl=.false.)
                call spproj_here%projinfo%set(1,'projname', trim(projname))
                call spproj_here%projinfo%set(1,'projfile', trim(projfile))
                call spproj_here%projinfo%set(1,'cwd',      trim(path))
                ! from current global project
                spproj_here%compenv = spproj_glob%compenv
                spproj_here%jobproc = spproj_glob%jobproc
                ! import micrographs & updates path to files
                call spproj_here%os_mic%new(nmics,is_ptcl=.false.)
                cnt = 0
                do imic = 1,tmp_proj%os_mic%get_noris()
                    if( states(imic) == 0 ) cycle
                    cnt = cnt+1
                    call spproj_here%os_mic%transfer_ori(cnt, tmp_proj%os_mic, imic)
                enddo
                nselected = cnt
                nrejected = tmp_proj%os_mic%get_noris() - nselected
                ! update for execution
                pick_extract_set_counter = pick_extract_set_counter + 1
                projname = int2str_pad(pick_extract_set_counter,params%numlen)
                projfile = trim(projname)//trim(METADATA_EXT)
                call cline_pick_extract%set('projname', trim(projname))
                call cline_pick_extract%set('projfile', trim(projfile))
                call cline_pick_extract%set('fromp',    1)
                call cline_pick_extract%set('top',      nselected)
                call spproj_here%write(trim(path)//'/'//trim(projfile))
                call spproj_here%kill
                call tmp_proj%kill
            end subroutine create_individual_project

            !>  import previous run to the current project and reselect micrographs
            subroutine import_previous_mics( records )
                type(micproj_record),      allocatable, intent(inout) :: records(:)
                type(sp_project),          allocatable :: spprojs(:)
                character(len=LONGSTRLEN), allocatable :: completed_fnames(:)
                character(len=:),          allocatable :: fname
                logical,                   allocatable :: mics_mask(:)
                integer :: n_spprojs, iproj, nmics, imic, jmic, iostat,id, nsel_mics, irec
                ! previously completed projects
                call simple_list_files_regexp(DIR_STREAM_COMPLETED, '\.simple$', completed_fnames)
                if( .not.allocated(completed_fnames) )then
                    return ! nothing was previously completed
                endif
                n_spprojs = size(completed_fnames)
                allocate(spprojs(n_spprojs))
                ! read projects micrographs
                nmics = 0
                do iproj = 1,n_spprojs
                    call spprojs(iproj)%read_segment('mic', completed_fnames(iproj))
                    nmics = nmics + spprojs(iproj)%os_mic%get_noris()
                enddo
                ! selection, because pick_extract purges state=0 and nptcls=0 mics,
                ! all mics can be assumed associated with particles
                allocate(mics_mask(nmics))
                jmic = 0
                do iproj = 1,n_spprojs
                    do imic = 1, spprojs(iproj)%os_mic%get_noris()
                        jmic            = jmic+1
                        mics_mask(jmic) = .true.
                        if( spprojs(iproj)%os_mic%isthere(imic, 'ctfres') )then
                            if( spprojs(iproj)%os_mic%get(imic,'ctfres') > (params%ctfresthreshold-0.001) ) mics_mask(jmic) = .false.
                        end if
                        if( .not.mics_mask(jmic) ) cycle
                        if( spprojs(iproj)%os_mic%isthere(imic, 'icefrac') )then
                            if( spprojs(iproj)%os_mic%get(imic,'icefrac') > (params%icefracthreshold-0.001) ) mics_mask(jmic) = .false.
                        end if
                    enddo
                enddo
                nsel_mics = count(mics_mask)
                if( nsel_mics == 0 )then
                    ! nothing to import
                    do iproj = 1,n_spprojs
                        call spprojs(iproj)%kill
                        fname = trim(DIR_STREAM_COMPLETED)//trim(completed_fnames(iproj))
                        call del_file(fname)
                    enddo
                    deallocate(spprojs)
                    nmics_rejected_glob = nmics
                    return
                endif
                ! updates global records & project
                allocate(records(nsel_mics))
                call spproj_glob%os_mic%new(nsel_mics, is_ptcl=.false.)
                irec = 0
                jmic = 0
                do iproj = 1,n_spprojs
                    do imic = 1, spprojs(iproj)%os_mic%get_noris()
                        jmic = jmic+1
                        if( mics_mask(jmic) )then
                            irec = irec + 1
                            records(irec)%projname = trim(completed_fnames(iproj))
                            records(irec)%micind   = imic
                            records(irec)%nptcls   = nint(spprojs(iproj)%os_mic%get(imic, 'nptcls'))
                            call spproj_glob%os_mic%transfer_ori(irec, spprojs(iproj)%os_mic, imic)
                        endif
                    enddo
                    call spprojs(iproj)%kill
                enddo
                ! update global set counter
                pick_extract_set_counter = 0
                do iproj = 1,n_spprojs
                    fname = basename_safe(completed_fnames(iproj))
                    fname = trim(get_fbody(trim(fname),trim(METADATA_EXT),separator=.false.))
                    call str2int(fname, iostat, id)
                    if( iostat==0 ) pick_extract_set_counter = max(pick_extract_set_counter, id)
                enddo
                nmics_rejected_glob = nmics - nsel_mics
                ! add previous projects to history
                do iproj = 1,n_spprojs
                    call project_buff%add2history(completed_fnames(iproj))
                enddo
                ! tidy files
                call simple_rmdir(DIR_STREAM)
                write(logfhandle,'(A,I6,A)')'>>> IMPORTED ',nsel_mics,' PREVIOUSLY PROCESSED MICROGRAPHS'
            end subroutine import_previous_mics

    end subroutine exec_stream_pick_extract

    subroutine exec_stream_assign_optics( self, cline )
        use simple_moviewatcher, only: moviewatcher
        use simple_timer
        class(commander_stream_assign_optics), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        type(parameters)                       :: params
        type(guistats)                         :: gui_stats
        type(moviewatcher)                     :: project_buff
        type(sp_project)                       :: spproj, spproj_part
        type(starproject_stream)               :: starproj_stream
        character(len=LONGSTRLEN), allocatable :: projects(:)
        integer                                :: nprojects, iproj, iori, new_oris, nimported
        call cline%set('mkdir', 'yes')
        if( .not. cline%defined('dir_target') ) THROW_HARD('DIR_TARGET must be defined!')
        if( .not. cline%defined('outdir')     ) call cline%set('outdir', '')
        ! write cmdline for GUI
        call cline%writeline(".cline")
        ! sanity check for restart
        if( cline%defined('dir_exec') )then
            if( .not.file_exists(cline%get_carg('dir_exec')) )then
                THROW_HARD('Previous directory does not exist: '//trim(cline%get_carg('dir_exec')))
            endif
            call del_file(TERM_STREAM)
        endif
        ! master parameters
        call params%new(cline)
        ! master project file
        call spproj%read( params%projfile )
        call spproj%update_projinfo(cline)
        if( spproj%os_mic%get_noris() /= 0 ) call spproj%os_mic%new(0, .false.)
        ! movie watcher init
        project_buff = moviewatcher(LONGTIME, trim(params%dir_target)//'/'//trim(DIR_STREAM_COMPLETED), spproj=.true.)
        ! initialise progress monitor
        call progressfile_init()
        ! guistats init
        call gui_stats%init
        call gui_stats%set('micrographs', 'micrographs_imported',  int2str(0), primary=.true.)
        call gui_stats%set('groups',      'optics_group_assigned', int2str(0), primary=.true.)
        ! Infinite loop
        nimported = 0
        do
            if( file_exists(trim(TERM_STREAM)) )then
                ! termination
                write(logfhandle,'(A)')'>>> TERMINATING STREAM ASSIGN OPTICS'
                exit
            endif
            ! detection of new projects
            call project_buff%watch( nprojects, projects, max_nmovies=50 )
            ! append projects to processing stack
            if( nprojects > 0 )then
                nimported = spproj%os_mic%get_noris()
                if(nimported > 0) then
                    new_oris  =  nimported + nprojects * NMOVS_SET
                    call spproj%os_mic%reallocate(new_oris)
                else
                    new_oris = nprojects * NMOVS_SET
                    call spproj%os_mic%new(new_oris, .false.)
                end if
                do iproj = 1, nprojects
                    call project_buff%add2history(projects(iproj))
                    call spproj_part%read(trim(projects(iproj)))
                    do iori = 1, NMOVS_SET
                        nimported = nimported + 1
                        call spproj%os_mic%transfer_ori(nimported, spproj_part%os_mic, iori)
                    end do
                    call spproj_part%kill()
                enddo
                write(logfhandle,'(A,I4,A,A)')'>>> ' , nprojects * NMOVS_SET, ' NEW MICROGRAPHS IMPORTED; ',cast_time_char(simple_gettime())
                call starproj_stream%stream_export_optics(spproj, params%outdir)
                ! guistats
                call gui_stats%set('micrographs', 'micrographs_imported', int2str(0), primary=.true.)
                call gui_stats%set('groups', 'optics_group_assigned', spproj%os_optics%get_noris(), primary=.true.)
            else
                call sleep(WAITTIME) ! may want to increase as 3s default
            endif
            call update_user_params(cline)
            if(params_glob%updated .eq. 'yes') then
                call starproj_stream%stream_export_optics(spproj, params%outdir)
                ! guistats
                call gui_stats%set('groups', 'optics_group_assigned', spproj%os_optics%get_noris(), primary=.true.)
                params_glob%updated = 'no'
            end if
            call gui_stats%write_json
        end do
        if(allocated(projects)) deallocate(projects)
        call gui_stats%write_json
        call gui_stats%kill
        ! cleanup
        call spproj%kill
        ! end gracefully
        call simple_end('**** SIMPLE_STREAM_ASSIGN_OPTICS NORMAL STOP ****')
    end subroutine exec_stream_assign_optics

    subroutine exec_stream_cluster2D( self, cline )
        use simple_moviewatcher, only: moviewatcher
        use simple_stream_chunk, only: micproj_record
        use simple_commander_cluster2D_stream_dev
        use simple_timer
        class(commander_stream_cluster2D), intent(inout) :: self
        class(cmdline),                    intent(inout) :: cline
        character(len=STDLEN),     parameter   :: micspproj_fname = './streamdata.simple'
        type(parameters)                       :: params
        type(guistats)                         :: gui_stats
        integer,                   parameter   :: INACTIVE_TIME   = 900  ! inactive time trigger for writing project file
        logical,                   parameter   :: DEBUG_HERE      = .false.
        type(micproj_record),      allocatable :: micproj_records(:)
        type(moviewatcher)                     :: project_buff
        type(sp_project)                       :: spproj_glob
        character(len=LONGSTRLEN), allocatable :: projects(:)
        character(len=LONGSTRLEN)              :: cwd_job
        integer                                :: nmics_rejected_glob
        integer                                :: nchunks_imported_glob, nchunks_imported, nprojects, iter, last_injection
        integer                                :: n_imported, n_added, nptcls_glob, n_failed_jobs, ncls_in, nmic_star
        logical                                :: l_haschanged, l_nchunks_maxed
        call cline%set('oritype',      'mic')
        call cline%set('mkdir',        'yes')
        call cline%set('autoscale',    'yes')
        call cline%set('reject_mics',  'no')
        call cline%set('kweight_chunk','default')
        call cline%set('kweight_pool', 'default')
        call cline%set('prune',        'no')
        call cline%set('nonuniform',   'no')
        call cline%set('ml_reg',       'no')
        call cline%set('wiener',       'full')
        if( .not. cline%defined('dir_target')   ) THROW_HARD('DIR_TARGET must be defined!')
        if( .not. cline%defined('walltime')     ) call cline%set('walltime',   29.0*60.0) ! 29 minutes
        if( .not. cline%defined('lpthres')      ) call cline%set('lpthres',       30.0)
        if( .not. cline%defined('ndev')         ) call cline%set('ndev', CLS_REJECT_STD)
        if( .not. cline%defined('reject_cls')   ) call cline%set('reject_cls',   'yes')
        if( .not. cline%defined('objfun')       ) call cline%set('objfun',    'euclid')
        if( .not. cline%defined('rnd_cls_init') ) call cline%set('rnd_cls_init',  'no')
        if( .not. cline%defined('remove_chunks')) call cline%set('remove_chunks','yes')
        ! write cmdline for GUI
        call cline%writeline(".cline")
        ! sanity check for restart
        if( cline%defined('dir_exec') )then
            if( .not.file_exists(cline%get_carg('dir_exec')) )then
                THROW_HARD('Previous directory does not exists: '//trim(cline%get_carg('dir_exec')))
            endif
        endif
        ncls_in = 0
        if( cline%defined('ncls') )then
            ! to circumvent parameters class stringency, restored after params%new
            ncls_in = nint(cline%get_rarg('ncls'))
            call cline%delete('ncls')
        endif
        ! master parameters
        call cline%set('numlen', 5.)
        call cline%set('stream','yes')
        call params%new(cline)
        call simple_getcwd(cwd_job)
        call cline%set('mkdir', 'no')
        if( ncls_in > 0 ) call cline%set('ncls', real(ncls_in))
        ! limit to # of chunks
        if( .not. cline%defined('maxnchunks') .or. params_glob%maxnchunks < 1 )then
            params_glob%maxnchunks = huge(params_glob%maxnchunks)
        endif
        call cline%delete('maxnchunks')
        ! restart
        if( cline%defined('dir_exec') )then
            call cline%delete('dir_exec')
            call del_file(micspproj_fname)
            call cleanup_root_folder
        endif
        ! Only required for compatibility with old version (chunk)
        params%nthr2D      = params%nthr
        params_glob%nthr2D = params%nthr
        ! initialise progress monitor
        call progressfile_init()
        ! master project file
        call spproj_glob%read( params%projfile )
        call spproj_glob%update_projinfo(cline)
        if( spproj_glob%os_mic%get_noris() /= 0 ) THROW_HARD('stream_cluster2D must start from an empty project (eg from root project folder)')
        ! movie watcher init
        project_buff = moviewatcher(LONGTIME, trim(params%dir_target)//'/'//trim(DIR_STREAM_COMPLETED), spproj=.true.)
        ! Infinite loop
        nptcls_glob           = 0   ! global number of particles
        nchunks_imported_glob = 0   ! global number of completed chunks
        last_injection        = simple_gettime()
        nprojects             = 0
        iter                  = 0
        n_imported            = 0   ! global number of imported processed micrographs
        n_failed_jobs         = 0
        nmic_star             = 0
        nmics_rejected_glob   = 0   ! global number of micrographs rejected
        l_haschanged          = .false.
        l_nchunks_maxed       = .false.
        ! guistats init
        call gui_stats%init
        do
            if( file_exists(trim(TERM_STREAM)) )then
                ! termination
                write(logfhandle,'(A)')'>>> TERMINATING PREPROCESS STREAM'
                exit
            endif
            iter = iter + 1
            ! detection of new projects
            if( l_nchunks_maxed )then
                call project_buff%kill
                nprojects = 0
            else
                ! watch & update global records
                call project_buff%watch(nprojects, projects, max_nmovies=5*params%nparts)
            endif
            ! update global records
            if( nprojects > 0 )then
                call update_records_with_project(projects, n_imported )
                call project_buff%add2history(projects)
            endif
            ! project update
            if( nprojects > 0 )then
                n_imported = size(micproj_records)
                write(logfhandle,'(A,I8)')       '>>> # MICROGRAPHS IMPORTED : ',n_imported
                write(logfhandle,'(A,I8)')       '>>> # PARTICLES IMPORTED   : ',nptcls_glob
                ! guistats
                ! call gui_stats%set('micrographs', 'movies', int2str(n_imported) // '/' // int2str(stacksz + spproj_glob%os_mic%get_noris()), primary=.true.)
                call gui_stats%set('micrographs', 'ptcls', nptcls_glob, primary=.true.)
                ! update progress monitor
                call progressfile_update(progress_estimate_preprocess_stream(n_imported, n_added))
                ! write project for gui, micrographs field only
                last_injection = simple_gettime()
                ! guistats
                ! call gui_stats%set_now('micrographs', 'last_new_movie')
                ! if(spproj_glob%os_mic%isthere('thumb')) then
                !     call gui_stats%set('micrographs', 'latest_micrograph', trim(adjustl(cwd_job)) // '/' // trim(adjustl(spproj_glob%os_mic%get_static(spproj_glob%os_mic%get_noris(), 'thumb'))), thumbnail=.true.)
                ! end if
                l_haschanged = .true.
                ! remove this?
                if( n_imported < 1000 .and. l_haschanged )then
                    call update_user_params(cline)
                else if( n_imported > nmic_star + 100 .and. l_haschanged )then
                    call update_user_params(cline)
                    nmic_star = n_imported
                endif
            else
                if( (simple_gettime()-last_injection > INACTIVE_TIME) .and. l_haschanged )then
                    call update_user_params_dev(cline)
                    l_haschanged = .false.
                endif
            endif
            ! 2D classification section
            call update_user_params_dev(cline)
            call update_chunks_dev
            call update_pool_status_dev
            call update_pool_dev
            call update_user_params_dev(cline)
            call reject_from_pool_dev
            call reject_from_pool_user_dev
            if( l_nchunks_maxed )then
                ! # of chunks is above desired threshold
                if( is_pool_available_dev() ) exit
            else
                call import_chunks_into_pool_dev(nchunks_imported)
                nchunks_imported_glob = nchunks_imported_glob + nchunks_imported
                l_nchunks_maxed       = nchunks_imported_glob >= params_glob%maxnchunks
                call classify_pool_dev
                call classify_new_chunks_dev(micproj_records)
            endif
            call sleep(WAITTIME)
            ! guistats
            if(file_exists(POOLSTATS_FILE)) call gui_stats%merge(POOLSTATS_FILE)
            call gui_stats%write_json
        end do
        ! termination
        call terminate_stream2D_dev
        call update_user_params(cline)
        ! final stats
        if(file_exists(POOLSTATS_FILE)) call gui_stats%merge(POOLSTATS_FILE, delete = .true.)
        call gui_stats%hide('micrographs', 'compute')
        call gui_stats%write_json
        call gui_stats%kill
        ! cleanup
        call spproj_glob%kill
        call qsys_cleanup
        ! end gracefully
        call simple_end('**** SIMPLE_STREAM_CLUSTER2D NORMAL STOP ****')
        contains

            ! updates global records
            subroutine update_records_with_project( projectnames, n_imported )
                character(len=LONGSTRLEN), allocatable, intent(in)  :: projectnames(:)
                integer,                                intent(out) :: n_imported
                type(sp_project),     allocatable :: spprojs(:)
                type(micproj_record), allocatable :: old_records(:)
                character(len=:),     allocatable :: fname, abs_fname
                integer :: iproj, n_spprojs, n_old, irec, n_completed, nptcls, nmics, imic, n_ptcls
                n_imported = 0
                n_ptcls    = 0
                if( .not.allocated(projectnames) ) return
                n_spprojs  = size(projectnames)
                if( n_spprojs == 0 )return
                n_old = 0 ! on first import
                if( allocated(micproj_records) ) n_old = size(micproj_records)
                allocate(spprojs(n_spprojs))
                ! because pick_extract purges state=0 and nptcls=0 mics,
                ! all mics can be assumed associated with particles
                nmics = 0
                do iproj = 1,n_spprojs
                    call spprojs(iproj)%read_segment('mic', trim(projectnames(iproj)))
                    nmics = nmics + spprojs(iproj)%os_mic%get_noris()
                enddo
                ! Updates global parameters once and init 2D
                if( n_old == 0 )then
                    params%smpd      = spprojs(1)%os_mic%get(1,'smpd')
                    params_glob%smpd = params%smpd
                    call spprojs(1)%read_segment('stk', trim(projectnames(1)))
                    params%box      = nint(spprojs(1)%os_stk%get(1,'box'))
                    params_glob%box = params%box
                    call init_cluster2D_stream_dev(cline, spproj_glob, params%box, micspproj_fname)
                    call cline%delete('ncls')
                endif
                ! import micrographs
                n_completed = n_old + nmics
                n_imported  = nmics
                ! reallocate records
                if( n_old == 0 )then
                    allocate(micproj_records(nmics))
                else
                    call move_alloc(micproj_records, old_records)
                    allocate(micproj_records(n_completed))
                    micproj_records(1:n_old) = old_records(:)
                    deallocate(old_records)
                endif
                ! update global records and some global variables
                irec = n_old
                do iproj = 1,n_spprojs
                    do imic = 1,spprojs(iproj)%os_mic%get_noris()
                        irec      = irec + 1
                        nptcls    = nint(spprojs(iproj)%os_mic%get(imic,'nptcls'))
                        n_ptcls   = n_ptcls + nptcls ! global update
                        fname     = trim(projectnames(iproj))
                        abs_fname = simple_abspath(fname, errmsg='stream_cluster2D :: update_projects_list 1')
                        micproj_records(irec)%projname   = trim(abs_fname)
                        micproj_records(irec)%micind     = imic
                        micproj_records(irec)%nptcls     = nptcls
                        micproj_records(irec)%nptcls_sel = nptcls
                        micproj_records(irec)%included   = .false.
                    enddo
                enddo
                nptcls_glob = nptcls_glob + n_ptcls ! global update
                ! cleanup
                do iproj = 1,n_spprojs
                    call spprojs(iproj)%kill
                enddo
                deallocate(spprojs)
            end subroutine update_records_with_project

    end subroutine exec_stream_cluster2D

    ! PRIVATE UTILITIES

    !> updates current parameters with user input
    subroutine update_user_params( cline_here )
        type(cmdline), intent(inout) :: cline_here
        type(oris) :: os
        real       :: tilt_thres, beamtilt
        call os%new(1, is_ptcl=.false.)
        if( file_exists(USER_PARAMS) )then
            call os%read(USER_PARAMS)
            if( os%isthere(1,'tilt_thres') ) then
                tilt_thres = os%get(1,'tilt_thres')
                if( abs(tilt_thres-params_glob%tilt_thres) > 0.001) then
                     if(tilt_thres < 0.01)then
                         write(logfhandle,'(A,F8.2)')'>>> OPTICS TILT_THRES TOO LOW: ',tilt_thres
                     else if(tilt_thres > 1) then
                         write(logfhandle,'(A,F8.2)')'>>> OPTICS TILT_THRES TOO HIGH: ',tilt_thres
                     else
                         params_glob%tilt_thres = tilt_thres
                         params_glob%updated    = 'yes'
                         call cline_here%set('tilt_thres', params_glob%tilt_thres)
                         write(logfhandle,'(A,F8.2)')'>>> OPTICS TILT_THRES UPDATED TO: ',tilt_thres
                     endif
                endif
            endif
            if( os%isthere(1,'beamtilt') ) then
                beamtilt = os%get(1,'beamtilt')
                if( beamtilt .eq. 1.0 ) then
                    params_glob%beamtilt = 'yes'
                    params_glob%updated  = 'yes'
                    call cline_here%set('beamtilt', params_glob%beamtilt)
                    write(logfhandle,'(A)')'>>> OPTICS ASSIGNMENT UDPATED TO USE BEAMTILT'
                else if( beamtilt .eq. 0.0 ) then
                    params_glob%beamtilt = 'no'
                    params_glob%updated  = 'yes'
                    call cline_here%set('beamtilt', params_glob%beamtilt)
                    write(logfhandle,'(A)')'>>> OPTICS ASSIGNMENT UDPATED TO IGNORE BEAMTILT'   
                else
                    write(logfhandle,'(A,F8.2)')'>>> OPTICS UPDATE INVALID BEAMTILT VALUE: ',beamtilt
                endif
            endif
            call del_file(USER_PARAMS)
        endif
        call os%kill
    end subroutine update_user_params

end module simple_commander_stream
