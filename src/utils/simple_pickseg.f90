module simple_pickseg
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_parameters,   only: params_glob
use simple_image,        only: image
use simple_tvfilter,     only: tvfilter
use simple_segmentation, only: otsu_robust_fast, otsu_img
use simple_binimage,     only: binimage
implicit none

public :: read_mic_raw, pickseg
private
#include "simple_local_flags.inc"

! class constants
real,             parameter :: SHRINK    = 4.
! real,             parameter :: lp        = 10. params_glob%lp
real,             parameter :: LAMBDA    = 3.
! real,             parameter :: nsig      = 1.5 params_glob%nsig
logical, parameter :: L_WRITE  = .true.
logical, parameter :: L_DEBUG  = .false.

! class variables
integer                       :: ldim_raw(3)
real                          :: smpd_raw
type(image)                   :: mic_raw
character(len=:), allocatable :: fbody

! instance
type pickseg
    private
    real                 :: smpd_shrink = 0.
    integer              :: ldim(3), ldim_box(3), nboxes = 0, box_raw = 0
    type(binimage)       :: mic_shrink, img_cc
    type(stats_struct)   :: sz_stats, diam_stats
    logical              :: exists = .false.
contains
    procedure :: pick
end type pickseg

contains

    subroutine read_mic_raw( micname )
        character(len=*), intent(in) :: micname !< micrograph file name
        character(len=:), allocatable :: ext
        integer :: nframes
        ! set micrograph info
        call find_ldim_nptcls(micname, ldim_raw, nframes, smpd_raw)
        if( ldim_raw(3) /= 1 .or. nframes /= 1 ) THROW_HARD('Only for 2D images')
        ! read micrograph
        call mic_raw%new(ldim_raw, smpd_raw)
        call mic_raw%read(micname)
        ! set fbody
        ext   = fname2ext(trim(micname))
        fbody = trim(get_fbody(basename(trim(micname)), ext))
    end subroutine read_mic_raw

    subroutine pick( self )
        class(pickseg), intent(inout) :: self
        type(tvfilter)       :: tvf
        type(image)          :: img_win
        real,    allocatable :: diams(:)
        integer, allocatable :: sz(:)
        real    :: px(3), otsu_t
        integer :: i, boxcoord(2), sz_max, sz_min
        logical :: outside
        ! shrink micrograph
        self%ldim(1)     = round2even(real(ldim_raw(1))/SHRINK)
        self%ldim(2)     = round2even(real(ldim_raw(2))/SHRINK)
        self%ldim(3)     = 1
        self%smpd_shrink = smpd_raw * SHRINK
        call mic_raw%mul(real(product(ldim_raw))) ! to prevent numerical underflow when performing FFT
        call mic_raw%fft
        call self%mic_shrink%new_bimg(self%ldim, self%smpd_shrink)
        call self%mic_shrink%set_ft(.true.)
        call mic_raw%clip(self%mic_shrink)
        select case(trim(params_glob%pcontrast))
            case('black')
                ! flip contrast (assuming black particle contrast on input)
                call self%mic_shrink%mul(-1.)
            case('white')
                ! nothing to do
            case DEFAULT
                THROW_HARD('uknown pcontrast parameter, use (black|white)')
        end select
        ! low-pass filter micrograph
        call self%mic_shrink%bp(0., params_glob%lp)
        call self%mic_shrink%ifft
        call mic_raw%ifft
        if( L_WRITE ) call self%mic_shrink%write('mic_shrink_lp.mrc')
        ! TV denoising
        call tvf%new()
        call tvf%apply_filter(self%mic_shrink, LAMBDA)
        call tvf%kill
        if( L_WRITE ) call self%mic_shrink%write('mic_shrink_lp_tv.mrc')
        call otsu_img(self%mic_shrink, otsu_t)
        call self%mic_shrink%set_imat
        if( L_WRITE ) call self%mic_shrink%write_bimg('mic_shrink_lp_tv_bin.mrc')
        call self%mic_shrink%erode
        call self%mic_shrink%erode
        if( L_WRITE ) call self%mic_shrink%write_bimg('mic_shrink_lp_tv_bin_erode.mrc')
        ! identify connected components
        call self%mic_shrink%find_ccs(self%img_cc)
        if( L_WRITE ) call self%img_cc%write_bimg('mic_shrink_lp_tv_bin_erode_cc.mrc')
        call self%img_cc%get_nccs(self%nboxes)  
        ! eliminate connected components that are too large or too small
        sz = self%img_cc%size_ccs()
        call calc_stats(real(sz), self%sz_stats)
        if( L_DEBUG )then
            print *, 'nboxes before elimination: ', self%nboxes
            print *, 'avg size: ', self%sz_stats%avg
            print *, 'med size: ', self%sz_stats%med
            print *, 'sde size: ', self%sz_stats%sdev
            print *, 'min size: ', self%sz_stats%minv
            print *, 'max size: ', self%sz_stats%maxv
        endif
        sz_min = nint(self%sz_stats%avg - params_glob%nsig * self%sz_stats%sdev)
        sz_max = nint(self%sz_stats%avg + params_glob%nsig * self%sz_stats%sdev)
        call self%img_cc%elim_ccs([sz_min,sz_max])
        call self%img_cc%get_nccs(self%nboxes)
        
        sz = self%img_cc%size_ccs()
        call calc_stats(real(sz), self%sz_stats)
        if( L_DEBUG )then
            print *, 'nboxes after  elimination: ', self%nboxes
            print *, 'avg size: ', self%sz_stats%avg
            print *, 'med size: ', self%sz_stats%med
            print *, 'sde size: ', self%sz_stats%sdev
            print *, 'min size: ', self%sz_stats%minv
            print *, 'max size: ', self%sz_stats%maxv
        endif
        allocate(diams(self%nboxes), source=0.)
        call calc_stats(diams, self%diam_stats)
        do i = 1, self%nboxes
            call self%img_cc%diameter_cc(i, diams(i))
        end do
        call calc_stats(diams, self%diam_stats)
        print *, 'avg diam: ', self%diam_stats%avg
        print *, 'med diam: ', self%diam_stats%med
        print *, 'sde diam: ', self%diam_stats%sdev
        print *, 'min diam: ', self%diam_stats%minv
        print *, 'max diam: ', self%diam_stats%maxv
        self%box_raw = find_magic_box(2 * nint(self%diam_stats%med/smpd_raw))
        call img_win%new([self%box_raw,self%box_raw,1], smpd_raw)
        do i = 1, self%nboxes
            px       = center_mass_cc(i)
            boxcoord = nint((real(SHRINK)*px(1:2))-real(self%box_raw)/2.)
            call mic_raw%window_slim(boxcoord, self%box_raw, img_win, outside)
            call img_win%write('extracted.mrc', i)
        end do

        contains

            function center_mass_cc( i_cc ) result( px )
                integer, intent(in) :: i_cc
                real :: px(3)
                integer, allocatable :: pos(:,:)
                integer, allocatable :: imat_cc(:,:,:)
                imat_cc = int(self%img_cc%get_rmat())
                where(imat_cc .ne. i_cc) imat_cc = 0
                call get_pixel_pos(imat_cc,pos)
                px(1) = sum(pos(1,:))/real(size(pos,dim = 2))
                px(2) = sum(pos(2,:))/real(size(pos,dim = 2))
                px(3) = 1.
                if(allocated(imat_cc)) deallocate(imat_cc)
            end function center_mass_cc

    end subroutine pick

end module simple_pickseg