program simple_test_3D_core_finder
include 'simple_lib.f08'
use simple_image,        only: image
implicit none
#include "simple_local_flags.inc"
    
real,    parameter  :: smpd=0.358, np_rad_A=44.0, shell_size_A=1.0
real                :: suma, suma2, sumax, sumay

type(image)                 :: img_part1, img_part2
real(kind=c_float), pointer :: rmat_img_part1(:,:,:)=>null()
real(kind=c_float), pointer :: rmat_img_part2(:,:,:)=>null()
real                        :: np_rad_vox=np_rad_A/smpd, shell_size_vox=shell_size_A/smpd
real                        :: center(3), rad_core, rad_core_vox
character(len=256)          :: fn_img_part1, fn_img_part2
integer                     :: ldim1(3), ldim2(3), ldim_refs(3), ifoo, nshells, i, j, k, n
real                        :: r, mean, mean1, mean2
logical, allocatable        :: mask(:,:,:)

if( command_argument_count() /= 2 )then
    write(logfhandle,'(a)')  'Usage: simple_test_3D_core_finder vol_part1.mrc vol_part2.mrc radius_core'
    write(logfhandle,'(a)')  'vol_part1.mrc: 3D volumen density map of part1' 
    write(logfhandle,'(a)')  'vol_part2.mrc: 3D volumen density map of part2', NEW_LINE('a')
    stop
else
    call get_command_argument(1, fn_img_part1)
    call get_command_argument(2, fn_img_part2)
endif

! create and read in volumes
call find_ldim_nptcls(fn_img_part1, ldim1, ifoo)
call find_ldim_nptcls(fn_img_part2, ldim2, ifoo)
if( ldim1(1) /= ldim2(1) .or. ldim1(2) /= ldim2(2) .or. ldim1(3) /= ldim2(3) )then
    THROW_HARD('****Non-conforming dimensions of 3D density maps vol1 and vol2')
endif
ldim_refs = [ldim1(1), ldim1(2), ldim1(3)]
call img_part1%new(ldim_refs, smpd)
call img_part2%new(ldim_refs, smpd)
call img_part1%read(fn_img_part1)
call img_part2%read(fn_img_part2)
! allocations and parameter calculations
rad_core_vox  = rad_core/smpd
ldim_refs     = [ldim1(1), ldim1(2), ldim1(3)]
nshells       = int(np_rad_vox / shell_size_vox)
center        = ldim_refs(1:3) / 2 + 0.5
allocate(mask(ldim_refs(1), ldim_refs(2), ldim_refs(3)), source=.false.)

! remove negative values
call img_part1%get_rmat_ptr( rmat_img_part1 )
where( rmat_img_part1 < 0 ) rmat_img_part1 = 0.
call img_part2%get_rmat_ptr( rmat_img_part2 )
where( rmat_img_part2 < 0 ) rmat_img_part2 = 0.
! take averages of shells out to the NP radius
mean = 0.; mean1 = 0; mean2 = 0; suma=0; sumax =0; sumay =0
do n = 0, nshells
    mask = .false. ! for now use mask in case we want to calculate other stats in the future
    do i = 1, ldim_refs(1)
        do j = 1, ldim_refs(2)
            do k = 1, ldim_refs(3)
                r = sqrt(real( (i - center(1))**2 + (j - center(2))**2 + (k - center(3))**2 ) )
                if( r > n*shell_size_vox .and. r < (n+1)*shell_size_vox )then
                    mask(i,j,k) = .true.
                endif
            enddo
        enddo
    enddo
    mean1 = sum(abs(rmat_img_part1(:ldim1(1),:ldim1(2),:ldim1(3))), mask=mask) / count(mask)
    mean2 = sum(abs(rmat_img_part2(:ldim1(1),:ldim1(2),:ldim1(3))), mask=mask) / count(mask)
    mean  = (mean1 - mean2)
    suma = 0. ; suma2 = 0.
    do i = 1, ldim_refs(1)
        do j = 1, ldim_refs(2)
            do k = 1, ldim_refs(3)
                r = sqrt(real( (i - center(1))**2 + (j - center(2))**2 + (k - center(3))**2 ))
                if( r > n*shell_size_vox .and. r < (n+1)*shell_size_vox )then
                    suma  =  suma + (rmat_img_part1(i,j,k) - mean1 )*(rmat_img_part2(i,j,k) - mean2)
                    sumax = sumax + (rmat_img_part1(i,j,k) - mean1 )**2 
                    sumay = sumay + (rmat_img_part2(i,j,k) - mean2 )**2 
                endif
            enddo
        enddo
    enddo
    print *, n, suma/(sqrt(sumax)*sqrt(sumay)), mean 
enddo
call img_part1%kill()
call img_part2%kill()
end program simple_test_3D_core_finder

