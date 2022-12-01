module simple_euclid_sigma2
include 'simple_lib.f08'
use simple_parameters,       only: params_glob
use simple_cartft_corrcalc,  only: cartft_corrcalc, cftcc_glob
use simple_polarft_corrcalc, only: polarft_corrcalc, pftcc_glob
use simple_sigma2_binfile,   only: sigma2_binfile
use simple_starfile_wrappers
implicit none

public :: euclid_sigma2, eucl_sigma2_glob, write_groups_starfile
private
#include "simple_local_flags.inc"

type euclid_sigma2
    private
    real,    allocatable, public  :: sigma2_noise(:,:)      !< the sigmas for alignment & reconstruction (from groups)
    real,    allocatable          :: sigma2_part(:,:)       !< the actual sigmas per particle (this part only)
    real,    allocatable          :: sigma2_groups(:,:,:)   !< sigmas for groups
    integer, allocatable          :: pinds(:)
    integer, allocatable          :: micinds(:)
    integer                       :: fromp
    integer                       :: top
    integer                       :: kfromto(2) = 0
    integer                       :: pftsz      = 0
    character(len=:), allocatable :: binfname
    logical                       :: exists     = .false.

contains
    ! constructor
    procedure          :: new
    ! utils
    procedure          :: write_info
    ! I/O
    procedure          :: read_part
    procedure          :: read_groups
    procedure, private :: calc_sigma2_1, calc_sigma2_2
    generic            :: calc_sigma2 => calc_sigma2_1, calc_sigma2_2
    procedure          :: write_sigma2
    procedure, private :: read_groups_starfile
    ! destructor
    procedure          :: kill_ptclsigma2
    procedure          :: kill
end type euclid_sigma2

class(euclid_sigma2), pointer :: eucl_sigma2_glob => null()

contains

    ! TYPE euclid_sigma2

    subroutine new( self, binfname, box )
        ! read individual sigmas from binary file, to be modified at the end of the iteration
        ! read group sigmas from starfile, to be used for alignment and volume reconstruction
        ! set up fields for fast access to sigmas
        class(euclid_sigma2), target, intent(inout) :: self
        character(len=*),             intent(in)    :: binfname
        integer,                      intent(in)    :: box
        call self%kill
        self%kfromto = [1, fdim(box)-1]
        allocate( self%sigma2_noise(self%kfromto(1):self%kfromto(2),params_glob%fromp:params_glob%top),&
                  self%pinds(params_glob%fromp:params_glob%top) )
        if( associated(pftcc_glob) )then
            call pftcc_glob%assign_sigma2_noise(self%sigma2_noise)
            call pftcc_glob%assign_pinds(self%pinds)
        endif
        if( associated(cftcc_glob) )then
            call cftcc_glob%assign_sigma2_noise(self%sigma2_noise)
            call cftcc_glob%assign_pinds(self%pinds)
        endif
        self%binfname         = trim(binfname)
        self%fromp            = params_glob%fromp
        self%top              = params_glob%top
        self%sigma2_noise     = 0.
        self%exists           = .true.
        eucl_sigma2_glob      => self
    end subroutine new

    subroutine write_info(self)
        class(euclid_sigma2), intent(in) :: self
        write(logfhandle,*) 'kfromto: ',self%kfromto
        write(logfhandle,*) 'fromp:   ',self%fromp
        write(logfhandle,*) 'top:     ',self%top
    end subroutine write_info

    ! I/O

    subroutine read_part( self, os, ptcl_mask )
        class(euclid_sigma2), intent(inout) :: self
        class(oris),          intent(inout) :: os
        logical,              intent(in)    :: ptcl_mask(params_glob%fromp:params_glob%top)
        type(sigma2_binfile) :: binfile
        call binfile%new_from_file(self%binfname)
        call binfile%read(self%sigma2_part)
    end subroutine read_part

    subroutine read_groups( self, os, ptcl_mask )
        class(euclid_sigma2), intent(inout) :: self
        class(oris),          intent(inout) :: os
        logical,              intent(in)    :: ptcl_mask(params_glob%fromp:params_glob%top)
        integer                             :: iptcl, igroup, ngroups, eo
        if( associated(pftcc_glob) ) call pftcc_glob%assign_pinds(self%pinds)
        if( associated(cftcc_glob) ) call cftcc_glob%assign_pinds(self%pinds)
        call self%read_groups_starfile( params_glob%which_iter, self%sigma2_groups, ngroups )
        ! copy group sigmas to particles
        do iptcl = params_glob%fromp, params_glob%top
            igroup  = nint(os%get(iptcl, 'stkind'))
            eo      = nint(os%get(iptcl, 'eo'    )) ! 0/1
            self%sigma2_noise(:,iptcl) = self%sigma2_groups(eo+1,igroup,:)
        end do
    end subroutine read_groups

    !>  Calculates and updates sigma2 within search resolution range
    subroutine calc_sigma2_1( self, pftcc, iptcl, o, refkind )
        class(euclid_sigma2),    intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        class(ori),              intent(in)    :: o
        character(len=*),        intent(in)    :: refkind ! 'proj' or 'class'
        integer :: iref, irot
        real    :: sigma_contrib(params_glob%kfromto(1):params_glob%kfromto(2))
        real    :: shvec(2)
        if ( o%isstatezero() ) return
        shvec = o%get_2Dshift()
        iref  = nint(o%get(trim(refkind)))
        irot  = pftcc_glob%get_roind(360. - o%e3get())
        call pftcc%gencorr_sigma_contrib(iref, iptcl, shvec, irot, sigma_contrib)
        self%sigma2_part(params_glob%kfromto(1):params_glob%kfromto(2),iptcl) = sigma_contrib
    end subroutine calc_sigma2_1

        !>  Calculates and updates sigma2 within search resolution range
    subroutine calc_sigma2_2( self, cftcc, iptcl, o, refkind )
        class(euclid_sigma2),   intent(inout) :: self
        class(cartft_corrcalc), intent(inout) :: cftcc
        integer,                intent(in)    :: iptcl
        class(ori),             intent(in)    :: o
        character(len=*),       intent(in)    :: refkind ! 'proj' or 'class'
        real                 :: sigma_contrib(params_glob%kfromto(1):params_glob%kfromto(2))
        real                 :: shvec(2)
        if ( o%isstatezero() ) return
        shvec = o%get_2Dshift()
        call cftcc%calc_sigma_contrib(iptcl, o, shvec, sigma_contrib)
        self%sigma2_part(params_glob%kfromto(1):params_glob%kfromto(2),iptcl) = sigma_contrib
    end subroutine calc_sigma2_2

    subroutine write_sigma2( self )
        class(euclid_sigma2), intent(inout) :: self
        type(sigma2_binfile)                :: binfile
        call binfile%new_from_file(self%binfname)
        call binfile%write(self%sigma2_part)
        call binfile%kill
    end subroutine write_sigma2

    ! destructor

    subroutine kill_ptclsigma2( self )
        class(euclid_sigma2), intent(inout) :: self
        if( allocated(self%sigma2_noise) ) deallocate(self%sigma2_noise)
    end subroutine kill_ptclsigma2

    subroutine kill( self )
        class(euclid_sigma2), intent(inout) :: self
        if( self%exists )then
            call self%kill_ptclsigma2
            if(allocated(self%pinds))             deallocate(self%pinds)
            if(allocated(self%micinds))           deallocate(self%micinds)
            self%kfromto      = 0
            self%fromp        = -1
            self%top          = -1
            self%exists       = .false.
            eucl_sigma2_glob  => null()
        endif
    end subroutine kill

    subroutine write_groups_starfile( fname, group_pspecs, ngroups )
        character(len=:), allocatable, intent(in) :: fname
        real, allocatable,             intent(in) :: group_pspecs(:,:,:)
        integer,                       intent(in) :: ngroups
        character(len=:), allocatable :: stmp
        integer                       :: eo, igroup, idx
        type(starfile_table_type)     :: ostar
        call starfile_table__new(ostar)
        call starfile_table__open_ofile(ostar, fname)
        ! global fields
        call starfile_table__addObject(ostar)
        call starfile_table__setIsList(ostar, .false.)
        call starfile_table__setname(ostar, "general")
        call starfile_table__setValue_int(ostar, EMDL_MLMODEL_NR_GROUPS, ngroups)
        call starfile_table__write_ofile(ostar)
        ! values
        do eo = 1, 2
            if( eo == 1 )then
                stmp = 'even'
            else
                stmp = 'odd'
            end if
            do igroup = 1, ngroups
                call starfile_table__clear(ostar)
                call starfile_table__setComment(ostar, stmp // ', group ' // trim(int2str(igroup)) )
                call starfile_table__setName(ostar, trim(int2str(eo)) // '_group_' // trim(int2str(igroup)) )
                call starfile_table__setIsList(ostar, .false.)
                do idx = lbound(group_pspecs,3), ubound(group_pspecs, 3)
                    call starfile_table__addObject(ostar)
                    call starfile_table__setValue_int(ostar,    EMDL_SPECTRAL_IDX, idx)
                    call starfile_table__setValue_double(ostar, EMDL_MLMODEL_SIGMA2_NOISE,&
                        real(group_pspecs(eo,igroup,idx),dp) )
                end do
                call starfile_table__write_ofile(ostar)
            end do
        end do
        call starfile_table__close_ofile(ostar)
        call starfile_table__delete(ostar)
    end subroutine write_groups_starfile

    subroutine read_groups_starfile( self, iter, group_pspecs, ngroups )
        class(euclid_sigma2),          intent(inout) :: self
        integer,                       intent(in)    :: iter
        real,             allocatable, intent(out)   :: group_pspecs(:,:,:)
        integer,                       intent(out)    :: ngroups
        type(str4arr),    allocatable :: names(:)
        type(starfile_table_type)     :: istarfile
        character(len=:), allocatable :: starfile_fname
        character                     :: eo_char
        real(dp)                      :: val
        integer(C_long)               :: num_objs, object_id
        integer                       :: stat, spec_idx, eo, igroup, idx
        logical                       :: l
        starfile_fname = trim(SIGMA2_GROUP_FBODY) // trim(int2str(iter)) // '.star'
        call starfile_table__new(istarfile)
        if (.not. file_exists(starfile_fname)) then
            THROW_HARD('euclid_sigma2_starfile: read_groups_pspecs; file does not exists: ' // starfile_fname)
        end if
        ! read header
        call starfile_table__getnames(istarfile, starfile_fname, names)
        call starfile_table__read( istarfile, starfile_fname, names(1)%str )
        l         = starfile_table__getValue_int(istarfile, EMDL_MLMODEL_NR_GROUPS, ngroups)
        object_id = starfile_table__nextobject(istarfile)
        ! read values
        allocate(group_pspecs(2,ngroups,self%kfromto(1):self%kfromto(2)))
        call starfile_table__getnames(istarfile, starfile_fname, names)
        do idx = 1, size(names)
            if( len(names(idx)%str) < len('1_group_')+1 )cycle
            if( names(idx)%str(2:8) .ne. '_group_' ) cycle
            eo_char = names(idx)%str(1:1)
            if ((eo_char .ne. '1').and.(eo_char .ne. '2')) cycle
            eo = 1
            if (eo_char == '2') eo = 2
            call str2int( names(idx)%str(9:len_trim(names(idx)%str)), stat, igroup )
            if( stat > 0 ) cycle
            if( (igroup < 1).or.(igroup>ngroups) ) cycle
            call starfile_table__read( istarfile, starfile_fname, names(idx)%str )
            object_id = starfile_table__firstobject(istarfile)
            num_objs  = starfile_table__numberofobjects(istarfile)
            do while( (object_id < num_objs) .and. (object_id >= 0) )
                l = starfile_table__getValue_int(istarfile, EMDL_SPECTRAL_IDX, spec_idx)
                if( l ) then
                    l = starfile_table__getValue_double(istarfile, EMDL_MLMODEL_SIGMA2_NOISE, val)
                    if( l ) then
                        if( (spec_idx >= self%kfromto(1)).and.(spec_idx <= self%kfromto(2)) ) then
                            group_pspecs(eo,igroup,spec_idx) = real(val)
                        end if
                    end if
                end if
                object_id = starfile_table__nextobject(istarfile)
            end do
        end do
        call starfile_table__delete(istarfile)
    end subroutine read_groups_starfile

end module simple_euclid_sigma2
