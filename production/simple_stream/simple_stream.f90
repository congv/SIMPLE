! executes the shared-memory parallelised programs in SIMPLE_STREAM
program simple_stream
include 'simple_lib.f08'
use simple_user_interface, only: make_user_interface,list_stream_prgs_in_ui
use simple_cmdline,        only: cmdline, cmdline_err
use simple_exec_helpers
use simple_commander_stream

implicit none
#include "simple_local_flags.inc"

! PROGRAMS
type(commander_stream_preprocess)           :: xpreprocess
type(commander_multipick_cluster2D)         :: xmultipick_cluster2D
type(commander_pick_extract_cluster2D)      :: xpick_extract_cluster2D

! OTHER DECLARATIONS
character(len=STDLEN)                       :: xarg, prg, entire_line
type(cmdline)                               :: cline
integer                                     :: cmdstat, cmdlen, pos
integer(timer_int_kind)                     :: t0
real(timer_int_kind)                        :: rt_exec

! start timer
t0 = tic()
! parse command-line
call get_command_argument(1, xarg, cmdlen, cmdstat)
call get_command(entire_line)
pos = index(xarg, '=') ! position of '='
call cmdline_err( cmdstat, cmdlen, xarg, pos )
prg = xarg(pos+1:)     ! this is the program name
! make UI
call make_user_interface
if( str_has_substr(entire_line, 'prg=list') )then
    call list_stream_prgs_in_ui
    stop
endif
! parse command line into cline object
call cline%parse
! generate script for queue submission?
call script_exec(cline, trim(prg), 'simple_stream')

select case(trim(prg))
    case( 'preproc' )
        call xpreprocess%execute(cline)
    case( 'multipick_cluster2D' )
        call xmultipick_cluster2D%execute(cline)
    case( 'pick_extract_cluster2D' )
        call xpick_extract_cluster2D%execute(cline)

    case DEFAULT
        THROW_HARD('prg='//trim(prg)//' is unsupported')
end select
call update_job_descriptions_in_project( cline )
! close log file
if( logfhandle .ne. OUTPUT_UNIT )then
    if( is_open(logfhandle) ) call fclose(logfhandle)
endif
call simple_print_git_version('904965c3')
! end timer and print
rt_exec = toc(t0)
call simple_print_timer(rt_exec)
end program simple_stream
