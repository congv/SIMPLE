program simple_test_test
use simple_stack_io, only: stack_io
use simple_image,    only: image
implicit none

type(stack_io) :: stkio_r1, stkio_r2, stkio_w
type(image)    :: img1, img2, img
character(len=*), parameter :: stkname1 = 'reprojs.mrcs'
character(len=*), parameter :: stkname2 = 'start2Drefs.mrc'
real,             parameter :: smpd    = 1.72
integer :: nptcls, iptcl, ldim(3)

call stkio_r1%open(stkname1, smpd, 'read', bufsz=100)
call stkio_r2%open(stkname2, smpd, 'read', bufsz=100)
nptcls = stkio_r1%get_nptcls()
ldim   = stkio_r1%get_ldim()
call img%new(ldim, smpd)
call img1%new(ldim, smpd)
call img2%new(ldim, smpd)
! read
do iptcl = 1, nptcls
    call stkio_r1%read(iptcl, img1)
    call stkio_r2%read(iptcl, img2)
    img = img1 - img2
    call img%write('outstk_read.mrc', iptcl)
end do
call stkio_r1%close
call stkio_r2%close
end program simple_test_test
