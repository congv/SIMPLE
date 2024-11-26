program simple_test_common_lines
include 'simple_lib.f08'
use simple_cmdline,    only: cmdline
use simple_builder,    only: builder
use simple_parameters, only: parameters
use simple_image,      only: image
use simple_projector,  only: projector
implicit none
integer,          parameter   :: NPLANES = 100, ORI_IND = 15
character(len=:), allocatable :: cmd
type(fplan_map),  allocatable :: coord_map(:)
type(parameters)              :: p
type(cmdline)                 :: cline
type(image)                   :: vol, noise, fplane1, fplane2, fplane1_pad, fplane2_pad, fplanes(NPLANES)
type(oris)                    :: spiral
type(ori)                     :: o1, o2
type(projector)               :: vol_pad
integer                       :: ifoo, rc, errflg, i, ori_phys(3), target_phys(3), f_ind
real                          :: res_fsc05, res_fsc0143, ave, sdev, maxv, minv, med
logical                       :: mrc_exists
real                          :: vec(1,3), A(3,3), vec_A(1,3), A_inv(3,3), inv_vec_A(1,3)
if( command_argument_count() < 4 )then
    write(logfhandle,'(a)') 'ERROR! Usage: simple_test_3D_opt_filt smpd=xx nthr=yy vol1=volume.mrc mskdiam=zz'
    write(logfhandle,'(a)') 'Example: https://www.rcsb.org/structure/1jyx with smpd=1. mskdiam=180'
    write(logfhandle,'(a)') 'DEFAULT TEST (example above) is running now...'
    inquire(file="1JYX.mrc", exist=mrc_exists)
    if( .not. mrc_exists )then
        write(*, *) 'Downloading the example dataset...'
        cmd = 'curl -s -o 1JYX.pdb https://files.rcsb.org/download/1JYX.pdb'
        call execute_command_line(cmd, exitstat=rc)
        write(*, *) 'Converting .pdb to .mrc...'
        cmd = 'e2pdb2mrc.py 1JYX.pdb 1JYX.mrc'
        call execute_command_line(cmd, exitstat=rc)
        cmd = 'rm 1JYX.pdb'
        call execute_command_line(cmd, exitstat=rc)
    endif
    call cline%set('smpd'   , 1.)
    call cline%set('nthr'   , 16.)
    call cline%set('vol1'   , '1JYX.mrc')
    call cline%set('mskdiam', 180.)
else
    call cline%parse_oldschool
endif
call cline%checkvar('smpd',    1)
call cline%checkvar('nthr',    2)
call cline%checkvar('vol1',    3)
call cline%checkvar('mskdiam', 4)
call cline%check
call p%new(cline)
call find_ldim_nptcls(p%vols(1), p%ldim, ifoo)
call vol%new(p%ldim, p%smpd)
call noise%new(p%ldim, p%smpd)
call vol%read(p%vols(1))
call vol%stats('foreground', ave, sdev, maxv, minv)
! add noise in a small center region of the vol
call noise%gauran(0., 5. * sdev)
call noise%mask(p%msk, 'soft')
! call vol%add(noise)
! call vol%write('vol_noisy.mrc')
call spiral%new(NPLANES, is_ptcl=.false.)
call spiral%spiral
call fplane1%new([p%box, p%box, 1], p%smpd)
call fplane2%new([p%box, p%box, 1], p%smpd)
call vol_pad%new(    [p%boxpd, p%boxpd, p%boxpd], p%smpd)
call fplane1_pad%new([p%boxpd, p%boxpd, 1],       p%smpd)
call fplane2_pad%new([p%boxpd, p%boxpd, 1],       p%smpd)
call vol%pad(vol_pad)
call vol_pad%fft
call vol_pad%expand_cmat(p%alpha)
call spiral%get_ori(ORI_IND, o1)
call vol_pad%fproject(o1,fplane1_pad)
do i = 1, spiral%get_noris()
    call spiral%get_ori(i, o2)
    call fplanes(i)%new([p%boxpd, p%boxpd, 1], p%smpd)
    call vol_pad%fproject(o2,fplanes(i))
enddo
call vol_pad%fproject_map(ORI_IND, spiral, coord_map)
call fplane2_pad%zero_and_flag_ft
do i = 1, size(coord_map)
    ori_phys    = coord_map(i)%ori_phys
    target_phys = coord_map(i)%target_phys
    f_ind       = coord_map(i)%target_find
    call fplane2_pad%set_cmat_at(ori_phys, fplanes(f_ind)%get_cmat_at(target_phys))
enddo
call fplane1_pad%ifft
call fplane2_pad%ifft
call fplane1_pad%clip(fplane1)
call fplane2_pad%clip(fplane2)
call fplane1%write('fplane.mrc', 1)
call fplane2%write('fplane.mrc', 2)
! testing
A(1,:)   = [1., 2., 3.]
A(2,:)   = [4., 5., 6.]
A(3,:)   = [7., 9., 10.]
vec(1,:) = [1., 2., 0.]
vec_A = matmul(vec, A)
call matinv(A, A_inv, 3, errflg)
inv_vec_A = matmul(vec_A, A_inv)
end program simple_test_common_lines