program simple_test_cavg_kpca
include 'simple_lib.f08'
use simple_cmdline,            only: cmdline
use simple_builder,            only: builder
use simple_parameters,         only: parameters
use simple_image,              only: image
use simple_strategy2D3D_common, only: discrete_read_imgbatch, prepimgbatch
use simple_ctf,                 only: ctf
use simple_fsc,                 only: plot_fsc
implicit none
#include "simple_local_flags.inc"
type(builder)        :: build
type(parameters)     :: p
type(cmdline)        :: cline
type(ctf)            :: tfun
type(ctfparams)      :: ctfvars
type(image)          :: ctfimg, rotimg, rotctfimg, cavg, rho
type(image)          :: even_cavg, even_rho, odd_cavg, odd_rho
real,    allocatable :: res(:), frc(:)
integer, allocatable :: pinds(:)
character(len=:), allocatable :: last_prev_dir
complex :: fcompl, fcompll
real    :: shift(2), mat(2,2), dist(2), loc(2), e3, kw, sdev, tval
integer :: logi_lims(3,2), cyc_lims(3,2), cyc_limsR(2,2), win_corner(2), phys(2)
integer :: i,pop,h,k,l,ll,m,mm, iptcl, eo, filtsz, neven, nodd, idir
logical :: l_ctf, l_phaseplate
! call cline%set('prg','cluster2D')
if( command_argument_count() < 4 )then
    write(logfhandle,'(a)') 'Usage: simple_test_cavg_kpca smpd=xx nthr=yy stk=stk.mrc'
    stop
else
    call cline%parse_oldschool
endif
call cline%checkvar('projfile',1)
call cline%checkvar('nthr',    2)
call cline%checkvar('class',   3)
call cline%checkvar('mskdiam', 4)
call cline%set('mkdir',  'yes')
call cline%set('oritype','ptcl2D')
call cline%check
!!!!!!! Hacky, only for test program convenience
idir = find_next_int_dir_prefix(PATH_HERE, last_prev_dir)
call cline%set('exec_dir', int2str(idir)//'_test_cavg_kpca')
call cline%set('projfile',trim(PATH_PARENT)//trim(cline%get_carg('projfile')))
if(cline%defined('stk')) call cline%set('stk',trim(PATH_PARENT)//trim(cline%get_carg('stk')))
call simple_mkdir( filepath(PATH_HERE, trim(cline%get_carg('exec_dir'))))
call simple_chdir( filepath(PATH_HERE, trim(cline%get_carg('exec_dir'))))
!!!!!!!
call build%init_params_and_build_general_tbox(cline, p, do3d=.false.)
call build%spproj_field%get_pinds(p%class, 'class', pinds)
pop = size(pinds)
if( pop == 0 ) THROW_HARD('Empty class!')
l_ctf        = build%spproj%get_ctfflag(p%oritype,iptcl=pinds(1)).ne.'no'
l_phaseplate = .false.
if( l_ctf ) l_phaseplate = build%spproj%has_phaseplate(p%oritype)
call prepimgbatch(pop)
logi_lims      = build%imgbatch(1)%loop_lims(2)
cyc_lims       = build%imgbatch(1)%loop_lims(3)
cyc_limsR(:,1) = cyc_lims(1,:)
cyc_limsR(:,2) = cyc_lims(2,:)
call ctfimg%copy(build%imgbatch(1))
call rotctfimg%copy(build%imgbatch(1))
call even_cavg%copy(build%imgbatch(1))
call odd_cavg%copy(even_cavg)
call even_rho%copy(even_cavg)
call odd_rho%copy(even_cavg)
call even_cavg%zero_and_flag_ft
call odd_cavg%zero_and_flag_ft
call even_rho%zero_and_flag_ft
call odd_rho%zero_and_flag_ft
neven = 0
nodd  = 0
if( cline%defined('stk') )then
    ! reading particles from inputted stk
    do i = 1,pop
        call progress_gfortran(i, pop)
        iptcl = pinds(i)
        e3    = build%spproj_field%e3get(iptcl)
        eo    = build%spproj_field%get_eo(iptcl)
        if( eo ==0 )then
            neven = neven + 1
        else
            nodd = nodd + 1
        endif
        call rotctfimg%zero_and_flag_ft
        call build%imgbatch(i)%read(p%stk,i)
        call build%imgbatch(i)%fft
        ! CTF rotation
        if( l_ctf )then
            ctfvars     = build%spproj%get_ctfparams(p%oritype,iptcl)
            tfun        = ctf(p%smpd, ctfvars%kv, ctfvars%cs, ctfvars%fraca)
            if( l_phaseplate )then
                call tfun%ctf2img(ctfimg, ctfvars%dfx, ctfvars%dfy, ctfvars%angast, ctfvars%phshift )
            else
                call tfun%ctf2img(ctfimg, ctfvars%dfx, ctfvars%dfy, ctfvars%angast)
            endif
            call rotmat2d(-e3, mat)
            do h = logi_lims(1,1),logi_lims(1,2)
                do k = logi_lims(2,1),logi_lims(2,2)
                    ! Rotation
                    loc        = matmul(real([h,k]),mat)
                    win_corner = floor(loc) ! bottom left corner
                    dist       = loc - real(win_corner)
                    ! Bi-linear interpolation
                    l     = cyci_1d(cyc_limsR(:,1), win_corner(1))
                    ll    = cyci_1d(cyc_limsR(:,1), win_corner(1)+1)
                    m     = cyci_1d(cyc_limsR(:,2), win_corner(2))
                    mm    = cyci_1d(cyc_limsR(:,2), win_corner(2)+1)
                    ! l, bottom left corner
                    phys   = build%imgbatch(i)%comp_addr_phys(l,m)
                    kw     = (1.-dist(1))*(1.-dist(2))   ! interpolation kernel weight
                    tval   = kw * ctfimg%get_cmat_at(phys(1), phys(2),1)
                    ! l, bottom right corner
                    phys   = build%imgbatch(i)%comp_addr_phys(l,mm)
                    kw     = (1.-dist(1))*dist(2)
                    tval   = tval   + kw * ctfimg%get_cmat_at(phys(1), phys(2),1)
                    ! ll, upper left corner
                    phys    = build%imgbatch(i)%comp_addr_phys(ll,m)
                    kw      = dist(1)*(1.-dist(2))
                    tval    = tval  + kw * ctfimg%get_cmat_at(phys(1), phys(2),1)
                    ! ll, upper right corner
                    phys    = build%imgbatch(i)%comp_addr_phys(ll,mm)
                    kw      = dist(1)*dist(2)
                    tval    = tval    + kw * ctfimg%get_cmat_at(phys(1), phys(2),1)
                    ! update with interpolated values
                    phys = build%imgbatch(i)%comp_addr_phys(h,k)
                    call rotctfimg%set_cmat_at(phys(1),phys(2),1, cmplx(tval*tval,0.))
                end do
            end do
        else
            rotctfimg = cmplx(1.,0.)
        endif
        if( eo == 0 )then
            call even_cavg%add(build%imgbatch(i))
            call even_rho%add(rotctfimg)
        else
            call odd_cavg%add(build%imgbatch(i))
            call odd_rho%add(rotctfimg)
        endif
    enddo
else
    call discrete_read_imgbatch(pop, pinds(:), [1,pop] )
    call rotimg%copy(build%imgbatch(1))
    do i = 1,pop
        call progress_gfortran(i,pop)
        iptcl = pinds(i)
        shift = build%spproj_field%get_2Dshift(iptcl)
        e3    = build%spproj_field%e3get(iptcl)
        eo    = build%spproj_field%get_eo(iptcl)
        call rotimg%zero_and_flag_ft
        call rotctfimg%zero_and_flag_ft
        if( eo ==0 )then
            neven = neven + 1
        else
            nodd = nodd + 1
        endif
        ! normalisation
        call build%imgbatch(i)%norm_noise(build%lmsk, sdev)
        ! shift
        call build%imgbatch(i)%fft
        call build%imgbatch(i)%shift2Dserial(-shift)
        ! ctf
        if( l_ctf )then
            ctfvars     = build%spproj%get_ctfparams(p%oritype,iptcl)
            tfun        = ctf(p%smpd, ctfvars%kv, ctfvars%cs, ctfvars%fraca)
            if( l_phaseplate )then
                call tfun%ctf2img(ctfimg, ctfvars%dfx, ctfvars%dfy, ctfvars%angast, ctfvars%phshift )
            else
                call tfun%ctf2img(ctfimg, ctfvars%dfx, ctfvars%dfy, ctfvars%angast)
            endif
            call build%imgbatch(i)%mul(ctfimg)
        else
            rotctfimg = cmplx(1.,0.)
        endif
        ! particle & ctf rotations
        call rotmat2d(-e3, mat)
        do h = logi_lims(1,1),logi_lims(1,2)
            do k = logi_lims(2,1),logi_lims(2,2)
                ! Rotation
                loc        = matmul(real([h,k]),mat)
                win_corner = floor(loc) ! bottom left corner
                dist       = loc - real(win_corner)
                ! Bi-linear interpolation
                l     = cyci_1d(cyc_limsR(:,1), win_corner(1))
                ll    = cyci_1d(cyc_limsR(:,1), win_corner(1)+1)
                m     = cyci_1d(cyc_limsR(:,2), win_corner(2))
                mm    = cyci_1d(cyc_limsR(:,2), win_corner(2)+1)
                ! l, bottom left corner
                phys   = build%imgbatch(i)%comp_addr_phys(l,m)
                kw     = (1.-dist(1))*(1.-dist(2))   ! interpolation kernel weight
                fcompl = kw * build%imgbatch(i)%get_cmat_at(phys(1), phys(2),1)
                if( l_ctf ) tval   = kw * real(ctfimg%get_cmat_at(phys(1), phys(2),1))
                ! l, bottom right corner
                phys   = build%imgbatch(i)%comp_addr_phys(l,mm)
                kw     = (1.-dist(1))*dist(2)
                fcompl = fcompl + kw * build%imgbatch(i)%get_cmat_at(phys(1), phys(2),1)
                if( l_ctf ) tval   = tval   + kw * real(ctfimg%get_cmat_at(phys(1), phys(2),1))
                if( l < 0 ) fcompl = conjg(fcompl) ! conjugation when required!
                ! ll, upper left corner
                phys    = build%imgbatch(i)%comp_addr_phys(ll,m)
                kw      = dist(1)*(1.-dist(2))
                fcompll =         kw * build%imgbatch(i)%get_cmat_at(phys(1), phys(2),1)
                if( l_ctf ) tval    = tval  + kw * real(ctfimg%get_cmat_at(phys(1), phys(2),1))
                ! ll, upper right corner
                phys    = build%imgbatch(i)%comp_addr_phys(ll,mm)
                kw      = dist(1)*dist(2)
                fcompll = fcompll + kw * build%imgbatch(i)%get_cmat_at(phys(1), phys(2),1)
                if( l_ctf ) tval    = tval    + kw * real(ctfimg%get_cmat_at(phys(1), phys(2),1))
                if( ll < 0 ) fcompll = conjg(fcompll) ! conjugation when required!
                ! update with interpolated values
                phys = build%imgbatch(i)%comp_addr_phys(h,k)
                call rotimg%set_cmat_at(phys(1),phys(2),1, fcompl + fcompll)
                if( l_ctf ) call rotctfimg%set_cmat_at(phys(1),phys(2),1, cmplx(tval*tval,0.))
            end do
        end do
        if( eo == 0 )then
            call even_cavg%add(rotimg)
            call even_rho%add(rotctfimg)
        else
            call odd_cavg%add(rotimg)
            call odd_rho%add(rotctfimg)
        endif
        ! write
        call rotimg%ifft
        call rotimg%write(p%outstk,i)
    enddo
endif
! deconvolutions
call cavg%copy(even_cavg)
call cavg%add(odd_cavg)
call rho%copy(even_rho)
call rho%add(odd_rho)
if( neven > 0 ) call even_cavg%ctf_dens_correct(even_rho)
if( nodd > 0 )  call odd_cavg%ctf_dens_correct(odd_rho)
call cavg%ctf_dens_correct(rho)
! write w/o drift correction (e/o merging)
call even_cavg%ifft
call odd_cavg%ifft
call cavg%ifft
call even_cavg%write('cavg_even.mrc')
call odd_cavg%write('cavg_odd.mrc')
call cavg%write('cavg.mrc')
! frc
if( neven>0 .and. nodd>0 )then
    filtsz = even_cavg%get_filtsz()
    allocate(frc(filtsz))
    res = even_cavg%get_res()
    call even_cavg%mask(p%msk,'soft',backgr=0.)
    call odd_cavg%mask(p%msk,'soft',backgr=0.)
    call even_cavg%fft()
    call odd_cavg%fft()
    call even_cavg%fsc(odd_cavg, frc)
    call plot_fsc(filtsz, frc, res, p%smpd, 'frc')
endif
end program simple_test_cavg_kpca
