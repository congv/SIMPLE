! write stats for gui 
module simple_guistats
include 'simple_lib.f08'
use simple_oris,  only: oris
use simple_ori,   only: ori
use simple_image, only: image
implicit none

public :: guistats
private
#include "simple_local_flags.inc"

type guistats
    type(oris) :: stats
    logical    :: updated
contains
    ! constructor
    procedure :: init
    ! setters 
    procedure :: new_section
    procedure :: ensure_section
    procedure :: deactivate_section
    generic   :: set => set_1, set_2, set_3
    procedure :: set_1
    procedure :: set_2
    procedure :: set_3
    procedure :: set_now
    procedure :: delete
    procedure :: hide
    procedure :: generate_2D_thumbnail
    procedure :: generate_2D_jpeg
    ! getters
    generic   :: get => get_1
    procedure :: get_1
    procedure :: get_keyline
    ! writers
    procedure :: write
    procedure :: write_json
    ! importers
    procedure :: merge
    !other
    procedure :: kill
end type guistats

contains

    subroutine init( self, remove_existing)
        class(guistats),   intent(inout) :: self
        logical, optional, intent(in)    :: remove_existing
        if(present(remove_existing) .and. remove_existing) then
            if(file_exists(GUISTATS_FILE // '.json')) call del_file(GUISTATS_FILE // '.json')
        endif
        call self%stats%new(1, .false.)
        call self%stats%set(1, "len", 1.0)
        call self%stats%set(1, "sects", 0.0)
        self%updated = .false.
    end subroutine init

    subroutine new_section( self, section_name )
        class(guistats),    intent(inout) :: self
        character(len=*),   intent(in)    :: section_name
        integer                           :: n_sections
        if(self%stats%isthere(1, "sects")) then
            n_sections = int(self%stats%get(1, "sects"))
            n_sections = n_sections + 1
            call self%stats%set(1, "sect_" // int2str(n_sections), section_name)
            call self%stats%set(1, "sects", float(n_sections))
            self%updated = .true.
        else
            call self%stats%set(1, "sects", 1.0)
            call self%stats%set(1, "sect_1", section_name)
            self%updated = .true.
        end if
    end subroutine new_section

    subroutine ensure_section( self, section_name )
        class(guistats),    intent(inout) :: self
        character(len=*),   intent(in)    :: section_name
        integer                           :: i, n_sections
        logical                           :: exists
        exists = .false.
        if(self%stats%isthere(1, "sects")) then
            n_sections = int(self%stats%get(1, "sects"))
            do i = 1, n_sections
                if(self%stats%isthere(1, "sect_" // int2str(i)) \
                    .and. trim(adjustl(self%stats%get_static(1, "sect_" // int2str(i)))) .eq. section_name) then
                    exists = .true.
                    exit 
                end if
            enddo
        end if
        if(.not. exists) then
            call self%new_section(section_name)
            self%updated = .true.
        end if
    end subroutine ensure_section

    subroutine deactivate_section( self, section_name )
        class(guistats),    intent(inout) :: self
        character(len=*),   intent(in)    :: section_name
        integer                           :: i, n_sections
        logical                           :: exists
        exists = .false.
        if(self%stats%isthere(1, "sects")) then
            n_sections = int(self%stats%get(1, "sects"))
            do i = 1, n_sections
                if(self%stats%isthere(1, "sect_" // int2str(i)) \
                    .and. trim(adjustl(self%stats%get_static(1, "sect_" // int2str(i)))) .eq. section_name) then
                        call self%stats%set(1, "sect_" // int2str(i), "null")
                        self%updated = .true.
                    exit 
                end if
            enddo
        end if
    end subroutine deactivate_section

    function get_keyline( self, section, key ) result ( line )
        class(guistats),  intent(inout) :: self
        character(len=*), intent(in)    :: section
        character(len=*), intent(in)    :: key
        integer                         :: line
        logical                         :: exists
        exists = .false.
        do line = 2, self%stats%get_noris()
            if(self%stats%isthere(line, "key") \
                .and. trim(adjustl(self%stats%get_static(line, "key"))) .eq. key \
                .and. self%stats%isthere(line, "sect") \
                .and. trim(adjustl(self%stats%get_static(line, "sect"))) .eq. section) then
                exists = .true.
                exit
            end if
        enddo
        if(.not. exists) then
            call self%stats%reallocate(self%stats%get_noris() + 1)
            call self%stats%set(1, "len", real(self%stats%get_noris()))
            self%updated = .true.
            line = self%stats%get_noris()
        end if
    end function get_keyline

    subroutine set_1( self, section, key, val, primary, alert, alerttext, notify, notifytext )
        class(guistats),   intent(inout)       :: self
        character(len=*),  intent(in)          :: section
        character(len=*),  intent(in)          :: key
        integer,           intent(in)          :: val
        logical, optional, intent(in)          :: primary, alert, notify
        character(len=*), optional, intent(in) :: alerttext, notifytext
        integer                                :: line
        call self%ensure_section(section)
        line = self%get_keyline(section, key)
        call self%stats%set(line, 'key', key)
        call self%stats%set(line, 'val', float(val))
        call self%stats%set(line, 'sect', section)
        call self%stats%set(line, 'type', 'integer')
        if(present(primary)) then
            if(primary) then
                call self%stats%set(line, 'primary', 1.0)
            else
                call self%stats%set(line, 'primary', 0.0)
            end if
        end if 
        if(present(alert)) then
            if(alert) then
                call self%stats%set(line, 'alert', 1.0)
                if(present(alerttext)) then
                    call self%stats%set(line, 'alerttext', alerttext)
                end if
            else
                call self%stats%set(line, 'alert', 0.0)
                call self%stats%delete_entry(line, 'alerttext')
            end if
        end if 
        if(present(notify)) then
            if(notify) then
                call self%stats%set(line, 'notify', 1.0)
                if(present(notifytext)) then
                    call self%stats%set(line, 'notifytext', notifytext)
                end if
            else
                call self%stats%set(line, 'notify', 0.0)
                call self%stats%delete_entry(line, 'notifytext')
            end if
        end if 
        self%updated = .true.
    end subroutine set_1
 
    subroutine set_2( self, section, key, val, primary, alert, alerttext, notify, notifytext )
        class(guistats),  intent(inout)        :: self
        character(len=*), intent(in)           :: section
        character(len=*), intent(in)           :: key
        real,             intent(in)           :: val
        logical, optional, intent(in)          :: primary, alert, notify
        character(len=*), optional, intent(in) :: alerttext, notifytext
        integer                                :: line
        call self%ensure_section(section)
        line = self%get_keyline(section, key)
        call self%stats%set(line, 'key', key)
        call self%stats%set(line, 'val', val)
        call self%stats%set(line, 'sect', section)
        call self%stats%set(line, 'type', 'real')
        if(present(primary)) then
            if(primary) then
                call self%stats%set(line, 'primary', 1.0)
            else
                call self%stats%set(line, 'primary', 0.0)
            end if
        end if 
        if(present(alert)) then
            if(alert) then
                call self%stats%set(line, 'alert', 1.0)
                if(present(alerttext)) then
                    call self%stats%set(line, 'alerttext', alerttext)
                end if
            else
                call self%stats%set(line, 'alert', 0.0)
                call self%stats%delete_entry(line, 'alerttext')
            end if
        end if  
        if(present(notify)) then
            if(notify) then
                call self%stats%set(line, 'notify', 1.0)
                if(present(notifytext)) then
                    call self%stats%set(line, 'notifytext', notifytext)
                end if
            else
                call self%stats%set(line, 'notify', 0.0)
                call self%stats%delete_entry(line, 'notifytext')
            end if
        end if 
        self%updated = .true.
    end subroutine set_2

    subroutine set_3( self, section, key, val, primary, alert, alerttext, notify, notifytext, thumbnail, boxfile, smpd, box)
        class(guistats),  intent(inout)        :: self
        character(len=*), intent(in)           :: section
        character(len=*), intent(in)           :: key
        character(len=*), intent(in)           :: val
        logical, optional, intent(in)          :: primary, alert, thumbnail, notify
        character(len=*), optional, intent(in) :: alerttext, notifytext, boxfile
        real,    optional, intent(in)          :: smpd, box
        integer                                :: line
        call self%ensure_section(section)
        line = self%get_keyline(section, key)
        call self%stats%set(line, 'key', key)
        call self%stats%set(line, 'val', val)
        call self%stats%set(line, 'sect', section)
        if(present(thumbnail) .and. thumbnail) then
            call self%stats%set(line, 'type', 'thumbnail')
            if(present(boxfile)) then
                call self%stats%set(line, 'boxfile', trim(boxfile))
            end if
            if(present(smpd)) then
                call self%stats%set(line, 'smpd', smpd)
            end if
            if(present(box)) then
                call self%stats%set(line, 'box', box)
            end if
        else
            call self%stats%set(line, 'type', 'string')
        end if 
        if(present(primary)) then
            if(primary) then
                call self%stats%set(line, 'primary', 1.0)
            else
                call self%stats%set(line, 'primary', 0.0)
            end if
        end if 
        if(present(alert)) then
            if(alert) then
                call self%stats%set(line, 'alert', 1.0)
                if(present(alerttext)) then
                    call self%stats%set(line, 'alerttext', alerttext)
                end if
            else
                call self%stats%set(line, 'alert', 0.0)
                call self%stats%delete_entry(line, 'alerttext')
            end if
        end if 
        if(present(notify)) then
            if(notify) then
                call self%stats%set(line, 'notify', 1.0)
                if(present(alerttext)) then
                    call self%stats%set(line, 'notifytext', alerttext)
                end if
            else
                call self%stats%set(line, 'notify', 0.0)
                call self%stats%delete_entry(line, 'notifytext')
            end if
        end if
        self%updated = .true.
    end subroutine set_3

    subroutine set_now( self, section, key )
        class(guistats),  intent(inout) :: self  
        character(len=*), intent(in)    :: section
        character(len=*), intent(in)    :: key
        integer                         :: line
        character(8)  :: date
        character(10) :: time
        character(5)  :: zone
        character(16) :: datestr
        integer,dimension(8) :: values
        ! using keyword arguments
        call date_and_time(date,time,zone,values)
        call date_and_time(DATE=date,ZONE=zone)
        call date_and_time(TIME=time)
        call date_and_time(VALUES=values)
        write(datestr, '(I4,A,I2.2,A,I2.2,A,I2.2,A,I2.2)') values(1), '/', values(2), '/', values(3), '_', values(5), ':', values(6)
        call self%set(section, key, datestr)
        self%updated = .true.
    end subroutine set_now

    subroutine get_1( self, section, key, val)
        class(guistats),  intent(inout)        :: self
        character(len=*), intent(in)           :: section
        character(len=*), intent(in)           :: key
        real, intent(inout)                    :: val
        integer                                :: line
        val = 0.0
        do line = 2, self%stats%get_noris()
            if(self%stats%isthere(line, "key") \
            .and. trim(adjustl(self%stats%get_static(line, "key"))) .eq. key \
            .and. self%stats%isthere(line, "sect") \
            .and. trim(adjustl(self%stats%get_static(line, "sect"))) .eq. section) then
                val = self%stats%get(line, "val")
                exit
            end if
        enddo
    end subroutine get_1

    subroutine delete( self, section, key )
        class(guistats),  intent(inout) :: self
        character(len=*), intent(in)    :: section
        character(len=*), intent(in)    :: key
        integer                         :: line
        line = self%get_keyline(section, key)
        call self%stats%delete(line)
        self%updated = .true.
    end subroutine delete

    subroutine hide( self, section, key )
        class(guistats),  intent(inout) :: self
        character(len=*), intent(in)    :: section
        character(len=*), intent(in)    :: key
        integer                         :: line
        line = self%get_keyline(section, key)
        call self%stats%set(line, 'hidden', 1.0)
        self%updated = .true.
    end subroutine hide

    subroutine merge( self, fname, delete )
        class(guistats),    intent(inout) :: self
        character(len=*),   intent(in)    :: fname
        logical, optional,  intent(in)    :: delete
        type(oris)                        :: tmporis
        integer                           :: i, keyline, stats_len
        logical                           :: l_delete = .false.
        if(present(delete)) l_delete = delete
        call tmporis%new(1, .false.)
        call tmporis%read(fname, fromto=[1,1])
        if(tmporis%isthere(1, "len")) then
            stats_len = int(tmporis%get(1, "len"))
            call tmporis%kill
            if(stats_len > 0) then
                call tmporis%new(stats_len, .false.)
                call tmporis%read(fname)
                do i = 2, stats_len
                    if(tmporis%isthere(i, "sect")) then
                        call self%ensure_section(trim(adjustl(tmporis%get_static(i, 'sect'))))
                        if(tmporis%isthere(i, "key")) then
                            keyline = self%get_keyline(trim(adjustl(tmporis%get_static(i, 'sect'))), trim(adjustl(tmporis%get_static(i, 'key'))))
                            call self%stats%transfer_ori(keyline, tmporis, i)
                         endif
                    endif
                enddo
                self%updated = .true.
            end if
        endif
    end subroutine merge

    subroutine write( self, fname )
        class(guistats),  intent(inout)        :: self
        character(len=*), optional, intent(in) :: fname
        integer                                :: i
        if(self%updated .and. self%stats%get_noris() .gt. 1) then
            if(present(fname)) then
                if(file_exists(fname)) call del_file(fname)
                call self%stats%write(fname)
            else
                if(file_exists(GUISTATS_FILE)) call del_file(GUISTATS_FILE)
                do i = 1, self%stats%get_noris()
                    call self%stats%print(i)
                enddo
                call self%stats%write(GUISTATS_FILE)
            end if
            self%updated = .false.
        end if
    end subroutine write

    subroutine kill( self )
        class(guistats),  intent(inout) :: self
        call self%stats%kill
        self%updated = .false.
    end subroutine kill

    subroutine write_json( self )
        use json_module
        class(guistats),  intent(inout) :: self
        type(json_core)                 :: json
        type(json_value), pointer       :: keydata, section, sections     
        integer                         :: isect
        if(self%updated .and. self%stats%isthere(1, "sects") .and. self%stats%get(1, "sects") .gt. 0.0) then
            if(file_exists(GUISTATS_FILE // '.json')) call del_file(GUISTATS_FILE // '.json')
            ! JSON init
            call json%initialize()
            ! create object of section entries
            call json%create_object(sections, 'sections')
            do isect=1, int(self%stats%get(1, "sects"))
                if(self%stats%isthere(1, "sect_" // int2str(isect)) .and. trim(adjustl(self%stats%get_static(1, "sect_" // int2str(isect)))) .ne. "null") then
                    call create_section_array(trim(adjustl(self%stats%get_static(1, "sect_" // int2str(isect)))))
                    call json%add(sections, section)
                end if
            end do
            ! write & clean
            call json%print(sections, GUISTATS_FILE // '.json')
            if( json%failed() )then
                write(logfhandle,*) 'json input/output error for simple_guistats:write_json'
                stop
            endif
            call json%destroy(sections)
            self%updated = .false.
        end if

        contains

            subroutine create_section_array( section_name )
                character(len=*), intent(in) :: section_name
                integer :: i
                call json%create_array(section, section_name)
                do i = 2, self%stats%get_noris()
                    if(self%stats%isthere(i, 'hidden') .and. self%stats%get(i, 'hidden') .eq. 1.0) continue
                    if(self%stats%isthere(i, 'sect') .and. trim(adjustl(self%stats%get_static(i, 'sect'))) .eq. section_name) then
                        if(self%stats%isthere(i, 'key') .and. self%stats%isthere(i, 'val') .and. self%stats%isthere(i, 'type')) then
                            call json%create_object(keydata, trim(adjustl(self%stats%get_static(i, 'key'))))
                            call json%add(keydata, 'key',    trim(adjustl(self%stats%get_static(i, 'key'))))
                            call json%add(keydata, 'type',   trim(adjustl(self%stats%get_static(i, 'type'))))
                            if(trim(adjustl(self%stats%get_static(i, 'type'))) .eq. 'integer') then
                                call json%add(keydata, 'value', int(self%stats%get(i, 'val')))
                            else if(trim(adjustl(self%stats%get_static(i, 'type'))) .eq. 'real') then
                                call json%add(keydata, 'value', dble(self%stats%get(i, 'val')))
                            else if(trim(adjustl(self%stats%get_static(i, 'type'))) .eq. 'string' \
                               .or. trim(adjustl(self%stats%get_static(i, 'type'))) .eq. 'thumbnail') then
                                call json%add(keydata, 'value', trim(adjustl(self%stats%get_static(i, 'val'))))
                            end if
                            if(self%stats%isthere(i, 'primary') .and. self%stats%get(i, 'primary') .gt. 0.0) then
                                call json%add(keydata, 'primary', .true.)
                            else
                                call json%add(keydata, 'primary', .false.)
                            end if
                            if(self%stats%isthere(i, 'alert') .and. self%stats%get(i, 'alert') .gt. 0.0) then
                                call json%add(keydata, 'alert', .true.)
                            else
                                call json%add(keydata, 'alert', .false.)
                            end if
                            if(self%stats%isthere(i, 'alerttext')) then
                                call json%add(keydata, 'alerttext', trim(adjustl(self%stats%get_static(i, 'alerttext'))))
                            end if
                            if(self%stats%isthere(i, 'notify') .and. self%stats%get(i, 'notify') .gt. 0.0) then
                                call json%add(keydata, 'notify', .true.)
                            else
                                call json%add(keydata, 'notify', .false.)
                            end if
                            if(self%stats%isthere(i, 'notifytext')) then
                                call json%add(keydata, 'notifytext', trim(adjustl(self%stats%get_static(i, 'notifytext'))))
                            end if
                            if(self%stats%isthere(i, 'boxfile')) then
                                call json%add(keydata, 'boxfile', trim(adjustl(self%stats%get_static(i, 'boxfile'))))
                            end if
                            if(self%stats%isthere(i, 'box') .and. self%stats%get(i, 'box') .gt. 0.0) then
                                call json%add(keydata, 'box', int(self%stats%get(i, 'box'))) 
                            end if
                            if(self%stats%isthere(i, 'smpd') .and. self%stats%get(i, 'smpd') .gt. 0.0) then
                                call json%add(keydata, 'smpd', dble(self%stats%get(i, 'smpd'))) 
                            end if
                            call json%add(section, keydata)
                        end if
                    end if
                end do

            end subroutine create_section_array
    end subroutine write_json
    
    subroutine generate_2D_thumbnail( self, section, key, oris2D, last_iter )
        class(guistats),  intent(inout) :: self
        type(oris),       intent(inout) :: oris2D
        integer,          intent(in)    :: last_iter
        character(len=*), intent(in)    :: section
        character(len=*), intent(in)    :: key
        integer,          allocatable   :: inds(:)
        real,             allocatable   :: classres(:)
        type(image)                     :: clsstk, thumbimg
        character(len=LONGSTRLEN)       :: cavgs, cwd
        integer                         :: ncls, i, n, ldim_stk(3), ldim_thumb(3), classes(10), nptcls
        call simple_getcwd(cwd)
        cavgs = trim(adjustl(cwd)) // '/' // trim(CAVGS_ITER_FBODY) // int2str_pad(last_iter,3) // '.mrc'
        if(.not. oris2D%isthere("res")) return
        if(.not. file_exists(trim(adjustl(cavgs)))) return
        ncls = oris2D%get_noris()
        if(ncls <= 0) return
        allocate(inds(ncls))
        allocate(classres(ncls))
        classres = 0.0
        do i=1,ncls
            classres(i) = real(oris2D%get(i, 'res'))
        end do
        inds = (/(i,i=1,ncls)/)
        call hpsort(classres, inds)
        classes = 0
        n = 1
        do i=1, ncls
            if(n .gt. 10) exit
            if(oris2D%get_state(inds(i)) .gt. 0.0) then
                classes(n) = inds(i)
                n = n + 1
            end if
        end do 
        call find_ldim_nptcls(trim(adjustl(cavgs)), ldim_stk, nptcls)
        ldim_thumb(1) = ldim_stk(1) * 5
        ldim_thumb(2) = ldim_stk(2) * 2
        ldim_thumb(3) = 1
        ldim_stk(3) = 1
        call clsstk%new(ldim_stk, 1.0)
        call thumbimg%new(ldim_thumb, 1.0)
        do i=1, 5
            if(classes(i) .gt. 0) then
                call clsstk%read(trim(adjustl(cavgs)), classes(i))
                call thumbimg%tile(clsstk, i, 1)
            endif
        end do
        do i=6, 10
            if(classes(i) .gt. 0) then
                call clsstk%read(trim(adjustl(cavgs)), classes(i))
                call thumbimg%tile(clsstk, i - 5, 2)
            endif
        end do
        call thumbimg%write_jpg(CLUSTER2D_ITER_THUMB)
        call self%set(section, key, trim(adjustl(cwd)) // '/' // CLUSTER2D_ITER_THUMB, thumbnail = .true.)
        call thumbimg%kill()
        call clsstk%kill()
        if(allocated(inds)) deallocate(inds)
        if(allocated(classres)) deallocate(classres)
    end subroutine generate_2D_thumbnail

    subroutine generate_2D_jpeg( self, section, key, oris2D, last_iter, smpd )
        class(guistats),  intent(inout) :: self
        type(oris),       intent(inout) :: oris2D
        integer,          intent(in)    :: last_iter
        character(len=*), intent(in)    :: section
        character(len=*), intent(in)    :: key
        real,             intent(in)    :: smpd
        type(image)                     :: clsstk, img
        character(len=LONGSTRLEN)       :: cavgs, cwd
        integer                         :: ncls, i, n, ldim_stk(3), ldim_img(3), nptcls
        call simple_getcwd(cwd)
        cavgs = trim(adjustl(cwd)) // '/' // trim(CAVGS_ITER_FBODY) // int2str_pad(last_iter,3) // '.mrc'
        if(.not. file_exists(trim(adjustl(cavgs)))) return
        ncls = oris2D%get_noris()
        if(ncls <= 0) return
        call find_ldim_nptcls(trim(adjustl(cavgs)), ldim_stk, nptcls)
        ldim_img(1) = ldim_stk(1)
        ldim_img(2) = ldim_stk(2) * ldim_stk(3)
        ldim_img(3) = 1
        ldim_stk(3) = 1
        call clsstk%new(ldim_stk, 1.0)
        call img%new(ldim_img, 1.0)
        do i=1, ncls 
            call clsstk%read(trim(adjustl(cavgs)), i)
            call img%tile(clsstk, 1, i) 
        end do
        call img%write_jpg(trim(CAVGS_ITER_FBODY) // int2str_pad(last_iter,3) // '.jpg')
        call self%set(section, key, trim(adjustl(cwd)) // '/' // trim(CAVGS_ITER_FBODY) // int2str_pad(last_iter,3) // '.jpg', thumbnail = .true., box = real(ldim_stk(1)), smpd = smpd)
        call img%kill()
        call clsstk%kill()
    end subroutine generate_2D_jpeg

end module simple_guistats
