module simple_syslib
#ifdef IFX
  use IFPORT
#endif
use simple_defs
use simple_error
use, intrinsic :: iso_fortran_env
use, intrinsic :: iso_c_binding
implicit none
! local version of throw_hard to enable public feature
#define THROW_ERROR(msg) call simple_exception(msg, __FILENAME__ , __LINE__)

!> glibc interface CONFORMING TO POSIX.1-2001, POSIX.1-2008, SVr4, 4.3BSD.
interface

    function rmdir(dirname) bind(C, name="rmdir")
        use, intrinsic :: iso_c_binding
        integer(c_int) :: rmdir
        character(c_char),dimension(*),intent(in)  ::  dirname
    end function rmdir

    !! mkdir() attempts to create a directory named pathname. mkdir returns zero
    !! on success, or -1 if an error occurred (in which case, errno is set
    !! appropriately). If errno equals EEXIST pathname already exists (not
    !! necessarily as a directory). This includes the case where pathname is a
    !! symbolic link, dangling or not.
    function mkdir(path,mode) bind(c,name="mkdir")
        use, intrinsic :: iso_c_binding
        integer(c_int) :: mkdir
        character(kind=c_char,len=1),dimension(*),intent(in) :: path
        integer(c_int16_t), value :: mode
    end function mkdir

    !! symlink() creates a symbolic link named linkpath to target. On success,
    !! zero is returned. On error, -1 is returned, and errno is set
    !! appropriately.
    function symlink(target_path, link_path) bind(c,name="symlink")
        use, intrinsic :: iso_c_binding
        integer(c_int) :: symlink
        character(kind=c_char,len=1),dimension(*),intent(in) :: target_path
        character(kind=c_char,len=1),dimension(*),intent(in) :: link_path
    end function symlink

    ! !!  sync() causes all buffered modifications to file metadata and data to be
    ! !!  written to the underlying filesystems.
    function fsync (fd) bind(c,name="fsync")
      use iso_c_binding, only: c_int
        integer(c_int), value :: fd
        integer(c_int) :: fsync
    end function fsync

    ! For float parsing only!
    function sscanf(str, fmt, val) bind(C, name="sscanf")
        use iso_c_binding, only : c_int, c_char, c_float
        integer(kind=c_int) :: sscanf
        character(kind=c_char,len=1), dimension(*),intent(in)  :: str, fmt
        real(kind=c_float),                        intent(out) :: val
    end function sscanf

end interface

!> SIMPLE_POSIX.c commands
interface

    function isdir(dirname, str_len) bind(C, name="isdir")
        import
        integer(c_int) :: isdir
        character(c_char),dimension(*),intent(in)  ::  dirname
        integer(c_int), intent(in) :: str_len
    end function isdir

    function makedir(dirname, str_len) bind(C, name="makedir")
        import
        integer(c_int) :: makedir
        character(c_char),dimension(*),intent(in)  ::  dirname
       integer(c_int), intent(in) :: str_len
    end function makedir

    function removedir(dirname,str_len, count) bind(C, name="remove_directory")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: removedir
        character(c_char),dimension(*),intent(in)  ::  dirname
        integer(c_int), intent(in) :: str_len
        integer(c_int), intent(inout) :: count
    end function removedir

    function list_dirs(path, str_len, list_fout, str_len_fout, count) bind(c,name="list_dirs")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: list_dirs                                 !> return success
        character(kind=c_char,len=1),dimension(*),intent(in):: path !> input pathname
        integer(c_int), intent(in)    :: str_len                    !> input pathname string length
        character(kind=c_char,len=1),dimension(*),intent(in):: list_fout !> output list string file name
        integer(c_int), intent(in)    :: str_len_fout               !> output list file name string length
        integer(c_int), intent(inout) :: count                      !> return number of elements in results
    end function list_dirs

    function wait_pid(pid) bind(c,name="wait_pid")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: wait_pid                                    !> return PID of forked process
        integer(c_int), intent(in) :: pid
    end function wait_pid

    function touch(filename, len) bind(c,name="touch")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: touch                                       !> return success of touch
        character(kind=c_char,len=1),dimension(*),intent(in) :: filename
        integer(c_int), intent(in) :: len
    end function touch

    function get_absolute_pathname(infile, inlen, outfile, outlen) bind(c,name="get_absolute_pathname")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: get_absolute_pathname                             !> return status
        character(kind=c_char,len=1),dimension(*),intent(in)    :: infile   !> input pathname
        integer(c_int), intent(in)  :: inlen                                !> input pathname string length
        character(kind=c_char,len=1),dimension(*),intent(inout) :: outfile  !> output pathname
        integer(c_int), intent(out) :: outlen                               !> output pathname string length
    end function get_absolute_pathname

    function get_sysinfo(HWM, totRAM, shRAM, bufRAM, peakBuf) bind(c,name="get_sysinfo")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: get_sysinfo
        integer(c_long), intent(inout) :: HWM                !> high-water mark
        integer(c_long), intent(inout) :: totRAM             !> total RAM usage
        integer(c_long), intent(inout) :: shRAM              !> shared RAM usage
        integer(c_long), intent(inout) :: bufRAM             !> this process's buffered RAM
        integer(c_long), intent(inout) :: peakBuf            !> this process's peak RAM usage
    end function get_sysinfo

    function regexp_match(source,src_len, regex,rgx_len) bind(C,name="regexp_match")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: regexp_match
        character(kind=c_char,len=1),dimension(*),intent(in)    :: source  !> input string
        integer(c_int), intent(in) :: src_len
        character(kind=c_char,len=1),dimension(*),intent(in)    :: regex   !> input RE string
        integer(c_int), intent(in) :: rgx_len
    end function

end interface

interface simple_getenv
    module procedure simple_getenv_1
    module procedure simple_getenv_2
end interface

contains

    subroutine exec_cmdline( cmdline, waitflag, suppress_errors, exitstat)
        character(len=*),  intent(in)  :: cmdline
        logical, optional, intent(in)  :: waitflag, suppress_errors
        integer, optional, intent(out) :: exitstat
        character(len=:), allocatable  :: cmdstr
        character(len=100) ::errmsg
        integer ::  cstat, exec_stat
        logical :: l_doprint, wwait, l_suppress_errors
        l_doprint = .false.
        wwait     = .true.
        l_suppress_errors = .false.
        if( present(waitflag)        ) wwait = waitflag
        if( present(suppress_errors) ) l_suppress_errors = suppress_errors
        if( l_suppress_errors )then
            allocate(cmdstr, source=trim(adjustl(cmdline))//' '//SUPPRESS_MSG)
        else
            allocate(cmdstr, source=trim(adjustl(cmdline)))
        endif
        call execute_command_line(trim(adjustl(cmdstr)), wait=wwait, exitstat=exec_stat, cmdstat=cstat, cmdmsg=errmsg)
        if( .not. l_suppress_errors ) call raise_sys_error( cmdstr, exec_stat, cstat, errmsg )
        if( l_doprint )then
            write(logfhandle,*) 'command            : ', cmdstr
            write(logfhandle,*) 'status of execution: ', exec_stat
        endif
        if(present(exitstat))exitstat=exec_stat
    end subroutine exec_cmdline

    !>  Handles error from system call
    subroutine raise_sys_error( cmd, exit_status, cmdstat, cmdmsg )
        integer,          intent(in) :: exit_status, cmdstat
        character(len=*), intent(in) :: cmd
        character(len=*), intent(in) :: cmdmsg
        logical :: err
        err = .false.
        if( exit_status /= 0 )then
            write(logfhandle,*)'System error', exit_status,' for command: ', trim(adjustl(cmd))
            err = .true.
        endif
        if( cmdstat /= 0 )then
            write(logfhandle,*)cmdmsg
            call simple_error_check(cmdstat,' command could not be executed: '//trim(adjustl(cmd)))
            write(logfhandle,*)'cmdstat = ',cmdstat,' command could not be executed: ', trim(adjustl(cmd))
            err = .true.
        endif
    end subroutine raise_sys_error

    !> isenv; return 0 if environment variable is present
    logical function simple_isenv( name )
        character(len=*), intent(in) :: name
        integer                      :: status
        simple_isenv=.false.
        status=1
        call get_environment_variable( trim(adjustl(name)), status=status)
        if(status==0) simple_isenv=.true.
    end function simple_isenv

    !> simple_getenv gets the environment variable string and returns status
    function simple_getenv_1( name , retval, allowfail, silent)  result( status )
        character(len=*),      intent(in)  :: name
        character(len=*),      intent(out) :: retval
        logical,     optional, intent(in)  :: allowfail
        logical,     optional, intent(in)  :: silent
        integer                            :: length, status
        logical                            :: l_silent
        l_silent = .false.
        if(present(silent)) l_silent = silent
        call get_environment_variable( trim(name), value=retval, length=length, status=status)
        if( status == -1 ) write(logfhandle,*) 'value string too short; simple_syslib :: simple_getenv_1'
        if( status ==  1 )then
            if(.not. l_silent) write(logfhandle,*) 'environment variable: ', trim(name), ' is not defined; simple_syslib :: simple_getenv_1'
            retval = 'undefined'
            return
        endif
        if( status ==  2 ) write(logfhandle,*) 'environment variables not supported by system; simple_syslib :: simple_getenv_1'
        if( length ==  0 .or. status /= 0 )then
            retval = ""
            return
        end if
    end function simple_getenv_1

    !> simple_getenv gets the environment variable string and returns status
    function simple_getenv_2( name , status, allowfail)  result( envval )
        character(len=*),      intent(in)  :: name
        integer, intent(out)               :: status
        logical,     optional, intent(in)  :: allowfail
        character(len=:), allocatable      :: envval
        character(len=STDLEN)              :: retval
        integer                            :: length
        call get_environment_variable( trim(name), value=retval, length=length, status=status)
        if( status == -1 ) write(logfhandle,*) 'value string too short; simple_syslib :: simple_getenv_2'
        if( status ==  1 )then
            write(logfhandle,*) 'environment variable: ', trim(name), ' is not defined; simple_syslib :: simple_getenv_2'
            envval = 'undefined'
            return
        endif
        if( status ==  2 ) write(logfhandle,*) 'environment variables not supported by system; simple_syslib :: simple_getenv_2'
        if( length ==  0 .or. status /= 0 )then
            envval = ""
            return
        end if
        envval = trim(retval)
    end function simple_getenv_2

    !> \brief Touch file, create file if necessary
    subroutine simple_touch( fname , errmsg, status)
        character(len=*), intent(in)           :: fname !< input filename
        character(len=*), intent(in), optional :: errmsg
        integer, intent(out), optional :: status
        integer :: iostat
        iostat  = touch(trim(adjustl(fname)), len_trim(adjustl(fname)))
        if(iostat/=0)then
            call simple_error_check(iostat, "In simple_touch  msg:"//trim(errmsg))
        endif
        if(present(status))status=iostat
    end subroutine simple_touch

    !> \brief Soft link file
    subroutine syslib_symlink( f1, f2 , errmsg, status)
        character(len=*), intent(in)           :: f1, f2 !< input filename
        character(len=*), intent(in), optional :: errmsg
        integer, intent(out), optional :: status
        integer :: iostat
        iostat  = symlink(trim(adjustl(f1))//achar(0), trim(adjustl(f2))//achar(0))
        if(iostat/=0)then
            call simple_error_check(iostat, "In syslib_symlink  msg:"//trim(errmsg))
        endif
        if(present(status))status=iostat
    end subroutine syslib_symlink

    !> \brief  Rename or move file
    subroutine simple_rename( filein, fileout, overwrite, errmsg )
        character(len=*), intent(in)               :: filein, fileout !< input filename
        logical,          intent(in),     optional :: overwrite       !< default true
        character(len=*), intent(in),     optional :: errmsg          !< message
        character(kind=c_char, len=:), allocatable :: f1, f2
        character(len=:),              allocatable :: msg, errormsg
        integer :: file_status
        logical :: force_overwrite
        if( present(errmsg) )then
            allocate(errormsg, source=". Message: "//trim(errmsg))
        else
            allocate(errormsg, source=". ")
        end if
        if( .not. file_exists(filein) ) THROW_ERROR("designated input file doesn't exist "//trim(filein)//trim(errormsg))
        force_overwrite = .true.
        if( present(overwrite) ) force_overwrite=overwrite
        if( file_exists(trim(fileout)) .and. (force_overwrite) ) call del_file(trim(fileout))
        allocate(f1, source=trim(adjustl(filein))//achar(0))
        allocate(f2, source=trim(adjustl(fileout))//achar(0))
        file_status = rename(trim(f1), trim(f2))
        if( file_status /= 0 )then
            allocate(msg,source="simple_rename failed to rename file "//trim(filein)//trim(errormsg))
            call simple_error_check(file_status, trim(msg))
            deallocate(msg)
        endif
        deallocate(f1,f2,errormsg)
    end subroutine simple_rename

    function simple_chmod(pathname, mode ) result( status )
        character(len=*), intent(in) :: pathname, mode
        integer :: status, imode
        imode = INT(o'000') ! convert symbolic to octal
        if ( index(mode, 'x') /=0) imode=IOR(imode,INT(o'111'))
        if ( index(mode, 'w') /=0) imode=IOR(imode,INT(o'222'))
        if ( index(mode, 'r') /=0) imode=IOR(imode,INT(o'444'))
        status = chmod(pathname, mode) !! intrinsic GNU
        if( status/=0 ) call simple_error_check(status,"simple_syslib::simple_chmod chmod failed "//trim(pathname))
    end function simple_chmod

    !>  Wrapper for POSIX system call stat
    subroutine simple_file_stat( filename, status, buffer, doprint )
        character(len=*),     intent(in)    :: filename
        integer,              intent(inout) :: status
        integer, allocatable, intent(inout) :: buffer(:)  !< POSIX stat struct
        logical, optional,    intent(in)    :: doprint
        logical :: l_print, currently_opened
        l_print = .false.
        currently_opened=.false.
        allocate(buffer(13), source=0)
        status = stat(trim(adjustl(filename)), buffer)
        if( present(doprint) )l_print = doprint
        if( l_print )then
            write(logfhandle,*) 'command: stat ', trim(adjustl(filename))
            write(logfhandle,*) 'status of execution: ', status
        endif
    end subroutine simple_file_stat

    logical function is_io(unit)
        integer, intent(in) :: unit
        is_io=.false.
        if (unit == ERROR_UNIT .or. unit == OUTPUT_UNIT .or. unit == INPUT_UNIT) is_io= .true.
    end function is_io

    !>  \brief  check whether a IO unit is currently opened
    logical function is_open( unit_number )
        integer, intent(in)   :: unit_number
        integer               :: io_status
        character(len=STDLEN) :: io_message
        io_status = 0
        is_open=.false.
        inquire(unit=unit_number, opened=is_open,iostat=io_status,iomsg=io_message)
        if(is_iostat_eor(io_status) .or. is_iostat_end(io_status)) return
        if (io_status .ne. 0) then
            write(logfhandle,*) 'is_open: I/O error ', io_status, ': ', trim(adjustl(io_message))
            THROW_ERROR('I/O')
        endif
    end function is_open

    !>  \brief  check if a file exists on disk
    !! return logical true=dir exists, false=dir does not exist
    logical function dir_exists( dname )
        character(len=*), intent(in) :: dname
        integer :: status
        integer, allocatable :: buffer(:)
        character(kind=c_char, len=:), allocatable :: d1
        dir_exists=.false.
        allocate(d1,source=trim(adjustl(dname))//achar(0))
        status = isdir(trim(d1), len_trim(d1))
        deallocate(d1)
        if (status == 1) then
            dir_exists = .true.
            call simple_file_stat( trim(adjustl(dname)), status, buffer, .false. )
        endif
    end function dir_exists

    !>  \brief  check if a file exists on disk
    !! return logical true=FILE exists, false=FILE does not exist
    logical function file_exists( fname )
        character(len=*), intent(in) :: fname
        inquire(file=trim(adjustl(fname)), exist = file_exists)
    end function file_exists

    !>  \brief  check whether a file is currently opened
    logical function is_file_open( fname )
        character(len=*), intent(in)  :: fname
        integer               :: io_status
        character(len=STDLEN) :: io_message
        io_status = 0
        inquire(file=fname, opened=is_file_open,iostat=io_status,iomsg=io_message)
        if (io_status .ne. 0) then
            THROW_ERROR('I/O '//trim(adjustl(io_message)))
        endif
    end function is_file_open

    !> \brief  Get current working directory
    subroutine simple_getcwd( cwd )
        character(len=*), intent(inout) :: cwd   !< output pathname
        integer :: io_status
        io_status = getcwd(cwd)
        if(io_status /= 0) call simple_error_check(io_status, &
            "syslib:: simple_getcwd failed to get path "//trim(cwd))
    end subroutine simple_getcwd

    !> \brief  Change working directory
    !! return optional status 0=success
    subroutine simple_chdir( newd, oldd, status, errmsg )
        character(len=*),           intent(in)  :: newd   !< target pathname
        character(len=*), optional, intent(out) :: oldd
        integer,          optional, intent(out) :: status
        character(len=*), optional, intent(in)  :: errmsg
        character(len=LONGSTRLEN)               :: olddir
        character(len=300) :: eemsg
        character(len=:), allocatable :: targetdir
        integer :: io_status
        logical :: dir_e, check_exists
        if(present(status)) status = 1
        if(present(oldd))then
            call simple_getcwd(olddir)
            oldd = trim(olddir)
        endif
        if(allocated(targetdir))deallocate(targetdir)
        check_exists=.true.
        targetdir = simple_abspath(trim(newd), errmsg=eemsg, check_exists=check_exists)
        inquire(file=trim(targetdir), EXIST=dir_e, IOSTAT=io_status)
        if(dir_e) then
            io_status = chdir(trim(targetdir))
            if(io_status /= 0)then
                if(present(errmsg))write (*,*) "ERROR>> ", trim(errmsg)
                select case (io_status)
                case (2)  ! ENOENT
                    write (*,*)'The directory '//TRIM(targetdir)//' does not exist'
                case (20) ! ENOTDIR
                    write (*,*) TRIM(targetdir)//' is not a directory'
                case default
                    write (*,*)'Error with code ', io_status
                end select
                call simple_error_check(io_status, &
                    "syslib:: simple_chdir failed to change path "//trim(targetdir))
            endif
        else
            if(present(errmsg))write (*,*) trim(errmsg)
            THROW_ERROR("directory does not exist")
        endif
        if(present(status)) status = io_status
        deallocate(targetdir)
    end subroutine simple_chdir

    !> \brief  Make directory
    subroutine simple_mkdir( dir, errmsg, verbose)
        character(len=*),           intent(in) :: dir
        character(len=*), optional, intent(in) :: errmsg
        logical,          optional, intent(in) :: verbose
        logical, parameter :: ignore_here = .false.
        character(kind=c_char, len=:), allocatable :: path
        character(len=STDLEN) :: tmpdir
        integer :: io_status, lenstr
        logical :: l_verbose
        l_verbose = .true.
        if( present(verbose) ) l_verbose = verbose
        ! check input arg
        tmpdir = trim(adjustl(dir))
        lenstr = len_trim(tmpdir)
        if( lenstr==0 ) then
            if( verbose )write(logfhandle,*)"syslib:: simple_mkdir arg empty "//trim(tmpdir)
            return
        else if( (lenstr<=2) .and. (tmpdir(1:1)=='/' .or. tmpdir(1:1)=='.') )then
            ! ignore '/' '.' './' '..'
            if( verbose )write(logfhandle,*)"syslib:: simple_mkdir arg special char: "//trim(tmpdir)
        endif
        io_status = 0
        if(.not. dir_exists(trim(adjustl(tmpdir)))) then
            ! prepare path for C function
            allocate(path, source=trim(tmpdir)//c_null_char)
            io_status = makedir(trim(adjustl(path)), len_trim(tmpdir))
            if(.not. dir_exists(trim(adjustl(path)))) then
                if(present(errmsg))write (*,*) "ERROR>> ", trim(errmsg)
                if( verbose )write(logfhandle,*)" syslib:: simple_mkdir failed to create "//trim(path)
                if(.not. ignore_here)then
                    if(io_status /= 0) call simple_error_check(io_status, &
                        "syslib:: simple_mkdir failed to create "//trim(path))
                endif
            endif
            deallocate(path)
        end if
    end subroutine simple_mkdir

    !> \brief  Remove directory
    !! return status 0=success for directory exists or directory created
    !! return error status for other removedir results
    subroutine simple_rmdir( d , status, errmsg)
        character(len=*),intent(in)              :: d
        integer,         intent(out), optional   :: status
        character(len=*),intent(in),  optional   :: errmsg
        character(kind=c_char,len=:), allocatable :: path
        integer                                   :: io_status
        logical                                   :: dir_e
        integer :: err, length, count
        io_status=0
        inquire(file=trim(adjustl(d)), exist=dir_e)
        if(dir_e) then
            count=0
            allocate(path, source=trim(adjustl(d))//c_null_char)
            length = len_trim(adjustl(path))
            io_status = removedir(trim(adjustl(path)), length, count)
            if(io_status /= 0)then
                if(present(errmsg))write (*,*) "ERROR>> ", trim(errmsg)
                err = int(IERRNO(), kind=4 )
                call simple_error_check(io_status, "syslib:: simple_rmdir failed to remove "//trim(d))
                io_status=0
            endif
            deallocate(path)
        end if
        if(present(status)) status = io_status
    end subroutine simple_rmdir

    !> ensure C-strings get converted to fortran-style strings
    subroutine syslib_c2fortran_string(str, len)
        character(len=*), intent(inout) :: str
        integer, intent(out), optional :: len
        integer :: l
        l = index(str, char(0))
        if(present(len)) len = l-1
        if(l>0) str(l:)=' '
    end subroutine syslib_c2fortran_string

    function find_next_int_dir_prefix( dir2list, last_prev_dir ) result( next_int_dir_prefix )
        use simple_strings, only: char_is_a_number, map_str_nrs, str2int
        character(len=*),                        intent(in)  :: dir2list
        character(len=:), allocatable, optional, intent(out) :: last_prev_dir
        character(len=STDLEN)              :: str
        character(len=STDLEN), allocatable :: dirs(:)
        logical,               allocatable :: nrmap(:)
        integer,               allocatable :: dirinds(:)
        integer :: i, j, last_nr_ind, io_stat
        integer :: next_int_dir_prefix, ndirs, loc(1)
        dirs = simple_list_dirs(dir2list)
        last_nr_ind = 1
        if( allocated(dirs) )then
            ndirs = size(dirs)
        else
            next_int_dir_prefix = 1
            return
        endif
        allocate(dirinds(ndirs), source=0)
        do i=1,ndirs
            str = trim(dirs(i))
            if( char_is_a_number(str(1:1)) )then
                nrmap = map_str_nrs(trim(str))
                do j=1,size(nrmap)
                    if( nrmap(j) )then
                        last_nr_ind = j
                    else
                        exit
                    endif
                enddo
                call str2int(str(1:last_nr_ind), io_stat, dirinds(i))
            endif
        end do
        if( any(dirinds > 0) )then
            loc = maxloc(dirinds)
            next_int_dir_prefix = dirinds(loc(1)) + 1
            if( present(last_prev_dir) ) allocate(last_prev_dir, source=trim(dirs(loc(1))))
        else
            next_int_dir_prefix = 1
        endif
    end function find_next_int_dir_prefix

    function simple_list_dirs(path, status) result(list)
        use simple_strings, only: int2str
        character(len=*),           intent(in)  :: path
        integer,          optional, intent(out) :: status
        character(len=STDLEN),        allocatable :: list(:)
        character(kind=c_char,len=:), allocatable :: pathhere
        character(len=STDLEN) :: list_fname
        integer               :: stat, i,num_dirs, luntmp
        allocate(pathhere, source=trim(adjustl(path))//c_null_char)
        list_fname =  '__simple_dirlist_'//int2str(part_glob)//'__'
        stat = list_dirs(trim(pathhere),len_trim(pathhere), trim(list_fname), len_trim(list_fname), num_dirs)
        if(stat/=0)THROW_ERROR("failed to process list_dirs "//trim(pathhere))
        open(newunit=luntmp, file=trim(list_fname))
        allocate( list(num_dirs) )
        do i = 1,num_dirs
            read( luntmp, '(a)' ) list(i)
        enddo
        close(luntmp)
        call del_file(list_fname)
        deallocate(pathhere)
        if(present(status)) status= stat
    end function simple_list_dirs

    subroutine simple_list_files( pattern, list )
        use simple_strings, only: int2str
        character(len=*),                       intent(in)    :: pattern
        character(len=LONGSTRLEN), allocatable, intent(inout) :: list(:)
        character(len=LONGSTRLEN) :: cmd
        character(len=LONGSTRLEN) :: tmpfile
        character(len=1) :: junk
        integer :: sz, funit, ios, i, nlines
        tmpfile = '__simple_filelist_'//int2str(part_glob)//'__'
        cmd = 'ls -1f '//trim(pattern)//' > '//trim(tmpfile)
        call exec_cmdline( cmd, suppress_errors=.true.)
        inquire(file=trim(tmpfile), size=sz)
        if( allocated(list) ) deallocate(list)
        if( sz > 0 )then
            open(newunit=funit, file=trim(tmpfile))
            nlines = 0
            do
                read(funit,*,iostat=ios) junk
                if(ios /= 0)then
                    exit
                else
                    nlines = nlines + 1
                endif
            end do
            rewind(funit)
            allocate( list(nlines) )
            do i=1,nlines
                read(funit, '(a)') list(i)
            enddo
            close(funit, status='delete')
        else
            open(newunit=funit, file=trim(tmpfile))
            close(funit, status='delete')
        endif
    end subroutine simple_list_files

    subroutine simple_list_files_regexp( dir, regexp, list, chronological)
        use simple_strings, only: int2str
        character(len=*),                       intent(in)    :: dir
        character(len=*),                       intent(in)    :: regexp
        character(len=LONGSTRLEN), allocatable, intent(inout) :: list(:)
        logical,                   optional,    intent(in)    :: chronological
        character(len=LONGSTRLEN) :: cmd
        character(len=LONGSTRLEN) :: tmpfile
        character(len=1) :: junk
        integer :: sz, funit, ios, i, nlines
        logical :: l_chrono
        if( len_trim(adjustl(regexp)) == 0) return
        l_chrono = .false.
        if( present(chronological) ) l_chrono = chronological
        tmpfile = '__simple_filelist_'//int2str(part_glob)//'__'
        ! builds command
        if( l_chrono )then
            cmd = 'ls -1f -rt '//adjustl(trim(dir))//' | grep -E '''//adjustl(trim(regexp))//''' > '//trim(tmpfile)
        else
            cmd = 'ls -1f '//adjustl(trim(dir))//' | grep -E '''//adjustl(trim(regexp))//''' > '//trim(tmpfile)
        endif
        call exec_cmdline( cmd, suppress_errors=.true.)
        inquire(file=trim(tmpfile), size=sz)
        if( allocated(list) ) deallocate(list)
        if( sz > 0 )then
            open(newunit=funit, file=trim(tmpfile))
            nlines = 0
            do
                read(funit,*,iostat=ios) junk
                if(ios /= 0)then
                    exit
                else
                    nlines = nlines + 1
                endif
            end do
            rewind(funit)
            allocate( list(nlines) )
            do i=1,nlines
                read(funit, '(a)') list(i)
                list(i) = adjustl(trim(dir))//'/'//trim(list(i))
            enddo
            close(funit, status='delete')
        else
            open(newunit=funit, file=trim(tmpfile))
            close(funit, status='delete')
        endif
    end subroutine simple_list_files_regexp

    !> \brief  is for deleting a file
    subroutine del_file( file )
        character(len=*), intent(in) :: file !< input filename
        integer :: fnr, file_status
        if( file_exists(file) )then
            open(newunit=fnr,file=file,STATUS='OLD',IOSTAT=file_status)
            if( file_status == 0 )then
                close(fnr, status='delete',IOSTAT=file_status)
                if(file_status /=0) THROW_ERROR("failed to close file "//trim(file))
            end if
        endif
    end subroutine del_file

    !> simple_timestamp prints time stamp (based on John Burkardt's website code)
    subroutine simple_timestamp ( )
        character(len= 8) :: ampm
        integer (kind=sp) :: d
        integer (kind=sp) :: h
        integer (kind=sp) :: m
        integer (kind=sp) :: mm
        character (len=9 ), parameter, dimension(12) :: month = (/ &
            'January  ', 'February ', 'March    ', 'April    ', &
            'May      ', 'June     ', 'July     ', 'August   ', &
            'September', 'October  ', 'November ', 'December ' /)
        integer    :: n, s, y, values(8)
        call date_and_time(values=values)
        y = values(1)
        m = values(2)
        d = values(3)
        h = values(5)
        n = values(6)
        s = values(7)
        mm = values(8)
        if ( h < 12 ) then
            ampm = 'AM'
        else if ( h == 12 ) then
            if ( n == 0 .and. s == 0 ) then
                ampm = 'Noon'
            else
                ampm = 'PM'
            end if
        else
            h = h - 12
            if ( h < 12 ) then
                ampm = 'PM'
            else if ( h == 12 ) then
                if ( n == 0 .and. s == 0 ) then
                    ampm = 'Midnight'
                else
                    ampm = 'AM'
                end if
            end if
        end if
        write ( *, '(i2.2,1x,a,1x,i4,2x,i2,a1,i2.2,a1,i2.2,a1,i3.3,1x,a)' ) &
            d, trim ( month(m) ), y, h, ':', n, ':', s, '.', mm, trim ( ampm )
    end subroutine simple_timestamp

    function cpu_usage ()
        real    :: cpu_usage
        integer :: ios, i
        integer :: unit,oldidle, oldsum, sumtimes
        real    :: percent
        character(len = 4) lineID ! 'cpu '
        integer, dimension(9) :: times
        cpu_usage=0.0
        sumtimes = 0; oldsum=0
        oldidle=0
        times = 0
        percent = 0.
        write(logfhandle,'(a)') 'CPU Usage'
        open(newunit=unit, file = '/proc/stat', status = 'old', action = 'read', iostat = ios)
        if (ios /= 0) then
            THROW_ERROR('opening /proc/stat')
        else
            read(unit, fmt = *, iostat = ios) lineID, (times(i), i = 1, 9)
            if (ios /= 0)         THROW_ERROR('reading /proc/stat')
            close(unit, iostat = ios)
            if (ios /= 0)         THROW_ERROR('closing /proc/stat')
            if (lineID /= 'cpu ') THROW_ERROR('reading /proc/stat')
            sumtimes = sum(times)
            percent = (1. - real((times(4) - oldidle)) / real((sumtimes - oldsum))) * 100.
            write(logfhandle, fmt = '(F6.2,A2)') percent, '%'
            oldidle = times(4)
            oldsum = sumtimes
        end if
        cpu_usage=percent
    end function cpu_usage

    integer(4) function get_process_id( )
        get_process_id = getpid()
    end function get_process_id

    integer(4) function get_login_id( )
        get_login_id = getuid()
    end function get_login_id

    subroutine print_compiler_info(file_unit)
        integer, intent (in), optional :: file_unit
        integer  :: file_unit_op
        character(len=:), allocatable :: compilation_cmd, compiler_ver
        if (present(file_unit)) then
            file_unit_op = file_unit
        else
            file_unit_op = OUTPUT_UNIT
        end if
        write( file_unit_op, '(A,A)' ) 'CMAKE Fortran COMPILER VERSION ',&
            trim(FC_COMPILER_CMAKE_VERSION)
        compilation_cmd = COMPILER_OPTIONS()
        compiler_ver = COMPILER_VERSION()
        if(allocated(compiler_ver))then
            if(len(compiler_ver) <= 0) THROW_ERROR('simple_syslib compiler_version str le 0')

            write( file_unit_op, '(A,A,A,A)' ) &
                ' This file was compiled by ', trim(adjustl(compiler_ver)), &
                ' using the options ', trim(adjustl(compilation_cmd))
            deallocate (compilation_cmd, compiler_ver)
        endif
    end subroutine print_compiler_info

    subroutine simple_sysinfo_usage(valueRSS,valuePeak,valueSize,valueHWM)
        integer(kind=8), intent(out) :: valueRSS
        integer(kind=8), intent(out) :: valuePeak
        integer(kind=8), intent(out) :: valueSize
        integer(kind=8), intent(out) :: valueHWM
        integer :: stat
        integer(c_long) :: HWM, totRAM, shRAM, bufRAM, peakBuf
        stat = get_sysinfo( HWM, totRAM, shRAM, bufRAM, peakBuf)
        if (stat /= 0 ) THROW_ERROR("failed to get sysinfo")
        valueRSS = bufRAM
        valuePeak = totRAM
        valueSize = shRAM
        valueHWM = HWM
    end subroutine simple_sysinfo_usage

    ! Suggestion from https://stackoverflow.com/a/30241280
    subroutine simple_mem_usage(valueRSS,valuePeak,valueSize,valueHWM)
        implicit none
        integer(kind=8), intent(out) :: valueRSS
        integer(kind=8), intent(out), optional :: valuePeak
        integer(kind=8), intent(out), optional :: valueSize
        integer(kind=8), intent(out), optional :: valueHWM
        character(len=200) :: filename=' '
        character(len=80)  :: line
        character(len=8)   :: pid_char=' '
        integer            :: pid,unit
        logical            :: ifxst
        valueRSS=-1    ! return negative number if not found
        if(present(valuePeak))valuePeak=-1
        if(present(valueSize))valueSize=-1
        if(present(valueHWM))valueHWM=-1
        !--- get process ID
        pid=getpid()
        write(pid_char,'(I8)') pid
        filename='/proc/'//trim(adjustl(pid_char))//'/status'
        !--- read system file
        inquire (file=trim(filename),exist=ifxst)
        if (.not.ifxst) then
            write (*,*) 'system file does not exist'
            return
        endif
        open(newunit=unit, file=filename, action='read')
        ! the order of the following do loops is dependent on cat /proc/PID/status listing
        if(present(valuePeak))then
            do
                read (unit,'(a)',end=110) line
                if (line(1:7).eq.'VmPeak:') then
                    read (line(8:),*) valuePeak
                    exit
                endif
            enddo
110         continue
        endif
        if(present(valueSize))then
            do
                read (unit,'(a)',end=120) line
                if (line(1:7).eq.'VmSize:') then
                    read (line(8:),*) valueSize
                    exit
                endif
            enddo
120         continue
        endif
        if(present(valueHWM))then
            do
                read (unit,'(a)',end=130) line
                if (line(1:6).eq.'VmHWM:') then
                    read (line(7:),*) valueHWM
                    exit
                endif
            enddo
130         continue
        endif
        do
            read (unit,'(a)',end=140) line
            if (line(1:6).eq.'VmRSS:') then
                read (line(7:),*) valueRSS
                exit
            endif
        enddo
140     continue
        close(unit)
        return
    end subroutine simple_mem_usage

    subroutine simple_dump_mem_usage(dump_file)
        character(len=*), intent(inout), optional :: dump_file
        character(len=200)    :: filename=' '
        character(len=8)      :: pid_char=' '
        character(len=STDLEN) :: command
        integer               :: pid
#ifdef MACOSX
        write(logfhandle,*)" simple_dump_mem_usage cannot run on MacOSX"
        return
#endif
        pid=getpid()
        write(pid_char,'(I8)') pid
        filename='/proc/'//trim(adjustl(pid_char))//'/status'
        command = 'grep -E "^(VmPeak|VmSize|VmHWM|VmRSS):"<'//trim(filename)//'|awk "{a[NR-1]=\$2}END{print a[0],a[1],a[2],a[3]}" '
        if(present(dump_file)) command = trim(command)//' >> '//trim(dump_file)
        call exec_cmdline(trim(command))
    end subroutine simple_dump_mem_usage

    function simple_abspath(infile,errmsg,status,check_exists) result(absolute_name)
        character(len=*),              intent(in)    :: infile
        integer,          optional,    intent(out)   :: status
        character(len=*), optional,    intent(in)    :: errmsg
        logical,          optional,    intent(in)    :: check_exists
        character(len=:), allocatable :: absolute_name
        type(c_ptr)                          :: cstring
        character(len=LINE_MAX_LEN), target  :: fstr
        character(kind=c_char,len=LONGSTRLEN):: infilename_c
        character(kind=c_char,len=LONGSTRLEN):: outfilename_c
        integer :: lengthin,  lengthout, status_here
        logical :: check_exists_here
        check_exists_here = .true.
        if( present(check_exists) )check_exists_here = check_exists
        if( check_exists_here )then
            if( .not.file_exists(trim(infile)) )then
                write(logfhandle,*) errmsg
                write(logfhandle,*)' cwd: '//trim(CWD_GLOB)
                THROW_ERROR('file: '//trim(infile)//' does not exist')
            endif
        endif
        lengthin     = len_trim(infile)
        cstring      = c_loc(fstr)
        infilename_c = trim(infile)//achar(0)
        status_here  = get_absolute_pathname(trim(adjustl(infilename_c)), lengthin, outfilename_c, lengthout)
        call syslib_c2fortran_string(outfilename_c)
        if(allocated(absolute_name)) deallocate(absolute_name)
        if( lengthout > 1)then
            allocate(absolute_name, source=trim(outfilename_c(1:lengthout)))
        else
            allocate(absolute_name, source=trim(infile))
        end if
        if(present(status))status = status_here
    end function simple_abspath

    integer function RE_match(source, regex)
        character(len=*),              intent(in)  :: source,regex
        integer(c_int) :: res
        character(kind=c_char,len=STDLEN)  :: source_c  !> input string
        character(kind=c_char,len=STDLEN)  :: regex_c   !> input RE string
        source_c = trim(source)//achar(0)
        regex_c = trim(regex)//achar(0)
        res = regexp_match(source_c,len_trim(source),  regex_c, len_trim(regex))
        RE_match = INT(res)
    end function RE_match

    subroutine print_slurm_env()
        character(len=255) :: env_value
        character(len=63), allocatable :: env_vars(:);
        integer :: i, stat, len
        len = 63
        allocate (env_vars(7))
        env_vars = [character(len=63) :: "slurm_jobid", "slurm_job_user", "slurm_job_cpus_per_node", "slurm_mem_per_cpu", "slurmd_nodename", "slurm_job_account", "slurm_submit_dir"]
        call get_environment_variable("slurm_jobid", env_value, len, stat)
        if( stat .eq. 0 )then
            write(logfhandle,*) ""
            write(logfhandle,*) "##### simple slurm env #####"
            write(logfhandle,*) ""
            do i = 1, 7
                call get_environment_variable(trim(env_vars(i)), env_value, len, stat)
                if(stat .eq. 0) then
                    write(logfhandle,*) trim(env_vars(i)), achar(9), " : ", achar(9), trim(env_value)
                    endif
                end do
                write(logfhandle,*) ""
                write(logfhandle,*) "############################"
                write(logfhandle,*) ""
        endif
        deallocate (env_vars)
    end subroutine print_slurm_env

end module simple_syslib
