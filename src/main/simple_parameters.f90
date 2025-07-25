! provides global distribution of constants and derived constants
module simple_parameters
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_cmdline,        only: cmdline
use simple_user_interface, only: simple_program, get_prg_ptr
use simple_atoms,          only: atoms
use simple_decay_funs
implicit none

public :: parameters, params_glob
private
#include "simple_local_flags.inc"

type :: parameters
    ! pointer 2 program UI
    type(simple_program), pointer :: ptr2prg => null()
    ! yes/no decision variables in ascending alphabetical order
    character(len=3)          :: acf='no'             !< calculate autocorrelation function(yes|no){no}
    character(len=3)          :: append='no'          !< append selection (yes|no){no}
    character(len=3)          :: async='no'           !< asynchronous (yes|no){no}
    character(len=3)          :: atom_thres='yes'     !< do atomic thresholding or not (yes|no){yes}
    character(len=3)          :: autoscale='no'       !< automatic down-scaling(yes|no){yes}
    character(len=3)          :: autosample='no'      !< automatic particles sampling scheme(yes|no){no}
    character(len=3)          :: avg='no'             !< calculate average (yes|no){no}
    character(len=3)          :: backgr_subtr='no'    !< Whether to perform micrograph background subtraction
    character(len=3)          :: balance='no'         !< Balance class populations to smallest selected
    character(len=3)          :: beamtilt='no'        !< use beamtilt values when generating optics groups
    character(len=3)          :: bin='no'             !< binarize image(yes|no){no}
    character(len=3)          :: cavg_ini='no'        !< use class averages for initialization(yes|no){no}
    character(len=3)          :: cavg_ini_ext='no'    !< use class averages for (external) initialization(yes|no){no}
    character(len=3)          :: cavgw='no'           !< use class averages weights during 3D ab initio(yes|no){no}
    character(len=3)          :: center='yes'         !< center image(s)/class average(s)/volume(s)(yes|no){no}
    character(len=3)          :: center_pdb='no'      !< move PDB atomic center to the center of the box(yes|no){no}
    character(len=3)          :: chunk='no'           !< indicates whether we are within a chunk(yes|no){no}
    character(len=3)          :: classtats='no'       !< calculate class population statistics(yes|no){no}
    character(len=3)          :: clear='no'           !< clear exising processing upon start (stream)
    character(len=3)          :: combine_eo='no'      !< Whether combined e/o volumes have been used for alignment(yes|no){no}
    character(len=3)          :: continue='no'        !< continue previous refinement(yes|no){no}
    character(len=3)          :: contsh='yes'         !< continuously shifting(yes|no){yes}
    character(len=3)          :: crowded='yes'        !< wheter picking is done in crowded micrographs or not (yes|no){yes}
    character(len=3)          :: ctfstats='no'        !< calculate ctf statistics(yes|no){no}
    character(len=3)          :: ctfpatch='yes'       !< whether to perform patched CTF estimation(yes|no){yes}
    character(len=3)          :: doprint='no'
    character(len=3)          :: dynreslim='no'       !< Whether the alignement resolution limit should be dynamic in streaming(yes|no){no}
    character(len=3)          :: empty3Dcavgs='yes'   !< whether 3D empty cavgs are okay(yes|no){yes}
    character(len=3)          :: envfsc='yes'         !< envelope mask even/odd pairs for FSC calculation(yes|no){yes}
    character(len=3)          :: even='no'            !< even orientation distribution(yes|no){no}
    character(len=3)          :: extract='yes'        !< whether to extract particles after picking (streaming only)
    character(len=3)          :: extractfrommov='no'  !< whether to extract particles from the movie(yes|no){no}
    character(len=3)          :: fill_holes='no'      !< fill the holes post binarisation(yes|no){no}
    character(len=3)          :: fillin='no'          !< fillin particle sampling
    character(len=3)          :: ft2img='no'          !< convert Fourier transform to real image of power(yes|no){no}
    character(len=3)          :: frc_weight='no'      !< considering particle numbers of classes in computing frc (yes|no){no}
    character(len=3)          :: frcref='no'          !< Whether to apply a FRC filter to the 3D polar reference(yes|no){no}
    character(len=3)          :: gauref='no'          !< Whether to apply a gaussian filter to the polar reference(yes|no){no}
    character(len=3)          :: guinier='no'         !< calculate Guinier plot(yes|no){no}
    character(len=3)          :: graphene_filt='no'   !< filter out graphene bands in correlation search
    character(len=3)          :: greedy_sampling='yes' !< greedy class sampling or not (referring to objective function)
    character(len=3)          :: gridding='no'        !< to test gridding correction
    character(len=3)          :: groupframes='no'     !< Whether to perform weighted frames averaging during motion correction(yes|no){no}
    character(len=3)          :: have_clustering='no' !< to flag that clustering solution exists in field os_cls2D (cluster_cavgs)
    character(len=3)          :: hist='no'            !< whether to print histogram
    character(len=3)          :: icm='no'             !< whether to apply ICM filter to reference
    character(len=3)          :: incrreslim='no'      !< Whether to add ten shells to the FSC resolution limit
    character(len=3)          :: interactive='no'     !< Whether job is interactive
    character(len=3)          :: iterstats='no'       !< Whether to keep track alignment stats throughout iterations
    character(len=3)          :: json='no'            !< Print in json format (mainly for nice)
    character(len=3)          :: keepvol='no'         !< dev flag for preserving iterative volumes in refine3d
    character(len=3)          :: lam_anneal='no'      !< anneal lambda parameter
    character(len=3)          :: linethres='no'       !< whether to consider angular threshold in common lines (yes|no){no}
    character(len=3)          :: linstates='no'       !< linearizing states in alignment (yes|no){no}
    character(len=3)          :: loc_sdev='no'        !< Whether to calculate local standard deviations(yes|no){no}
    character(len=3)          :: lp_auto='no'         !< automatically estimate lp(yes|no){no}
    character(len=3)          :: makemovie='no'
    character(len=3)          :: masscen='yes'        !< center to center of gravity(yes|no){yes}
    character(len=3)          :: mcpatch='yes'        !< whether to perform patch-based alignment during motion correction
    character(len=3)          :: mcpatch_thres='yes'  !< whether to use the threshold for motion correction patch solution(yes|no){yes}
    character(len=3)          :: mirr='no'            !< mirror(no|x|y){no}
    character(len=3)          :: mkdir='no'           !< make auto-named execution directory(yes|no){no}
    character(len=3)          :: ml_reg='yes'         !< apply ML regularization to class averages or volume
    character(len=3)          :: ml_reg_chunk='no'    !< apply ML regularization to class averages or volume in chunks
    character(len=3)          :: ml_reg_pool='no'     !< apply ML regularization to class averages or volume in pool
    character(len=3)          :: needs_sigma='no'     !<
    character(len=3)          :: neg='no'             !< invert contrast of images(yes|no){no}
    character(len=3)          :: neigs_per='no'       !< using neigs as percentage of the total dimension(yes|no){no}
    character(len=3)          :: noise_norm ='yes'    !< image normalization based on background/foreground standardization(yes|no){yes}
    character(len=3)          :: norm='no'            !< do statistical normalisation avg
    character(len=3)          :: nonuniform='no'      !< nonuniform filtering(yes|no){no}
    character(len=3)          :: omit_neg='no'        !< omit negative pixels(yes|no){no}
    character(len=3)          :: outside='no'         !< extract boxes outside the micrograph boundaries(yes|no){no}
    character(len=3)          :: pad='no'
    character(len=3)          :: partition='no'
    character(len=3)          :: pca_fft='no'         !< fft image before pca(yes|no){no}
    character(len=3)          :: pca_img_ori='no'     !< original (no rotation/shifting within classes) ptcl stack to pca(yes|no){no}
    character(len=3)          :: pca_ori_stk='no'     !< output denoised particle stack in the original order and shifted/rotated back(yes|no){no}
    character(len=3)          :: phaseplate='no'      !< images obtained with Volta phaseplate(yes|no){no}
    character(len=3)          :: phrand='no'          !< phase randomize(yes|no){no}
    character(len=3)          :: pick_roi='no'
    character(len=3)          :: platonic='yes'       !< platonic symmetry or not(yes|no){yes}
    character(len=3)          :: polar='no'           !< To use polar FT representation(yes|no){no}
    character(len=3)          :: pre_norm='no'        !< pre-normalize images for PCA analysis
    character(len=3)          :: print_corrs='no'     !< exporting corrs during the refinement(yes|no){no}
    character(len=3)          :: proj_is_class='no'   !< intepret projection directions as classes
    character(len=3)          :: projstats='no'
    character(len=3)          :: prune='no'
    character(len=3)          :: prob_inpl='no'       !< probabilistic in-plane search in refine=neigh mode(yes|no){no}
    character(len=3)          :: prob_sh='no'         !< shift information in the prob tab (yes|no){no}
    character(len=3)          :: projrec='no'         !< Whether to reconstruct from summed projection directions (yes|no){no}
    character(len=3)          :: ptcl_norm ='no'
    character(len=3)          :: randomise='no'       !< whether to randomise particle order
    character(len=3)          :: rank_cavgs='yes'     !< Whether to rank class averages(yes|no)
    character(len=3)          :: ranked_parts='yes'   !< generate ranked rather than balanced partitions in class sampling
    character(len=3)          :: refs_delin='no'      !< delinearizing reprojections of different states (yes|no){no}
    character(len=3)          :: reject_cls='no'      !< whether to reject poor classes
    character(len=3)          :: reject_mics='no'     !< whether to reject micrographs based on ctfres/icefrac
    character(len=3)          :: remap_cls='no'
    character(len=3)          :: remove_chunks='yes'  !< whether to remove chunks after completion (yes|no){yes}
    character(len=3)          :: reset_boxfiles='no'  !< whether to remove existing boxfiles and set boxfile in current dir (yes|no){no}
    character(len=3)          :: restore_cavgs='yes'  !< Whether to restore images to class averages after orientation search (yes|no){yes}
    character(len=3)          :: ring='no'            !< whether to use ring in interactive stream pick
    character(len=3)          :: roavg='no'           !< rotationally average images in stack
    character(len=3)          :: transp_pca='no'
    character(len=3)          :: script='no'          !< do not execute but generate a script for submission to the queue
    character(len=3)          :: shbarrier='yes'      !< use shift search barrier constraint(yes|no){yes}
    character(len=3)          :: sh_first='no'        !< shifting before orientation search(yes|no){no}
    character(len=3)          :: sh_inv='no'          !< whether to use shift invariant metric for projection direction assignment(yes|no){no}
    character(len=3)          :: sort_asc='yes'       !< sort oris ascending
    character(len=3)          :: srch_oris='yes'      !< whether to search orientations in multivolume assignment(yes|no){yes} 
    character(len=3)          :: stream='no'          !< stream (real time) execution mode(yes|no){no}
    character(len=3)          :: symrnd='no'          !< randomize over symmetry operations(yes|no){no}
    character(len=3)          :: taper_edges='no'     !< self-explanatory
    character(len=3)          :: tophat='no'          !< tophat filter(yes|no){no}
    character(len=3)          :: trail_rec='no'       !< trailing (weighted average) reconstruction when update_frac=yes 
    character(len=3)          :: trsstats='no'        !< provide origin shift statistics(yes|no){no}
    character(len=3)          :: tseries='no'         !< images represent a time-series(yes|no){no}
    character(len=3)          :: updated='no'         !< whether parameters has been updated
    character(len=3)          :: use_thres='yes'      !< Use contact-based thresholding(yes|no){yes}
    character(len=3)          :: vis='no'             !< visualise(yes|no)
    character(len=3)          :: verbose_exit='yes'   !< Whether to write a indicator file when task completes(yes|no){no}
    character(len=3)          :: volrec='yes'         !< volume reconstruction in 3D(yes|no){yes}
    character(len=3)          :: write_cavgs='no'     !< write out cavgs
    character(len=3)          :: zero='no'            !< zeroing(yes|no){no}
    ! files & directories strings in ascending alphabetical order
    character(len=LONGSTRLEN) :: boxfile=''           !< file with EMAN particle coordinates(.txt)
    character(len=LONGSTRLEN) :: boxtab=''            !< table (text file) of files with EMAN particle coordinates(.txt)
    character(len=LONGSTRLEN) :: classdoc=''          !< doc with per-class stats(.txt)
    character(len=LONGSTRLEN) :: cwd=''
    character(len=LONGSTRLEN) :: deftab=''            !< file with CTF info(.txt|.simple)
    character(len=LONGSTRLEN) :: dir=''               !< directory
    character(len=LONGSTRLEN) :: dir_meta=''          !< grab xml files from here
    character(len=LONGSTRLEN) :: dir_movies=''        !< grab mrc mrcs files from here
    character(len=LONGSTRLEN) :: dir_prev=''          !< grab previous projects for streaming
    character(len=LONGSTRLEN) :: dir_refine=''        !< refinement directory
    character(len=LONGSTRLEN) :: dir_reject='rejected'!< move rejected files to here{rejected}
    character(len=LONGSTRLEN) :: dir_select='selected'!< move selected files to here{selected}
    character(len=LONGSTRLEN) :: dir_target=''        !< put output here
    character(len=LONGSTRLEN) :: dir_ptcls=''
    character(len=LONGSTRLEN) :: dir_box=''
    character(len=LONGSTRLEN) :: exec_dir='./'        !< auto-named execution directory
    character(len=LONGSTRLEN) :: filetab=''           !< list of files(.txt)
    character(len=LONGSTRLEN) :: fname=''             !< file name
    character(len=LONGSTRLEN) :: frcs=trim(FRCS_FILE) !< binary file with per-class/proj Fourier Ring Correlations(.bin)
    character(len=LONGSTRLEN) :: fsc='fsc_state01.bin'!< binary file with FSC info{fsc_state01.bin}
    character(len=LONGSTRLEN) :: gainref=''           !< gain reference for movie alignment
    character(len=LONGSTRLEN) :: import_dir=''        !< dir to import .star files from for import_starproject
    character(len=LONGSTRLEN) :: infile=''            !< file with inputs(.txt)
    character(len=LONGSTRLEN) :: infile2=''           !< file with inputs(.txt)
    character(len=LONGSTRLEN) :: mskfile=''           !< maskfile.ext
    character(len=LONGSTRLEN) :: msklist=''           !< table (text file) of mask volume files(.txt)
    character(len=LONGSTRLEN) :: mskvols(MAXS)=''
    character(len=LONGSTRLEN) :: niceserver=''        !< address and port of nice server for comms
    character(len=LONGSTRLEN) :: oritab=''            !< table  of orientations(.txt|.simple)
    character(len=LONGSTRLEN) :: oritab2=''           !< 2nd table of orientations(.txt|.simple)
    character(len=LONGSTRLEN) :: outdir=''            !< manually set output directory name
    character(len=LONGSTRLEN) :: outfile=''           !< output document
    character(len=LONGSTRLEN) :: outstk=''            !< output image stack
    character(len=LONGSTRLEN) :: outvol=''            !< output volume{outvol.ext}
    character(len=LONGSTRLEN) :: pdbfile=''           !< PDB file
    character(len=LONGSTRLEN) :: pdbfile2=''          !< PDB file, another one
    character(len=LONGSTRLEN) :: pdbfiles=''          !< list of PDB files
    character(len=LONGSTRLEN) :: pdbout=''            !< PDB output file
    character(len=LONGSTRLEN) :: pdfile='pdfile.bin'
    character(len=LONGSTRLEN) :: pickrefs=''          !< picking references
    character(len=LONGSTRLEN) :: plaintexttab=''      !< plain text file of input parameters
    character(len=LONGSTRLEN) :: projfile=''          !< SIMPLE *.simple project file
    character(len=LONGSTRLEN) :: projfile_optics=''   !< SIMPLE *.simple project file containing optics group definitions
    character(len=LONGSTRLEN) :: projfile_target=''   !< another SIMPLE *.simple project file
    character(len=LONGSTRLEN) :: refs=''              !< initial2Dreferences.ext
    character(len=LONGSTRLEN) :: refs_even=''
    character(len=LONGSTRLEN) :: refs_odd=''
    character(len=LONGSTRLEN) :: snapshot=''          !< path to write snapshot project file to
    character(len=LONGSTRLEN) :: star_datadir=''      !< STAR-generated data directory
    character(len=LONGSTRLEN) :: starfile=''          !< STAR-formatted EM file (proj.star)
    character(len=LONGSTRLEN) :: star_mic=''          !< STAR-formatted EM file (micrographs.star)
    character(len=LONGSTRLEN) :: star_model=''        !< STAR-formatted EM file (model.star)
    character(len=LONGSTRLEN) :: star_ptcl=''         !< STAR-formatted EM file (data.star)
    character(len=LONGSTRLEN) :: stk=''               !< particle stack with all images(ptcls.ext)
    character(len=LONGSTRLEN) :: stktab=''            !< list of per-micrograph stacks
    character(len=LONGSTRLEN) :: stk2=''              !< 2nd stack(in selection map: selected(cavgs).ext)
    character(len=LONGSTRLEN) :: stk3=''              !< 3d stack (in selection map (cavgs)2selectfrom.ext)
    character(len=LONGSTRLEN) :: stk_backgr=''        !< stack with image for background subtraction
    character(len=LONGSTRLEN) :: vol=''
    character(len=LONGSTRLEN) :: vols(MAXS)=''
    character(len=LONGSTRLEN) :: vols_even(MAXS)=''
    character(len=LONGSTRLEN) :: vols_odd(MAXS)=''
    character(len=LONGSTRLEN) :: xmldir=''
    character(len=LONGSTRLEN) :: xmlloc=''
    ! other character variables in ascending alphabetical order
    character(len=STDLEN)     :: algorithm=''         !< algorithm to be used
    character(len=STDLEN)     :: angastunit='degrees' !< angle of astigmatism unit (radians|degrees){degrees}
    character(len=4)          :: automatic='no'       !< automatic thres for edge detect (yes|no){no}
    character(len=5)          :: automsk='no'         !< automatic envelope masking (yes|tight|no){no}
    character(len=STDLEN)     :: boxtype='eman'
    character(len=STDLEN)     :: cls_init='ptcl'      !< Scheme to generate initial references for 2D analysis(ptcl|randcls|rand)
    character(len=STDLEN)     :: clustinds=''         !< comma-separated cluster indices
    character(len=STDLEN)     :: coord='cart'         !< Coordinate system for cluster2D(cart|polar|both){cart}
    character(len=STDLEN)     :: cn_type='cn_std'     !< generalised coordination number (cn_gen) or stardard (cn_std)
    character(len=STDLEN)     :: ctf='no'             !< ctf flag(yes|no|flip)
    character(len=STDLEN)     :: detector='bin'       !< detector for edge detection (sobel|bin|otsu)
    character(len=STDLEN)     :: dfunit='microns'     !< defocus unit (A|microns){microns}
    character(len=STDLEN)     :: dir_exec=''          !< name of execution directory
    character(len=4)          :: element ='    '      !< atom kind
    character(len=STDLEN)     :: executable=''        !< name of executable
    character(len=4)          :: ext='.mrc'           !< file extension{.mrc}
    character(len=STDLEN)     :: fbody=''             !< file body
    character(len=STDLEN)     :: filter='no'          !< filter type{no}
    character(len=STDLEN)     :: flag='dummy'         !< convenience flag for testing purpose
    character(len=STDLEN)     :: flipgain='no'        !< gain reference flipping (no|x|y|xy|yx)
    character(len=STDLEN)     :: linstates_mode='ppca'  !< linearized state mode(forprob|backprob){forprob}
    character(len=STDLEN)     :: multivol_mode='single' !< multivolume abinitio3D mode(single|independent|docked|input_oris_start|input_oris_fixed){single}
    character(len=STDLEN)     :: imgkind='ptcl'       !< type of image(ptcl|cavg|mic|movie){ptcl}
    character(len=STDLEN)     :: import_type='auto'   !< type of import(auto|mic|ptcl2D|ptcl3D){auto}
    character(len=STDLEN)     :: interpfun='kb'       !< Interpolation function projection/reconstruction/polar representation(kb|linear){kb}
    character(len=STDLEN)     :: kweight='default'    !< k-weighted options for cc cost function(default|all|cls|inpl|none){default}
    character(len=STDLEN)     :: kweight_chunk='default' !< k-weighted options for cc in chunks(default|all|inpl|none){default}
    character(len=STDLEN)     :: kweight_pool='default'  !< k-weighted options for cc in pool(default|all|inpl|none){default}
    character(len=STDLEN)     :: mcconvention='simple'!< which frame of reference convention to use for motion correction(simple|unblur|relion){simple}
    character(len=STDLEN)     :: msktype='soft'       !< type of mask(hard|soft){soft}
    character(len=STDLEN)     :: multi_moldiams=''    !< list of molecular diameters to be used for multiple gaussian pick
    character(len=7)          :: objfun='euclid'      !< objective function(euclid|cc){euclid}
    character(len=STDLEN)     :: opt='bfgs'           !< optimiser (bfgs|simplex){bfgs}
    character(len=STDLEN)     :: oritype='ptcl3D'     !< SIMPLE project orientation type(stk|ptcl2D|cls2D|cls3D|ptcl3D)
    character(len=STDLEN)     :: pca_mode='ppca'      !< PCA mode(ppca|pca_svd|kpca){ppca}
    character(len=STDLEN)     :: kpca_ker='cosine'    !< kPCA kernel(rbf|cosine){cosine}
    character(len=STDLEN)     :: kpca_target='ptcl'   !< kPCA kernel target on ptcls or cavgs (ptcl|cls){ptcl}
    character(len=STDLEN)     :: pcontrast='black'    !< particle contrast(black|white){black}
    character(len=STDLEN)     :: pickkind='gau'       !< Picking quasi-template(gau|ring|disc){gau}
    character(len=STDLEN)     :: pgrp='c1'            !< point-group symmetry(cn|dn|t|o|i)
    character(len=STDLEN)     :: pgrp_start='c1'      !< point-group symmetry(cn|dn|t|o|i)
    character(len=STDLEN)     :: phshiftunit='radians'!< additional phase-shift unit (radians|degrees){radians}
    character(len=STDLEN)     :: picker='new'         !< which picker to use (old|new){new}
    character(len=STDLEN)     :: prg=''               !< SIMPLE program being executed
    character(len=STDLEN)     :: projname=''          !< SIMPLE  project name
    character(len=STDLEN)     :: subprojname=''       !< SIMPLE  subproject name
    character(len=STDLEN)     :: protocol=''          !< generic option
    character(len=STDLEN)     :: ptclw='no'           !< use particle weights(yes|no){no}
    character(len=STDLEN)     :: qsys_name='local'    !< name of queue system (local|slurm|pbs)
    character(len=STDLEN)     :: qsys_partition2D=''  !< partition name for streaming 2D analysis
    character(len=STDLEN)     :: real_filter=''
    character(len=STDLEN)     :: refine='shc'         !< refinement mode(snhc|shc|neigh|shc_neigh){shc}
    character(len=STDLEN)     :: refine_type='3D'     !< refinement mode(3D|2D|hybrid){3D}
    character(len=STDLEN)     :: ref_type='cavg'      !< polar reference type(cavg|clin|vol){cavg}
    character(len=STDLEN)     :: sigma_est='group'    !< sigma estimation kind (group|global){group}
    character(len=STDLEN)     :: sort=''              !< key to sort oris on
    character(len=STDLEN)     :: speckind='sqrt'      !< power spectrum kind(real|power|sqrt|log|phase){sqrt}
    character(len=STDLEN)     :: split_mode='even'
    character(len=STDLEN)     :: startype=''          !< export type for STAR format (micrograph|select|extract|class2d|initmodel|refine3d|post){all}
    character(len=STDLEN)     :: stats='no'           !< provide statistics(yes|no|print){no}
    character(len=STDLEN)     :: tag=''               !< just a tag
    character(len=STDLEN)     :: vol_even=''          !< even reference volume
    character(len=STDLEN)     :: vol_odd=''           !< odd  reference volume
    character(len=STDLEN)     :: wcrit = 'no'         !< correlation weighting scheme (softmax|zscore|sum|cen|exp|no){sum}
    character(len=STDLEN)     :: wfun='kb'
    character(len=STDLEN)     :: wiener='full'        !< Wiener restoration (full|partial|partial_aln){full}
    character(len=:), allocatable  :: last_prev_dir   !< last previous execution directory
    ! special integer kinds
    integer(kind(ENUM_ORISEG))     :: spproj_iseg = PTCL3D_SEG    !< sp-project segments that b%a points to
    integer(kind(ENUM_OBJFUN))     :: cc_objfun   = OBJFUN_EUCLID !< objective function(OBJFUN_CC = 0, OBJFUN_EUCLID = 1)
    integer(kind=kind(ENUM_WCRIT)) :: wcrit_enum  = CORRW_CRIT    !< criterium for correlation-based weights
    ! integer variables in ascending alphabetical order
    integer :: angstep=5
    integer :: binwidth=1          !< binary layers grown for molecular envelope(in pixels){1}
    integer :: box=0               !< square image size(in pixels)
    integer :: box_crop=0          !< square image size(in pixels), relates to Fourier cropped references
    integer :: box_croppd=0        !< square image size(in pixels), relates to Fourier cropped references and padded
    integer :: box_extract
    integer :: boxpd=0
    integer :: cc_iters=1          !< number of iterations with objfun=cc before switching to another objective function
    integer :: class=1             !< cluster identity
    integer :: clip=0              !< clipped image box size(in pixels)
    integer :: clustind=0          !< cluster index
    integer :: cn=8                !< fixed std coord number for atoms in nanos
    integer :: cn_max=12           !< max std coord number for atoms in nanos
    integer :: cn_min=4            !< min std coord number for atoms in nanos
    integer :: cn_stop=10          !< rotational symmetry order stop index{10}
    integer :: cs_thres=2          !< contact score threshold for discarding atoms during autorefine3D_nano
    integer :: edge=6              !< edge size for softening molecular envelope(in pixels)
    integer :: eer_fraction=20     !< # of eer raw frames to fraction together
    integer :: eer_upsampling=1    !< eer up-sampling
    integer :: extr_iter=1
    integer :: extr_lim=MAX_EXTRLIM2D
    integer :: find=1              !< Fourier index
    integer :: nframesgrp=0        !< # frames to group before motion_correct(Falcon 3){0}
    integer :: fromp=1             !< start ptcl index
    integer :: fromf=1             !< frame start index
    integer :: grow=0              !< # binary layers to grow(in pixels)
    integer :: hpind_fsc           !< high-pass Fourier index for FSC
    integer :: icm_stage=0
    integer :: iptcl=1
    integer :: istart=0
    integer :: job_memory_per_task2D=JOB_MEMORY_PER_TASK_DEFAULT
    integer :: kfromto(2)
    integer :: ldim(3)=0
    integer :: maxits=100          !< maximum # iterations
    integer :: maxits_glob=100     !< maximum # iterations, global
    integer :: maxits_between=30   !< maximum # iterations in between model building steps
    integer :: maxits_sh=60        !< maximum # iterations of shifting lbfgsb
    integer :: maxnchunks=0
    integer :: maxpop=0            !< max population of an optics group
    integer :: maxnruns=0
    integer :: minits=0            !< minimum # iterations
    integer :: mrcmode=2
    integer :: nchunks=0
    integer :: nchunksperset=0
    integer :: ncunits=0           !< # computing units, can be < nparts{nparts}
    integer :: ncls=500            !< # clusters
    integer :: ncls_start=10       !< minimum # clusters for 2D streaming
    integer :: ndiscrete=0         !< # discrete orientations
    integer :: neigs=0             !< # of eigenvectors 
    integer :: newbox=0            !< new box for scaling (by Fourier padding/clipping)
    integer :: nframes=0           !< # frames{30}
    integer :: ngrow=0             !< # of white pixel layers to grow in binary image
    integer :: niceprocid=0        !< # id of process in nice database
    integer :: ninit=3             !< # number of micrographs to use during diameter estimation global search
    integer :: nmics=0             !< # micrographs
    integer :: nmoldiams=1         !< # moldiams
    integer :: noris=0
    integer :: nparts=1            !< # partitions in distributed execution
    integer :: nparts_per_part=1   !< # partitions in distributed execution of balanced parts
    integer :: nparts_chunk=1      !< # partitions in chunks distributed execution
    integer :: nparts_pool =1      !< # partitions for pool distributed execution
    integer :: npeaks=NPEAKS_DEFAULT !< # of greedy subspace peaks to construct multi-neighborhood search spaces from
    integer :: npeaks_inpl=NPEAKS_INPL_DEFAULT !< # multi-neighborhood search peaks to refine with L-BFGS
    integer :: npix=0              !< # pixles/voxels in binary representation
    integer :: nptcls=1            !< # images in stk/# orientations in oritab
    integer :: nptcls_per_cls=500  !< # images in stk/# orientations in oritab
    integer :: nptcls_per_part=0   !< # particles per part in balanced selection
    integer :: nquanta=0           !< # quanta in quantization
    integer :: nran=0              !< # random images to select
    integer :: nrefs=100           !< # references used for picking{100}
    integer :: nrestarts=1
    integer :: nrots=0             !< number of in-plane rotations in greedy Cartesian search
    integer :: nsample=0           !< # particles to sample in refinement with fractional update
    integer :: nsample_max=0       !< maximum # particles to sample in refinement with fractional update
    integer :: nsample_start=0     !< # particles to sample in refinement with fractional update, lower bound
    integer :: nsample_stop=0      !< # particles to sample in refinement with fractional update, upper bound
    integer :: nsearch=40          !< # search grid points{40}
    integer :: nspace=2500         !< # projection directions
    integer :: nspace_sub=500      !< # projection directions in subspace
    integer :: nspace_max=1500     !< Maximum # of projection directions
    integer :: nstages=8           !< # low-pass limit stages
    integer :: nstates=1           !< # states to reconstruct
    integer :: nsym=1
    integer :: nthr=1              !< # OpenMP threads{1}
    integer :: nthr2D=1            !< # OpenMP threads{1}
    integer :: nthr_ini3D=1        !< # OpenMP threads{1}
    integer :: numlen=0            !< length of number string
    integer :: nxpatch=MC_NPATCH   !< # of patches along x for motion correction{5}
    integer :: nypatch=MC_NPATCH   !< # of patches along y for motion correction{5}
    integer :: offset=10           !< pixels offset{10}
    integer :: optics_offset=0
    integer :: part=1
    integer :: pid=0               !< process ID
    integer :: pspecsz=512         !< size of power spectrum(in pixels)
    integer :: ptcl=1
    integer :: reliongroups=0
    integer :: shift_stage=0
    integer :: split_stage=7       !< splitting stage when multivol_mode==docked
    integer :: startit=1           !< start iterating from here
    integer :: stage=0
    integer :: state=1             !< state to extract
    integer :: stepsz=1            !< size of step{1}
    integer :: tofny=0
    integer :: top=1
    integer :: tof=0               !< end index
    integer :: vol_dim=0           !< input simulated pdb2mrc volume dimensions
    integer :: walltime=WALLTIME_DEFAULT  !< Walltime in seconds for workload management
    integer :: which_iter=0        !< iteration nr
    integer :: smooth_ext=8        !< smoothing window extension
    integer :: xcoord=0            !< x coordinate{0}
    integer :: ycoord=0            !< y coordinate{0}
    integer :: xdim=0              !< x dimension(in pixles)
    integer :: xdimpd=0
    integer :: ydim=0              !< y dimension(in pixles)
    ! real variables in ascending alphabetical order
    real    :: alpha=KBALPHA
    real    :: amsklp=8.           !< low-pass limit for envelope mask generation(in A)
    real    :: angerr=0.           !< angular error(in degrees){0}
    real    :: ares=7.
    real    :: astigerr=0.         !< astigmatism error(in microns)
    real    :: astigthreshold=ASTIG_THRESHOLD !< ice fraction threshold{1.0}
    real    :: astigtol=0.05       !< expected (tolerated) astigmatism(in microns){0.05}
    real    :: athres=10.          !< angular threshold(in degrees)
    real    :: bfac=200            !< bfactor for sharpening/low-pass filtering(in A**2){200.}
    real    :: bfacerr=50.         !< bfactor error in simulated images(in A**2){0}
    real    :: box_exp_factor=BOX_EXP_FACTOR_DEFAULT !< multiplication factor to image size as determined by multi-diameter picking{1.2}
    real    :: bw_ratio=0.3        !< ratio between foreground-background pixel desired in edge detection
    real    :: cenlp=20.           !< low-pass limit for binarisation in centering(in A){30 A}
    real    :: cs=2.7              !< spherical aberration constant(in mm){2.7}
    real    :: corr_thres=0.5      !< per-atom validation correlation threshold for discarding atoms
    real    :: ctfresthreshold=CTFRES_THRESHOLD !< ctf resolution threshold{30A}
    real    :: dcrit_rel=0.5       !< critical distance relative to box(0-1){0.5}
    real    :: defocus=2.          !< defocus(in microns){2.}
    real    :: dferr=1.            !< defocus error(in microns){1.0}
    real    :: dfmax=DFMAX_DEFAULT !< maximum expected defocus(in microns)
    real    :: dfmin=DFMIN_DEFAULT !< minimum expected defocus(in microns)
    real    :: dfsdev=0.1
    real    :: dstep=0.
    real    :: dsteppd=0.
    real    :: e1=0.               !< 1st Euler(in degrees){0}
    real    :: e2=0.               !< 2nd Euler(in degrees){0}
    real    :: e3=0.               !< 3d Euler(in degrees){0}
    real    :: eps=0.5             !< learning rate
    real    :: eps_bounds(2) = [0.5,1.0]
    real    :: eullims(3,2)=0.
    real    :: extr_init=EXTRINITHRES !< initial extremal ratio (0-1)
    real    :: fny=0.
    real    :: focusmsk=0.         !< spherical msk for use with focused refinement (radius in pixels)
    real    :: focusmskdiam=0.     !< spherical msk for use with focused refinement (diameter in Angstroms)
    real    :: frac=1.             !< fraction of ptcls(0-1){1}
    real    :: fraca=0.1           !< fraction of amplitude contrast used for fitting CTF{0.1}
    real    :: fracdeadhot=0.05    !< fraction of dead or hot pixels{0.01}
    real    :: frac_best=1.0       !< fraction of best particles to sample from per class when balance=yes
    real    :: frac_worst=1.0      !< fraction of worst particles to sample from per class when balance=yes
    real    :: frac_diam=0.5       !< fraction of atomic diameter
    real    :: fracsrch=0.9        !< fraction of serach space scanned for convergence
    real    :: fraction_dose_target=FRACTION_DOSE_TARGET_DEFAULT !< dose (in e/A2)
    real    :: frac_outliers=0.
    real    :: fraczero=0.
    real    :: ftol=1e-6
    real    :: gaufreq=-1.0         ! Full width at half maximum frequency for the gaussian filter
    real    :: motion_correctftol = 1e-6   !< tolerance (gradient) for motion_correct
    real    :: motion_correctgtol = 1e-6   !< tolerance (function value) for motion_correct
    real    :: hp=100.             !< high-pass limit(in A)
    real    :: hp_ctf_estimate=HP_CTF_ESTIMATE !< high-pass limit 4 ctf_estimate(in A)
    real    :: icefracthreshold=ICEFRAC_THRESHOLD !< ice fraction threshold{1.0}
    real    :: kv=300.             !< acceleration voltage(in kV){300.}
    real    :: lambda=1.0
    real    :: lam_bounds(2) = [0.05,1.0]
    real    :: lp=20.              !< low-pass limit(in A)
    real    :: lp2D=20.            !< low-pass limit(in A)
    real    :: lp_backgr=20.       !< low-pass for solvent blurring (in A)
    real    :: lp_discrete=20.     !< low-pass for discrete search used for peak detection (in A)
    real    :: lp_ctf_estimate=LP_CTF_ESTIMATE !< low-pass limit 4 ctf_estimate(in A)
    real    :: lpstart_nonuni= 30. !< optimization(search)-based low-pass limit lower bound
    real    :: lp_pick=PICK_LP_DEFAULT !< low-pass limit 4 picker(in A)
    real    :: lplim_crit=0.143    !< corr criterion low-pass limit assignment(0.143-0.5){0.143}
    real    :: lplims2D(3)
    real    :: lpstart=0.          !< start low-pass limit(in A){15}
    real    :: lpstop=8.0          !< stop low-pass limit(in A){8}
    real    :: lpstart_ini3D=0.    !< start low-pass limit(in A){15}
    real    :: lpstop_ini3D=8.0    !< stop low-pass limit(in A){8}
    real    :: lpstop2D=8.0        !< stop low-pass limit(in A){8}
    real    :: lpthres=RES_THRESHOLD_STREAM
    real    :: max_dose=0.         !< maximum dose threshold (e/A2)
    real    :: max_rad=0.          !< particle longest  dim (in pixels)
    real    :: min_rad=100.        !< particle shortest dim (in pixels)
    real    :: moldiam=140.        !< molecular diameter(in A)
    real    :: moldiam_max=200.    !< upper bound molecular diameter(in A)
    real    :: moldiam_refine=0.   !< upper bound molecular diameter(in A)
    real    :: moldiam_ring=0.     !< ring picker diameter(in A)
    real    :: moment=0.
    real    :: msk=0.              !< mask radius(in pixels)
    real    :: msk_crop=0.         !< mask radius(in pixels)
    real    :: mskdiam=0.          !< mask diameter(in Angstroms)
    real    :: mul=1.              !< origin shift multiplication factor{1}
    real    :: ndev=2.5            !< # deviations in one-cluster clustering
    real    :: ndev2D=CLS_REJECT_STD    !< # deviations for 2D class selection/rejection
    real    :: nsig=2.5            !< # sigmas
    real    :: osmpd=0.            !< target output pixel size
    real    :: overlap=0.9         !< required parameters overlap for convergence
    real    :: phranlp=35.         !< low-pass phase randomize(yes|no){no}
    real    :: pool_threshold_factor=POOL_THRESHOLD_FACTOR  !< stream pool class rejection adjustment
    real    :: prob_athres=10.     !< angle threshold for prob distribution samplings
    real    :: res_target = 3.     !< resolution target in A
    real    :: scale=1.            !< image scale factor{1}
    real    :: sherr=0.            !< shift error(in pixels){2}
    real    :: sigma=1.0           !< for gaussian function generation {1.}
    real    :: smpd=2.             !< sampling distance; same as EMANs apix(in A)
    real    :: smpd_target=0.5     !< target sampling distance; same as EMANs apix(in A) refers to paddep cavg/volume
    real    :: smpd_crop=2.        !< sampling distance; same as EMANs apix(in A) refers to cropped cavg/volume
    real    :: smpd_targets2D(2)
    real    :: snr=0.              !< signal-to-noise ratio
    real    :: snr_noise_reg=0.    !< signal to noise ratio of noise regularization
    real    :: stoch_rate=100.     !< percentage of stoch in polar cavgs
    real    :: stream_mean_threshold=MEAN_THRESHOLD         !< stream class rejection based on image mean (relative)
    real    :: stream_rel_var_threshold=REL_VAR_THRESHOLD   !< stream class rejection based on image variance (relative)
    real    :: stream_abs_var_threshold=ABS_VAR_THRESHOLD   !< stream class rejection based on image variance (absolute)
    real    :: stream_tvd_theshold=TVD_THRESHOLD            !< stream class rejection based on total variation distance
    real    :: stream_minmax_threshold=MINMAX_THRESHOLD     !< stream class rejection based on min.max absolute values
    real    :: tau=TAU_DEFAULT     !< for empirical scaling of cc-based particle weights
    real    :: tilt_thres=0.05
    real    :: thres=0.            !< threshold (binarisation: 0-1; distance filer: in pixels)
    real    :: thres_low=0.        !< lower threshold for canny edge detection
    real    :: thres_up=1.         !< upper threshold for canny edge detection
    real    :: tiltgroupmax=0
    real    :: total_dose
    real    :: trs=0.              !< maximum halfwidth shift(in pixels)
    real    :: update_frac = 1.
    real    :: ufrac_trec  = 1.    !< update frac trailing rec
    real    :: width=10.           !< falloff of mask(in pixels){10}
    real    :: winsz=RECWINSZ
    real    :: xsh=0.              !< x shift(in pixels){0}
    real    :: ysh=0.              !< y shift(in pixels){0}
    real    :: zsh=0.              !< z shift(in pixels){0}
    ! logical variables in (roughly) ascending alphabetical order
    logical :: l_autoscale    = .false.
    logical :: l_bfac         = .false.
    logical :: l_comlin       = .false.
    logical :: l_corrw        = .false.
    logical :: l_distr_exec   = .false.
    logical :: l_dose_weight  = .false.
    logical :: l_doshift      = .false.
    logical :: l_eer_fraction = .false.
    logical :: l_envfsc       = .false.
    logical :: l_filemsk      = .false.
    logical :: l_focusmsk     = .false.
    logical :: l_fillin       = .false.
    logical :: l_greedy_smpl  = .true.
    logical :: l_frac_best    = .false.
    logical :: l_frac_worst   = .false.
    logical :: l_update_frac  = .false.
    logical :: l_graphene     = .false.
    logical :: l_kweight      = .false.
    logical :: l_kweight_shift= .true.
    logical :: l_kweight_rot  = .false.
    logical :: l_icm          = .false.
    logical :: l_incrreslim   = .false.
    logical :: l_lam_anneal   = .false.
    logical :: l_linstates    = .false.
    logical :: l_lpauto       = .false.
    logical :: l_lpset        = .false.
    logical :: l_ml_reg       = .true.
    logical :: l_noise_reg    = .false.
    logical :: l_noise_norm   = .true.
    logical :: l_needs_sigma  = .false.
    logical :: l_neigh        = .false.
    logical :: l_phaseplate   = .false.
    logical :: l_prob_inpl    = .false.
    logical :: l_prob_sh      = .false.
    logical :: l_refs_delin   = .false.
    logical :: l_sh_first     = .false.
    logical :: l_sigma_glob   = .false.
    logical :: l_trail_rec    = .false.
    logical :: l_remap_cls    = .false.
    logical :: l_wiener_part  = .false.
    logical :: sp_required    = .false.
    contains
    procedure          :: new
    procedure, private :: set_img_format
end type parameters

class(parameters), pointer :: params_glob => null()

contains

    subroutine new( self, cline, silent )
        use simple_sp_project, only: sp_project
        class(parameters), target, intent(inout) :: self
        class(cmdline),            intent(inout) :: cline
        logical,         optional, intent(in)    :: silent
        character(len=LONGSTRLEN), allocatable   :: sp_files(:)
        character(len=:),          allocatable   :: phaseplate, ctfflag
        logical                       :: vol_defined(MAXS)
        character(len=1)              :: checkupfile(50)
        character(len=:), allocatable :: absname
        type(binoris)    :: bos
        type(sp_project) :: spproj
        type(ori)        :: o
        type(atoms)      :: atoms_obj
        real             :: smpd, mskdiam_default, msk_default
        integer          :: i, ncls, ifoo, lfoo(3), cntfile, istate
        integer          :: idir, nsp_files, box, nptcls, nthr
        logical          :: nparts_set, ssilent, def_vol1, def_even, def_odd, is_2D
        ssilent = .false.
        if( present(silent) ) ssilent = silent
        ! seed random number generator
        call seed_rnd
        ! constants
        nparts_set = .false.
        ! file counter
        cntfile = 0
        ! default initialisations that depend on meta-data file format
        self%outfile = 'outfile'//trim(METADATA_EXT)
        ! checkers in ascending alphabetical order
        call check_carg('acf',            self%acf)
        call check_carg('algorithm',      self%algorithm)
        call check_carg('angastunit',     self%angastunit)
        call check_carg('append',         self%append)
        call check_carg('async',          self%async)
        call check_carg('atom_thres',     self%atom_thres)
        call check_carg('automsk',        self%automsk)
        call check_carg('automatic',      self%automatic)
        call check_carg('autoscale',      self%autoscale)
        call check_carg('autosample',     self%autosample)
        call check_carg('avg',            self%avg)
        call check_carg('backgr_subtr',   self%backgr_subtr)
        call check_carg('balance',        self%balance)
        call check_carg('bin',            self%bin)
        call check_carg('boxtype',        self%boxtype)
        call check_carg('cavg_ini',       self%cavg_ini)
        call check_carg('cavg_ini_ext',   self%cavg_ini_ext)
        call check_carg('cavgw',          self%cavgw)
        call check_carg('center',         self%center)
        call check_carg('center_pdb',     self%center_pdb)
        call check_carg('chunk',          self%chunk)
        call check_carg('classtats',      self%classtats)
        call check_carg('clear',          self%clear)
        call check_carg('cls_init',       self%cls_init)
        call check_carg('clustinds',      self%clustinds)
        call check_carg('cn_type',        self%cn_type)
        call check_carg('combine_eo',     self%combine_eo)
        call check_carg('continue',       self%continue)
        call check_carg('contsh',         self%contsh)
        call check_carg('coord',          self%coord)
        call check_carg('crowded',        self%crowded)
        call check_carg('ctf',            self%ctf)
        call check_carg('ctfpatch',       self%ctfpatch)
        call check_carg('ctfstats',       self%ctfstats)
        call check_carg('detector',       self%detector)
        call check_carg('dfunit',         self%dfunit)
        call check_carg('dir_exec',       self%dir_exec)
        call check_carg('doprint',        self%doprint)
        call check_carg('dynreslim',      self%dynreslim)
        call check_carg('element',        self%element)
        call check_carg('empty3Dcavgs',   self%empty3Dcavgs)
        call check_carg('envfsc',         self%envfsc)
        call check_carg('even',           self%even)
        call check_carg('extract',        self%extract)
        call check_carg('extractfrommov', self%extractfrommov)
        call check_carg('startype',       self%startype)
        call check_carg('fbody',          self%fbody)
        call check_carg('fill_holes',     self%fill_holes)
        call check_carg('fillin',         self%fillin)
        call check_carg('filter',         self%filter)
        call check_carg('flag',           self%flag)
        call check_carg('flipgain',       self%flipgain)
        call check_carg('ft2img',         self%ft2img)
        call check_carg('frc_weight',     self%frc_weight)
        call check_carg('frcref',         self%frcref)
        call check_carg('gauref',         self%gauref)
        call check_carg('guinier',        self%guinier)
        call check_carg('graphene_filt',  self%graphene_filt)
        call check_carg('greedy_sampling',self%greedy_sampling)
        call check_carg('gridding',       self%gridding)
        call check_carg('groupframes',    self%groupframes)
        call check_carg('have_clustering', self%have_clustering)
        call check_carg('hist',           self%hist)
        call check_carg('icm',            self%icm)
        call check_carg('imgkind',        self%imgkind)
        call check_carg('incrreslim',     self%incrreslim)
        call check_carg('interactive',    self%interactive)
        call check_carg('interpfun',      self%interpfun)
        call check_carg('iterstats',      self%iterstats)
        call check_carg('json',           self%json)
        call check_carg('keepvol',        self%keepvol)
        call check_carg('kweight',        self%kweight)
        call check_carg('kweight_chunk',  self%kweight_chunk)
        call check_carg('kweight_pool',   self%kweight_pool)
        call check_carg('lam_anneal',     self%lam_anneal)
        call check_carg('linethres',      self%linethres)
        call check_carg('linstates',      self%linstates)
        call check_carg('linstates_mode', self%linstates_mode)
        call check_carg('loc_sdev',       self%loc_sdev)
        call check_carg('lp_auto',        self%lp_auto)
        call check_carg('makemovie',      self%makemovie)
        call check_carg('masscen',        self%masscen)
        call check_carg('mcpatch',        self%mcpatch)
        call check_carg('mcpatch_thres',  self%mcpatch_thres)
        call check_carg('mirr',           self%mirr)
        call check_carg('mkdir',          self%mkdir)
        call check_carg('ml_reg',         self%ml_reg)
        call check_carg('ml_reg_chunk',   self%ml_reg_chunk)
        call check_carg('ml_reg_pool',    self%ml_reg_pool)
        call check_carg('msktype',        self%msktype)
        call check_carg('mcconvention',   self%mcconvention)
        call check_carg('multi_moldiams', self%multi_moldiams)
        call check_carg('multivol_mode',  self%multivol_mode)
        call check_carg('needs_sigma',    self%needs_sigma)
        call check_carg('neg',            self%neg)
        call check_carg('neigs_per',      self%neigs_per)
        call check_carg('niceserver',     self%niceserver)
        call check_carg('noise_norm',     self%noise_norm)
        call check_carg('norm',           self%norm)
        call check_carg('nonuniform',     self%nonuniform)
        call check_carg('objfun',         self%objfun)
        call check_carg('omit_neg',       self%omit_neg)
        call check_carg('opt',            self%opt)
        call check_carg('oritype',        self%oritype)
        call check_carg('outdir',         self%outdir)
        call check_carg('outside',        self%outside)
        call check_carg('pad',            self%pad)
        call check_carg('partition',      self%partition)
        call check_carg('pca_mode',       self%pca_mode)
        call check_carg('kpca_ker',       self%kpca_ker)
        call check_carg('kpca_target',    self%kpca_target)
        call check_carg('pcontrast',      self%pcontrast)
        call check_carg('pickkind',       self%pickkind)
        call check_carg('pgrp',           self%pgrp)
        call check_carg('pgrp_start',     self%pgrp_start)
        call check_carg('pca_fft',        self%pca_fft)
        call check_carg('pca_img_ori',    self%pca_img_ori)
        call check_carg('pca_ori_stk',    self%pca_ori_stk)
        call check_carg('phaseplate',     self%phaseplate)
        call check_carg('phrand',         self%phrand)
        call check_carg('phshiftunit',    self%phshiftunit)
        call check_carg('pick_roi',       self%pick_roi)
        call check_carg('picker',         self%picker)
        call check_carg('platonic',       self%platonic)
        call check_carg('polar',          self%polar)
        call check_carg('pre_norm',       self%pre_norm)
        call check_carg('prg',            self%prg)
        call check_carg('print_corrs',    self%print_corrs)
        call check_carg('prob_inpl',      self%prob_inpl)
        call check_carg('prob_sh',        self%prob_sh)
        call check_carg('proj_is_class',  self%proj_is_class)
        call check_carg('projfile_optics',self%projfile_optics)
        call check_carg('projname',       self%projname)
        call check_carg('projrec',        self%projrec)
        call check_carg('projstats',      self%projstats)
        call check_carg('protocol',       self%protocol)
        call check_carg('prune',          self%prune)
        call check_carg('ptcl_norm',      self%ptcl_norm)
        call check_carg('ptclw',          self%ptclw)
        call check_carg('qsys_name',      self%qsys_name)
        call check_carg('qsys_partition2D',self%qsys_partition2D)
        call check_carg('randomise',      self%randomise)
        call check_carg('rank_cavgs',     self%rank_cavgs)
        call check_carg('ranked_parts',   self%ranked_parts)
        call check_carg('real_filter',    self%real_filter)
        call check_carg('ref_type',       self%ref_type)
        call check_carg('refine',         self%refine)
        call check_carg('refine_type',    self%refine_type)
        call check_carg('refs_delin',     self%refs_delin)
        call check_carg('reject_cls',     self%reject_cls)
        call check_carg('reject_mics',    self%reject_mics)
        call check_carg('remove_chunks',  self%remove_chunks)
        call check_carg('remap_cls',      self%remap_cls)
        call check_carg('reset_boxfiles', self%reset_boxfiles)
        call check_carg('restore_cavgs',  self%restore_cavgs)
        call check_carg('ring',           self%ring)
        call check_carg('roavg',          self%roavg)
        call check_carg('script',         self%script)
        call check_carg('shbarrier',      self%shbarrier)
        call check_carg('sh_first',       self%sh_first)
        call check_carg('sh_inv',         self%sh_inv)
        call check_carg('sigma_est',      self%sigma_est)
        call check_carg('snapshot',       self%snapshot)
        call check_carg('sort',           self%sort)
        call check_carg('sort_asc',       self%sort_asc)
        call check_carg('speckind',       self%speckind)
        call check_carg('split_mode',     self%split_mode)
        call check_carg('srch_oris',      self%srch_oris)
        call check_carg('stats',          self%stats)
        call check_carg('stream',         self%stream)
        call check_carg('subprojname',    self%subprojname)
        call check_carg('symrnd',         self%symrnd)
        call check_carg('tag',            self%tag)
        call check_carg('taper_edges',    self%taper_edges)
        call check_carg('tophat',         self%tophat)
        call check_carg('trail_rec',      self%trail_rec)
        call check_carg('transp_pca',     self%transp_pca)
        call check_carg('trsstats',       self%trsstats)
        call check_carg('tseries',        self%tseries)
        call check_carg('use_thres',      self%use_thres)
        call check_carg('vis',            self%vis)
        call check_carg('verbose_exit',   self%verbose_exit)
        call check_carg('volrec',         self%volrec)
        call check_carg('wcrit',          self%wcrit)
        call check_carg('wfun',           self%wfun)
        call check_carg('wiener',         self%wiener)
        call check_carg('write_cavgs',    self%write_cavgs)
        call check_carg('zero',           self%zero)
        ! File args
        call check_file('boxfile',        self%boxfile,      'T')
        call check_file('boxtab',         self%boxtab,       'T')
        call check_file('classdoc',       self%classdoc,     'T')
        call check_file('deftab',         self%deftab,       'T', 'O')
        call check_file('ext',            self%ext,          notAllowed='T')
        call check_file('filetab',        self%filetab,      'T')
        call check_file('fname',          self%fname)
        call check_file('frcs',           self%frcs,         'B')
        call check_file('fsc',            self%fsc,          'B')
        call check_file('gainref',        self%gainref)
        call check_file('infile',         self%infile,       'T')
        call check_file('infile2',        self%infile2,      'T')
        call check_file('mskfile',        self%mskfile,      notAllowed='T')
        call check_file('oritab',         self%oritab,       'T', 'O')
        call check_file('oritab2',        self%oritab2,      'T', 'O')
        call check_file('outfile',        self%outfile,      'T', 'O')
        call check_file('outstk',         self%outstk,       notAllowed='T')
        call check_file('outvol',         self%outvol,       notAllowed='T')
        call check_file('pdbfile',        self%pdbfile)
        call check_file('pdbfile2',       self%pdbfile2)
        call check_file('pdbfiles',       self%pdbfiles,     'T')
        call check_file('pdbout',         self%pdbout)
        call check_file('pickrefs',       self%pickrefs,     notAllowed='T')
        call check_file('plaintexttab',   self%plaintexttab, 'T')
        call check_file('projfile',       self%projfile,     'O')
        call check_file('projfile_target',self%projfile_target,'O')
        call check_file('refs',           self%refs,         notAllowed='T')
        call check_file('starfile',       self%starfile,     'R')  ! R for relion, S taken by SPIDER
        call check_file('star_mic',       self%star_mic,     'R')  ! R for relion, S taken by SPIDER
        call check_file('star_model',     self%star_model,   'R')  ! R for relion, S taken by SPIDER
        call check_file('star_ptcl',      self%star_ptcl,    'R')  ! R for relion, S taken by SPIDER
        call check_file('stk',            self%stk,          notAllowed='T')
        call check_file('stktab',         self%stktab,       'T')
        call check_file('stk2',           self%stk2,         notAllowed='T')
        call check_file('stk3',           self%stk3,         notAllowed='T')
        call check_file('stk_backgr',     self%stk_backgr,   notAllowed='T')
        call check_file('vol_even',       self%vol_even,     notAllowed='T')
        call check_file('vol_odd',        self%vol_odd,      notAllowed='T')
        ! Dir args
        call check_dir('dir',             self%dir)
        call check_dir('dir_box',         self%dir_box)
        call check_dir('dir_movies',      self%dir_movies)
        call check_dir('dir_prev',        self%dir_prev)
        call check_dir('dir_ptcls',       self%dir_ptcls)
        call check_dir('dir_refine',      self%dir_refine)
        call check_dir('dir_reject',      self%dir_reject)
        call check_dir('dir_select',      self%dir_select)
        call check_dir('dir_target',      self%dir_target)
        call check_dir('star_datadir',    self%star_datadir)
        ! Integer args
        call check_iarg('angstep',        self%angstep)
        call check_iarg('binwidth',       self%binwidth)
        call check_iarg('box',            self%box)
        call check_iarg('box_crop',       self%box_crop)
        call check_iarg('box_extract',    self%box_extract)
        call check_iarg('cc_iters',       self%cc_iters)
        call check_iarg('clip',           self%clip)
        call check_iarg('clustind',       self%clustind)
        call check_iarg('cn',             self%cn)
        call check_iarg('cn_max',         self%cn_max)
        call check_iarg('cn_min',         self%cn_min)
        call check_iarg('cn_stop',        self%cn_stop)
        call check_iarg('cs_thres',       self%cs_thres)
        call check_iarg('edge',           self%edge)
        call check_iarg('eer_fraction',   self%eer_fraction)
        call check_iarg('eer_upsampling', self%eer_upsampling)
        call check_iarg('extr_iter',      self%extr_iter)
        call check_iarg('extr_lim',      self%extr_lim)
        call check_iarg('find',           self%find)
        call check_iarg('nframesgrp',     self%nframesgrp)
        call check_iarg('fromp',          self%fromp)
        call check_iarg('fromf',          self%fromf)
        call check_iarg('grow',           self%grow)
        call check_iarg('icm_stage',      self%icm_stage)
        call check_iarg('iptcl',          self%iptcl)
        call check_iarg('job_memory_per_task2D', self%job_memory_per_task2D)
        call check_iarg('maxits',         self%maxits)
        call check_iarg('maxits_glob',    self%maxits_glob)
        call check_iarg('maxits_between', self%maxits_between)
        call check_iarg('maxits_sh',      self%maxits_sh)
        call check_iarg('maxnchunks',     self%maxnchunks)
        call check_iarg('maxpop',         self%maxpop)
        call check_iarg('maxnruns',       self%maxnruns)
        call check_iarg('minits',         self%minits)
        call check_iarg('mrcmode',        self%mrcmode)
        call check_iarg('nchunks',        self%nchunks)
        call check_iarg('nchunksperset',  self%nchunksperset)
        call check_iarg('ncls',           self%ncls)
        call check_iarg('ncls_start',     self%ncls_start)
        call check_iarg('ncunits',        self%ncunits)
        call check_iarg('ndiscrete',      self%ndiscrete)
        call check_iarg('neigs',          self%neigs)
        call check_iarg('newbox',         self%newbox)
        call check_iarg('nframes',        self%nframes)
        call check_iarg('ngrow',          self%ngrow)
        call check_iarg('niceprocid',     self%niceprocid)
        call check_iarg('ninit',          self%ninit)
        call check_iarg('nmoldiams',      self%nmoldiams)
        call check_iarg('nsearch',        self%nsearch)
        call check_iarg('noris',          self%noris)
        call check_iarg('nran',           self%nran)
        call check_iarg('nrefs',          self%nrefs)
        call check_iarg('nrestarts',      self%nrestarts)
        call check_iarg('nsample',        self%nsample)
        call check_iarg('nsample_max',    self%nsample_max)
        call check_iarg('nsample_start',  self%nsample_start)
        call check_iarg('nsample_stop',   self%nsample_stop)
        call check_iarg('nspace',         self%nspace)
        call check_iarg('nspace_sub',     self%nspace_sub)
        call check_iarg('nspace_max',     self%nspace_max)
        call check_iarg('nstages',        self%nstages)
        call check_iarg('nstates',        self%nstates)
        call check_iarg('class',          self%class)
        call check_iarg('nparts',         self%nparts)
        call check_iarg('nparts_per_part', self%nparts_per_part)
        call check_iarg('nparts_chunk',   self%nparts_chunk)
        call check_iarg('nparts_pool',    self%nparts_pool)
        call check_iarg('npeaks',         self%npeaks)
        call check_iarg('npeaks_inpl',    self%npeaks_inpl)
        call check_iarg('npix',           self%npix)
        call check_iarg('nptcls',         self%nptcls)
        call check_iarg('nptcls_per_cls', self%nptcls_per_cls)
        call check_iarg('nptcls_per_part', self%nptcls_per_part)
        call check_iarg('nquanta',        self%nquanta)
        call check_iarg('nthr',           self%nthr)
        call check_iarg('nthr2D',         self%nthr2D)
        call check_iarg('nthr_ini3D',     self%nthr_ini3D)
        call check_iarg('numlen',         self%numlen)
        call check_iarg('nxpatch',        self%nxpatch)
        call check_iarg('nypatch',        self%nypatch)
        call check_iarg('offset',         self%offset)
        call check_iarg('optics_offset',  self%optics_offset)
        call check_iarg('part',           self%part)
        call check_iarg('pspecsz',        self%pspecsz)
        call check_iarg('shift_stage',    self%shift_stage)
        call check_iarg('split_stage',    self%split_stage)
        call check_iarg('startit',        self%startit)
        call check_iarg('stage',          self%stage)
        call check_iarg('state',          self%state)
        call check_iarg('stepsz',         self%stepsz)
        call check_iarg('top',            self%top)
        call check_iarg('tof',            self%tof)
        call check_iarg('vol_dim',        self%vol_dim)
        call check_iarg('which_iter',     self%which_iter)
        call check_iarg('smooth_ext',     self%smooth_ext)
        call check_iarg('walltime',       self%walltime)
        call check_iarg('xdim',           self%xdim)
        call check_iarg('xcoord',         self%xcoord)
        call check_iarg('ycoord',         self%ycoord)
        call check_iarg('ydim',           self%ydim)
        ! Float args
        call check_rarg('alpha',          self%alpha)
        call check_rarg('amsklp',         self%amsklp)
        call check_rarg('angerr',         self%angerr)
        call check_rarg('ares',           self%ares)
        call check_rarg('astigerr',       self%astigerr)
        call check_rarg('astigthreshold', self%astigthreshold)
        call check_rarg('astigtol',       self%astigtol)
        call check_rarg('athres',         self%athres)
        call check_rarg('bfac',           self%bfac)
        call check_rarg('bfacerr',        self%bfacerr)
        call check_rarg('box_exp_factor', self%box_exp_factor)
        call check_rarg('bw_ratio',       self%bw_ratio)
        call check_rarg('cenlp',          self%cenlp)
        call check_rarg('cs',             self%cs)
        call check_rarg('corr_thres',     self%corr_thres)
        call check_rarg('ctfresthreshold',self%ctfresthreshold)
        call check_rarg('dcrit_rel',      self%dcrit_rel)
        call check_rarg('defocus',        self%defocus)
        call check_rarg('dferr',          self%dferr)
        call check_rarg('dfmax',          self%dfmax)
        call check_rarg('dfmin',          self%dfmin)
        call check_rarg('dfsdev',         self%dfsdev)
        call check_rarg('e1',             self%e1)
        call check_rarg('e2',             self%e2)
        call check_rarg('e3',             self%e3)
        call check_rarg('eps',            self%eps)
        call check_rarg('extr_init',      self%extr_init)
        call check_rarg('focusmsk',       self%focusmsk)
        call check_rarg('focusmskdiam',   self%focusmskdiam)
        call check_rarg('frac',           self%frac)
        call check_rarg('fraca',          self%fraca)
        call check_rarg('fracdeadhot',    self%fracdeadhot)
        call check_rarg('frac_best',      self%frac_best)
        call check_rarg('frac_worst',     self%frac_worst)
        call check_rarg('frac_diam',      self%frac_diam)
        call check_rarg('fracsrch',       self%fracsrch)
        call check_rarg('fraction_dose_target',self%fraction_dose_target)
        call check_rarg('frac_outliers',  self%frac_outliers)
        call check_rarg('fraczero',       self%fraczero)
        call check_rarg('ftol',           self%ftol)
        call check_rarg('gaufreq',        self%gaufreq)
        call check_rarg('hp',             self%hp)
        call check_rarg('hp_ctf_estimate',self%hp_ctf_estimate)
        call check_rarg('icefracthreshold',self%icefracthreshold)
        call check_rarg('kv',             self%kv)
        call check_rarg('lambda',         self%lambda)
        call check_rarg('lp',             self%lp)
        call check_rarg('lp2D',           self%lp2D)
        call check_rarg('lp_backgr',      self%lp_backgr)
        call check_rarg('lp_ctf_estimate',self%lp_ctf_estimate)
        call check_rarg('lp_discrete',    self%lp_discrete)
        call check_rarg('lpstart_nonuni', self%lpstart_nonuni)
        call check_rarg('lp_pick',        self%lp_pick)
        call check_rarg('lplim_crit',     self%lplim_crit)
        call check_rarg('lpstart',        self%lpstart)
        call check_rarg('lpstop',         self%lpstop)
        call check_rarg('lpstart_ini3D',  self%lpstart_ini3D)
        call check_rarg('lpstop_ini3D',   self%lpstop_ini3D)
        call check_rarg('lpstop2D',       self%lpstop2D)
        call check_rarg('lpthres',        self%lpthres)
        call check_rarg('max_dose',       self%max_dose)
        call check_rarg('moldiam',        self%moldiam)
        call check_rarg('moldiam_max',    self%moldiam_max)
        call check_rarg('moldiam_refine', self%moldiam_refine)
        call check_rarg('moldiam_ring',   self%moldiam_ring)
        call check_rarg('msk',            self%msk)
        call check_rarg('msk_crop',       self%msk_crop)
        call check_rarg('mskdiam',        self%mskdiam)
        call check_rarg('ndev',           self%ndev)
        call check_rarg('ndev2D',         self%ndev2D)
        call check_rarg('nsig',           self%nsig)
        call check_rarg('osmpd',          self%osmpd)
        call check_rarg('overlap',        self%overlap)
        call check_rarg('phranlp',        self%phranlp)
        call check_rarg('pool_threshold_factor', self%pool_threshold_factor)
        call check_rarg('prob_athres',    self%prob_athres)
        call check_rarg('res_target',     self%res_target)
        call check_rarg('scale',          self%scale)
        call check_rarg('sherr',          self%sherr)
        call check_rarg('smpd',           self%smpd)
        call check_rarg('smpd_crop',      self%smpd_crop)
        call check_rarg('smpd_target',    self%smpd_target)
        call check_rarg('sigma',          self%sigma)
        call check_rarg('snr',            self%snr)
        call check_rarg('snr_noise_reg',  self%snr_noise_reg)
        call check_rarg('stoch_rate',     self%stoch_rate)
        call check_rarg('stream_mean_threshold',    self%stream_mean_threshold)
        call check_rarg('stream_rel_var_threshold', self%stream_rel_var_threshold)
        call check_rarg('stream_abs_var_threshold', self%stream_abs_var_threshold)
        call check_rarg('stream_tvd_theshold',      self%stream_tvd_theshold)
        call check_rarg('stream_minmax_threshold',  self%stream_minmax_threshold)
        call check_rarg('tau',            self%tau)
        call check_rarg('tilt_thres',     self%tilt_thres)
        call check_rarg('thres',          self%thres)
        call check_rarg('total_dose',     self%total_dose)
        call check_rarg('trs',            self%trs)
        call check_rarg('motion_correctftol', self%motion_correctftol)
        call check_rarg('motion_correctgtol', self%motion_correctgtol)
        call check_rarg('update_frac',    self%update_frac)
        call check_rarg('ufrac_trec',     self%ufrac_trec)
        call check_rarg('width',          self%width)
        call check_rarg('winsz',          self%winsz)
        call check_rarg('xsh',            self%xsh)
        call check_rarg('ysh',            self%ysh)
        call check_rarg('zsh',            self%zsh)

        !>>> START, EXECUTION RELATED
        ! get cwd
        call simple_getcwd(self%cwd)
        ! update CWD globals in defs
        if( .not. allocated(cwd_glob_orig) ) allocate(cwd_glob_orig, source=trim(self%cwd))
        cwd_glob = trim(self%cwd)
        ! get process ID
        self%pid = get_process_id()
        ! get name of executable
        call get_command_argument(0,self%executable)
        if(len_trim(self%executable) == 0) THROW_HARD('get_command_argument failed; new')
        ! set execution mode (shmem or distr)
        if( cline%defined('part') .and. cline%defined('nparts') )then
            self%l_distr_exec = .true.
            part_glob = self%part
        else
            self%l_distr_exec = .false.
            part_glob = 1
        endif
        l_distr_exec_glob = self%l_distr_exec
        ! get pointer to program user interface
        call get_prg_ptr(self%prg, self%ptr2prg)
        ! look for the last previous execution directory and get next directory number
        if( allocated(self%last_prev_dir) ) deallocate(self%last_prev_dir)
        idir = find_next_int_dir_prefix(self%cwd, self%last_prev_dir)
        ! look for a project file
        if( .not.cline%defined('projfile') )then
            if( allocated(self%last_prev_dir) )then
                call simple_list_files(self%last_prev_dir//'/*.simple', sp_files)
            else
                call simple_list_files('*.simple', sp_files)
            endif
            if( allocated(sp_files) )then
                nsp_files = size(sp_files)
            else
                nsp_files = 0
            endif
        else
            nsp_files = 0
        endif
        if( associated(self%ptr2prg) .and. .not. str_has_substr(self%executable,'private') )then
            ! the associated(self%ptr2prg) condition required for commanders executed within
            ! distributed workflows without invoking simple_private_exec
            self%sp_required = self%ptr2prg%requires_sp_project()
            if( .not.cline%defined('projfile') .and. self%sp_required )then
                ! so that distributed execution can deal with multiple project files (eg scaling)
                ! and simple_exec can also not require a project file
                if( nsp_files > 1 )then
                    write(logfhandle,*) 'Multiple *simple project files detected'
                    do i=1,nsp_files
                        write(logfhandle,*) trim(sp_files(i))
                    end do
                    THROW_HARD('a unique *.simple project could NOT be identified; new')
                endif
            endif
        else
            self%sp_required = .false.
        endif
        if( nsp_files == 0 .and. self%sp_required .and. .not. cline%defined('projfile') )then
            write(logfhandle,*) 'program: ', trim(self%prg), ' requires a project file!'
            write(logfhandle,*) 'cwd:     ', trim(self%cwd)
            THROW_HARD('no *.simple project file identified; new')
        endif
        if( nsp_files == 1 .and. self%sp_required )then
            ! good, we found a single monolithic project file
            ! set projfile and projname fields unless given on command line
            if( .not. cline%defined('projfile') ) self%projfile = trim(sp_files(1))
            self%projname = get_fbody(basename(self%projfile), 'simple')
            ! update command line so that prototype copy in distr commanders transfers the info
            if( .not. cline%defined('projfile') ) call cline%set('projfile', trim(self%projname)//'.simple')
            if( .not. cline%defined('projname') ) call cline%set('projname', trim(self%projname))
        endif
        ! put a full path on projfile
        if( self%projfile .ne. '' )then
            if( file_exists(self%projfile) )then
                absname       = simple_abspath(self%projfile,errmsg='simple_parameters::new 1')
                self%projfile = trim(absname)
                self%projname = get_fbody(basename(self%projfile), 'simple')
            endif
        endif
        ! execution directory
        if( self%mkdir .eq. 'yes' )then
            if( associated(self%ptr2prg) .and. .not. str_has_substr(self%executable,'private') )then
                if( trim(self%prg) .eq. 'mkdir' )then
                    self%exec_dir = int2str(idir)//'_'//trim(self%dir)
                else if( cline%defined('dir_exec') )then
                    if( trim(basename(self%executable)).eq.'simple_stream' )then
                        ! to allow for specific restart strategy
                        self%exec_dir = trim(self%dir_exec)
                    else
                        self%exec_dir = int2str(idir)//'_'//trim(self%dir_exec)
                    endif
                else
                    if(self%outdir .eq. '') then
                        self%exec_dir = int2str(idir)//'_'//trim(self%prg)
                    else
                        ! To allow manual selection of output directory name
                        self%exec_dir = trim(adjustl(self%outdir))
                    end if
                endif
                ! make execution directory
                call simple_mkdir( filepath(PATH_HERE, trim(self%exec_dir)), errmsg="parameters:: new 2")
                if( trim(self%prg) .eq. 'mkdir' ) return
                write(logfhandle,'(a)') '>>> EXECUTION DIRECTORY: '//trim(self%exec_dir)
                ! change to execution directory directory
                call simple_chdir( filepath(PATH_HERE, trim(self%exec_dir)), errmsg="parameters:: new 3")
                if( self%sp_required )then
                    ! copy the project file
                    call simple_copy_file(trim(self%projfile), filepath(PATH_HERE, basename(self%projfile)))
                    ! update the projfile/projname
                    self%projfile = filepath(PATH_HERE, basename(self%projfile))
                    absname       = simple_abspath(self%projfile,errmsg='simple_parameters::new 4')
                    self%projfile = trim(absname)
                    self%projname = get_fbody(basename(self%projfile), 'simple')
                    ! so the projfile in cline and parameters are consistent
                    call cline%set('projfile', self%projfile)
                    ! cwd of SP-project will be updated in the builder
                endif
                ! get new cwd
                call simple_getcwd(self%cwd)
                cwd_glob = trim(self%cwd)
            endif
        endif
        ! open log file for write
        if( .not. str_has_substr(self%executable,'private') .and. STDOUT2LOG )then
            ! this is NOT a simple_private_exec execution but a simple_exec or simple_distr_exec one
            ! open the log file
            call fopen(logfhandle, status='replace', file=LOGFNAME, action='write')
        endif
        !>>> END, EXECUTION RELATED

        !>>> START, SANITY CHECKING AND PARAMETER EXTRACTION FROM ORITAB(S)/VOL(S)/STACK(S)
        ! determines whether at least one volume is on the cmdline
        vol_defined = .false.
        do i=1,size(vol_defined)
            if( cline%defined( trim('vol')//int2str(i) ))then
                vol_defined(i) = .true.
            endif
        enddo
        if( any(vol_defined) )then
            do i=1,size(vol_defined)
                if(vol_defined(i))call check_vol(self%vols(i))
            end do
        endif
        ! check inputted mask vols
        if( cline%defined('msklist') )then
            if( nlines(self%msklist)< MAXS ) call read_masks
        endif
        ! no stack given, get ldim from volume if present
        if( self%stk .eq. '' .and. cline%defined('vol_even') )then
            call find_ldim_nptcls(self%vol_even, self%ldim, ifoo)
            self%box      = self%ldim(1)
            if( .not.cline%defined('box_crop') ) self%box_crop = self%box
        else if( self%stk .eq. '' .and. vol_defined(1) )then
            call find_ldim_nptcls(self%vols(1), self%ldim, ifoo)
            self%box      = self%ldim(1)
            if( .not.cline%defined('box_crop') ) self%box_crop = self%box
        endif
        ! no stack given, no vol given, get ldim from mskfile if present
        if( self%stk .eq. '' .and. .not. vol_defined(1) .and. self%mskfile .ne. '' )then
            call find_ldim_nptcls(self%mskfile, self%ldim, ifoo)
            self%box      = self%ldim(1)
            if( .not.cline%defined('box_crop') ) self%box_crop = self%box
        endif
        ! directories
        if( self%mkdir.eq.'yes' )then
            if( self%dir_movies(1:1).ne.PATH_SEPARATOR )self%dir_movies = PATH_PARENT//trim(self%dir_movies)
            if( self%dir_target(1:1).ne.PATH_SEPARATOR )self%dir_target = PATH_PARENT//trim(self%dir_target)
        endif
        ! project file segment
        if( cline%defined('oritype') )then
            ! this determines the spproj_iseg
            select case(trim(self%oritype))
                case('mic')
                    self%spproj_iseg = MIC_SEG
                case('stk')
                    self%spproj_iseg = STK_SEG
                case('ptcl2D')
                    self%spproj_iseg = PTCL2D_SEG
                case('cls2D')
                    self%spproj_iseg = CLS2D_SEG
                case('cls3D')
                    self%spproj_iseg = CLS3D_SEG
                case('ptcl3D')
                    self%spproj_iseg = PTCL3D_SEG
                case('out')
                    self%spproj_iseg = OUT_SEG
                case('optics')
                    self%spproj_iseg = OPTICS_SEG       
                case('projinfo')
                    self%spproj_iseg = PROJINFO_SEG
                case('jobproc')
                    self%spproj_iseg = JOBPROC_SEG
                case('compenv')
                    self%spproj_iseg = COMPENV_SEG
                case DEFAULT
                    write(logfhandle,*) 'oritype: ', trim(self%oritype)
                    THROW_HARD('unsupported oritype; new')
            end select
        else
            self%oritype     = 'ptcl3D'
            self%spproj_iseg = PTCL3D_SEG
        endif
        ! take care of nptcls etc.
        if( file_exists(trim(self%projfile)) )then ! existence should be the only requirement here (not sp_required)
            ! or the private_exec programs don't get what they need
            ! get nptcls/box/smpd from project file
            if( self%stream.eq.'no' )then
                if( self%spproj_iseg==OUT_SEG .or. self%spproj_iseg==CLS3D_SEG)then
                    call spproj%read_segment('out', self%projfile)
                    call spproj%get_imginfo_from_osout(smpd, box, nptcls)
                    call spproj%kill
                    if( .not.cline%defined('smpd'))     self%smpd      = smpd
                    if( .not.cline%defined('box'))      self%box       = box
                    if( .not.cline%defined('nptcls'))   self%nptcls    = nptcls
                else
                    call bos%open(trim(self%projfile)) ! projfile opened here
                    ! nptcls
                    if( .not. cline%defined('nptcls') ) self%nptcls = bos%get_n_records(self%spproj_iseg)
                    ! smpd/box
                    call o%new(is_ptcl=.false.)
                    select case(self%spproj_iseg)
                        case(MIC_SEG)
                            call bos%read_first_segment_record(MIC_SEG, o)
                        case DEFAULT
                            call bos%read_first_segment_record(STK_SEG, o)
                    end select
                    if( o%isthere('smpd') .and. .not. cline%defined('smpd') ) self%smpd = o%get('smpd')
                    if( o%isthere('box')  .and. .not. cline%defined('box')  ) self%box  = nint(o%get('box'))
                    call o%kill
                endif
            else
                ! nothing to do for streaming, values set at runtime
            endif
            if( .not.bos%is_opened() ) call bos%open(trim(self%projfile)) ! projfile opened here
            ! CTF plan
            select case(trim(self%oritype))
                case('ptcl2D', 'ptcl3D')
                    call bos%read_first_segment_record(STK_SEG, o)
            end select
            if( .not. cline%defined('ctf') )then
                if( o%exists() )then
                    if( o%isthere('ctf') )then
                        call o%getter('ctf', ctfflag)
                        self%ctf = trim(ctfflag)
                    endif
                endif
            endif
            if( .not. cline%defined('phaseplate') )then
                if( o%isthere('phaseplate') )then
                    call o%getter('phaseplate', phaseplate)
                    self%phaseplate   = trim(phaseplate)
                    self%l_phaseplate = trim(self%phaseplate).eq.'yes'
                else
                    self%phaseplate   = 'no'
                    self%l_phaseplate = .false.
                endif
            else
                self%l_phaseplate = trim(self%phaseplate).eq.'yes'
            endif
            call bos%close
        else if( self%stk .ne. '' )then
            if( file_exists(self%stk) )then
                if( .not. cline%defined('nptcls') )then
                    ! get number of particles from stack
                    call find_ldim_nptcls(self%stk, lfoo, self%nptcls)
                endif
            else
                write(logfhandle,'(a,1x,a)') 'Inputted stack (stk) file does not exist!', trim(self%stk)
                stop
            endif
        else if( self%oritab .ne. '' )then
            if( .not. cline%defined('nptcls') .and. str_has_substr(self%oritab, '.txt') )then
                ! get # particles from oritab
                self%nptcls = nlines(self%oritab)
            endif
        else if( self%refs .ne. '' )then
            if( file_exists(self%refs) )then
                if( .not. cline%defined('box') )then
                    call find_ldim_nptcls(self%refs, self%ldim, ifoo)
                    self%ldim(3) = 1
                    self%box     = self%ldim(1)
                endif
                if( .not. cline%defined('box_crop') )then
                    call find_ldim_nptcls(self%refs, self%ldim, ifoo)
                    self%ldim(3)  = 1
                    self%box_crop = self%ldim(1)
                endif
            else
                ! we don't check for existence of refs as they can be output as well as input (cavgassemble)
            endif
        endif
        ! smpd_crop/box_crop
        if( .not.cline%defined('box_crop') ) self%box_crop  = self%box
        if( .not.cline%defined('smpd_crop') )then
            if( cline%defined('box_crop') )then
                self%smpd_crop = real(self%box)/real(self%box_crop) * self%smpd
            else
                self%smpd_crop = self%smpd
            endif
        endif
        ! check file formats
        call check_file_formats
        call double_check_file_formats
        ! make file names
        call mkfnames
        ! check box, box_crop
        if( self%box      > 0 .and. self%box      < 26 ) THROW_HARD('box needs to be larger than 26')
        if( self%box_crop > 0 .and. self%box_crop < 26 ) THROW_HARD('box_crop needs to be larger than 26')
        ! set refs_even and refs_odd
        if( cline%defined('refs') )then
            self%refs_even = add2fbody(self%refs, self%ext, '_even')
            self%refs_odd  = add2fbody(self%refs, self%ext, '_odd')
        endif
        ! set vols_even and vols_odd
        def_vol1 = cline%defined('vol1')
        def_even = cline%defined('vol_even')
        def_odd  = cline%defined('vol_odd')
        if( def_vol1 )then
            if( def_even ) THROW_HARD('vol1 and vol_even cannot be simultaneously part of the command line')
            if( def_odd )  THROW_HARD('vol1 and vol_odd cannot be simultaneously part of the command line')
        else
            if( def_even .and. def_odd )then
                if( def_vol1 ) THROW_HARD('vol1 cannot be part of command line when vol_even and vol_odd are')
            else
                if( (def_even.eqv..false.) .and. (def_odd.eqv..false.) )then
                    ! all good
                else
                    THROW_HARD('vol_even and vol_odd must be simultaneously part of the command line')
                endif
            endif
        endif
        if( def_even .or. def_odd .or. def_vol1 )then
            if( def_even .and. def_odd )then
                if( def_vol1 ) THROW_HARD('vol1 cannot be part of command line when vol_even and vol_odd are')
                self%vols_even(1) = trim(self%vol_even)
                self%vols_odd(1)  = trim(self%vol_odd)
                self%vols(1)      = trim(self%vol_even) ! the even volume will substitute the average one in this mode
            else
                if( def_vol1 )then
                    do istate=1,self%nstates
                        self%vols_even(istate) = add2fbody(self%vols(istate), self%ext, '_even')
                        self%vols_odd(istate)  = add2fbody(self%vols(istate), self%ext, '_odd' )
                        if( str_has_substr(self%prg, 'refine') )then
                            if( .not. file_exists(self%vols_even(istate)) ) call simple_copy_file(self%vols(istate), self%vols_even(istate))
                            if( .not. file_exists(self%vols_odd(istate))  ) call simple_copy_file(self%vols(istate), self%vols_odd(istate))
                        endif
                    end do
                else
                    THROW_HARD('both vol_even and vol_odd need to be part of the command line')
                endif
            endif
        endif
        !<<< END, SANITY CHECKING AND PARAMETER EXTRACTION FROM VOL(S)/STACK(S)

        !>>> START, PARALLELISATION-RELATED
        ! set split mode (even)
        self%split_mode = 'even'
        nparts_set      = .false.
        if( cline%defined('nparts') ) nparts_set  = .true.
        ! set length of number string for zero padding
        if( .not. cline%defined('numlen') )then
            if( nparts_set ) self%numlen = len(int2str(self%nparts))
        endif
        ! ldim & box from stack
        call set_ldim_box_from_stk
        ! fractional search and volume update
        if( self%update_frac <= .99)then
            self%l_update_frac = .true.
            self%l_trail_rec   = trim(self%trail_rec).eq.'yes'
        else
            self%update_frac   = 1.0
            self%l_update_frac = .false.
            if( trim(self%trail_rec).eq.'yes' )then
                self%l_trail_rec = .true.
            else
                self%l_trail_rec = .false.
            endif
        endif
        ! set frac_best flag
        self%l_frac_best  = self%frac_best  <= 0.99
        ! set frac_worst flag
        self%l_frac_worst = self%frac_worst <= 0.99
        ! set greedy sampling flag
        self%l_greedy_smpl = trim(self%greedy_sampling).eq.'yes'
        ! set fillin sampling flag
        self%l_fillin = trim(self%fillin).eq. 'yes'
        if( .not. cline%defined('ncunits') )then
            ! we assume that the number of computing units is equal to the number of partitions
            self%ncunits = self%nparts
        endif
        ! OpenMP threads
        if( cline%defined('nthr') )then
            nthr = cline%get_iarg('nthr')
            if( nthr == 0 )then
                !$ self%nthr = omp_get_max_threads()
                !$ call omp_set_num_threads(self%nthr)
            else
                !$ call omp_set_num_threads(self%nthr)
            endif
        else
            !$ self%nthr = omp_get_max_threads()
            !$ call omp_set_num_threads(self%nthr)
        endif
        nthr_glob = self%nthr
        ! job scheduling management
        if( self%walltime <= 0 )then
            THROW_HARD('Walltime cannot be negative!')
        else if( self%walltime > WALLTIME_DEFAULT )then
            THROW_WARN('Walltime is superior to maximum allowed of 23h59mins, resetting it to this value')
            self%walltime = WALLTIME_DEFAULT
        endif
        !<<< END, PARALLELISATION-RELATED

        !>>> START, IMAGE-PROCESSING-RELATED
        if( .not. cline%defined('xdim') ) self%xdim = self%box/2
        self%xdimpd     = round2even(self%alpha*real(self%box/2))
        self%boxpd      = 2*self%xdimpd
        self%box_croppd = 2*round2even(self%alpha*real(self%box_crop/2))
        ! set derived Fourier related variables
        self%dstep   = real(self%box-1)*self%smpd                  ! first wavelength of FT
        self%dsteppd = real(self%boxpd-1)*self%smpd                ! first wavelength of padded FT
        if( .not. cline%defined('hp') ) self%hp = 0.5*self%dstep   ! high-pass limit
        self%fny = 2.*self%smpd                                    ! Nyqvist limit
        if( .not. cline%defined('lpstop') )then                    ! default highest resolution lp
            self%lpstop = self%fny                                 ! deafult lpstop
        endif
        if( self%fny > 0. ) self%tofny = nint(self%dstep/self%fny) ! Nyqvist Fourier index
        self%lpstart = max(self%lpstart, self%fny)
        self%lpstop  = max(self%lpstop,  self%fny)
        ! set 2D low-pass limits and smpd_targets 4 scaling
        self%lplims2D(1)       = max(self%fny, self%lpstart)
        self%lplims2D(2)       = max(self%fny, self%lplims2D(1) - (self%lpstart - self%lpstop)/2.)
        self%lplims2D(3)       = max(self%fny, self%lpstop)
        self%smpd_targets2D(1) = min(MAX_SMPD, self%lplims2D(2)*LP2SMPDFAC2D)
        self%smpd_targets2D(2) = min(MAX_SMPD, self%lplims2D(3)*LP2SMPDFAC2D)
        ! check scale factor sanity
        if( self%scale < 0.00001 ) THROW_HARD('scale out if range, should be > 0; new')
        ! set default msk value
        if( cline%defined('msk') )then
            THROW_HARD('msk (mask radius in pixels) is deprecated! Use mskdiam (mask diameter in A)')
        endif
        mskdiam_default = (real(self%box) - COSMSKHALFWIDTH) * self%smpd
        msk_default     = round2even((real(self%box) - COSMSKHALFWIDTH) / 2.)
        if( cline%defined('mskdiam') )then
            self%msk = round2even((self%mskdiam / self%smpd) / 2.)
            if( self%msk > msk_default )then
                if( msk_default > 0. )then
                    THROW_WARN('Mask diameter too large, falling back on default value')
                    self%mskdiam = mskdiam_default
                    self%msk     = msk_default
                endif
            endif
             if( self%msk < 0.1 )then
                if( msk_default > 0. )then
                    THROW_WARN('Mask diameter zero, falling back on default value')
                    self%mskdiam = mskdiam_default
                    self%msk     = msk_default
                endif
            endif
        else
            self%mskdiam = mskdiam_default
            self%msk     = msk_default
        endif
        if( self%box > 0 )then
            if( .not.cline%defined('msk_crop') )then
                self%msk_crop = min(round2even((real(self%box_crop)-COSMSKHALFWIDTH)/2.),&
                    &round2even(self%msk * real(self%box_crop) / real(self%box)))
            endif
        endif
        ! automasking options
        self%l_filemsk = .false.
        if( cline%defined('mskfile') )then
            if( .not.file_exists(trim(self%mskfile)) ) THROW_HARD('Inputted mask file '//trim(self%mskfile)//' does not exist')
            self%l_filemsk = .true.  ! indicate file is inputted
        endif
        ! comlin generation
        select case(trim(self%ref_type))
        case('clin', 'vol')
            self%l_comlin = .true.  ! 3D
        case('cavg')
            self%l_comlin = .false. ! 2D
        case DEFAULT
            THROW_HARD('Unsupported REF_TYPE argument: '//trim(self%ref_type))
        end select
        ! image normalization
        self%l_noise_norm = trim(self%noise_norm).eq.'yes'
        ! set lpset flag
        self%l_lpset  = cline%defined('lp')
        ! set envfsc flag
        self%l_envfsc = self%envfsc .ne. 'no'
        ! set reference filtering flag
        if( cline%defined('icm') ) self%l_icm = (trim(self%icm).eq.'yes')
        ! set correlation weighting scheme
        self%l_corrw = self%wcrit .ne. 'no'
        ! set wiener mode
        self%l_wiener_part = str_has_substr(trim(self%wiener), 'partial')
        if( self%l_corrw )then
            select case(trim(self%wcrit))
                case('softmax')
                    self%wcrit_enum = CORRW_CRIT
                case('zscore')
                    self%wcrit_enum = CORRW_ZSCORE_CRIT
                case('sum')
                    self%wcrit_enum = RANK_SUM_CRIT
                case('cen')
                    self%wcrit_enum = RANK_CEN_CRIT
                case('exp')
                    self%wcrit_enum = RANK_EXP_CRIT
                case('inv')
                    self%wcrit_enum = RANK_INV_CRIT
                case DEFAULT
                    THROW_HARD('unsupported correlation weighting method')
            end select
        endif
        ! set graphene flag
        self%l_graphene = self%graphene_filt .ne. 'no'
        ! checks automask related values
        if( cline%defined('mskfile') )then
            if( .not. file_exists(self%mskfile) )then
                write(logfhandle,*) 'file: ', trim(self%mskfile)
                THROW_HARD('input mask file not in cwd')
            endif
        endif
        ! focused masking
        self%l_focusmsk = .false.
        if( cline%defined('focusmsk') )then
            THROW_HARD('focusmsk (focused mask radius in pixels) is deprecated! Use focusmskdiam (focused mask diameter in A)')
        endif
        if( cline%defined('focusmskdiam') )then
            if( .not.cline%defined('mskdiam') )then
                THROW_HARD('mskdiam must be provided together with focusmskdiam')
            endif
            self%focusmsk = round2even((self%focusmskdiam / self%smpd) / 2.)
            self%l_focusmsk = .true.
        else
            self%focusmsk = self%msk
        endif
        ! scaling stuff
        self%l_autoscale = .false.
        if( self%autoscale .eq. 'yes' ) self%l_autoscale = .true.
        if( .not. cline%defined('newbox') )then
            ! set newbox if scale is defined
            if( cline%defined('scale') )then
                self%newbox = find_magic_box(nint(self%scale*real(self%box)))
            endif
        endif
        ! set newbox if scale is defined
        self%kfromto             = 2
        if( cline%defined('hp') ) self%kfromto(1) = max(2,int(self%dstep/self%hp)) ! high-pass Fourier index set according to hp
        self%kfromto(2)          = int(self%dstep/self%lp)          ! low-pass Fourier index set according to lp
        self%lp                  = max(self%fny,self%lp)            ! lowpass limit
        if( .not. cline%defined('ydim') ) self%ydim = self%xdim
        ! set ldim
        if( cline%defined('xdim') ) self%ldim = [self%xdim,self%ydim,1]
        ! box on the command line overrides all other ldim setters
        if( cline%defined('box')  ) self%ldim = [self%box,self%box,1]
        ! set eullims
        self%eullims(:,1) = 0.
        self%eullims(:,2) = 359.99
        self%eullims(2,2) = 180.
        ! set default size of random sample
        if( .not. cline%defined('nran') )then
            self%nran = self%nptcls
        endif
        ! define clipped box if not given
        if( .not. cline%defined('clip') )then
            self%clip = self%box
        endif
        ! error check ncls
        if( file_exists(self%refs) )then
            ! get number of particles from stack
            call find_ldim_nptcls(self%refs, lfoo, ncls)
            if( cline%defined('ncls') )then
                if( ncls /= self%ncls )then
                    write(logfhandle,*)'ncls in ',trim(self%refs),' : ',ncls
                    write(logfhandle,*)'self%ncls : ',self%ncls
                    THROW_HARD('input number of clusters (ncls) not consistent with the number of references in stack (p%refs)')
                endif
            else
                self%ncls = ncls
            endif
        endif
        ! interpolation function
        select case(trim(self%interpfun))
            case('kb','linear', 'nn')
                ! supported
            case DEFAULT
                THROW_HARD('Unsupported interpolation function')
        end select
        ! set remap_clusters flag
        self%l_remap_cls = .false.
        if( self%remap_cls .eq. 'yes' ) self%l_remap_cls = .true.
        ! set to particle index if not defined in cmdlin
        if( .not. cline%defined('top') ) self%top = self%nptcls
        ! set the number of input orientations
        if( .not. cline%defined('noris') ) self%noris = self%nptcls
        ! Set molecular diameter
        if( .not. cline%defined('moldiam') )then
            self%moldiam = 2. * self%msk * self%smpd
        endif
        ! objective function used
        select case(trim(self%objfun))
            case('cc')
                self%cc_objfun = OBJFUN_CC
            case('euclid')
                self%cc_objfun = OBJFUN_EUCLID
            case DEFAULT
                write(logfhandle,*) 'objfun flag: ', trim(self%objfun)
                THROW_HARD('unsupported objective function; new')
        end select
        ! dose weighing
        self%l_dose_weight = cline%defined('total_dose')
        if( self%fraction_dose_target < 0.01 ) THROW_HARD('Invalid : fraction_dose_target'//real2str(self%fraction_dose_target))
        ! eer sanity checks
        self%l_eer_fraction = cline%defined('eer_fraction')
        select case(self%eer_upsampling)
            case(1,2)
                ! supported
            case DEFAULT
                THROW_HARD('eer_upsampling not supported: '//int2str(self%eer_upsampling))
        end select
        ! FILTERS
        ! sigma needs flags etc.
        select case(self%cc_objfun)
            case(OBJFUN_EUCLID)
                self%l_needs_sigma = .true.
            case(OBJFUN_CC)
                self%l_needs_sigma = (trim(self%needs_sigma).eq.'yes')
        end select
        ! type of sigma estimation (group or global)
        select case(trim(self%sigma_est))
            case('group')
                self%l_sigma_glob = .false.
            case('global')
                self%l_sigma_glob = .true.
            case DEFAULT
                THROW_HARD(trim(self%sigma_est)//' is not a supported sigma estimation approach')
        end select
        ! k-weighted cc option
        select case(trim(self%kweight))
            case('all')
                self%l_kweight       = .true. ! class/projection direction selection
                self%l_kweight_rot   = .true. ! in-plane rotation
                self%l_kweight_shift = .true. ! shift search
            case('cls')
                self%l_kweight       = .true.
                self%l_kweight_rot   = .false.
                self%l_kweight_shift = .false.
            case('inpl')
                self%l_kweight       = .false.
                self%l_kweight_rot   = .true.
                self%l_kweight_shift = .true.
            case('none')
                self%l_kweight       = .false.
                self%l_kweight_rot   = .false.
                self%l_kweight_shift = .false.
            case DEFAULT
                self%l_kweight       = .false.
                self%l_kweight_rot   = .false.
                self%l_kweight_shift = .true.
        end select
        select case(trim(self%kweight_chunk))
            case('all','inpl','none','default')
                ! all valid
            case DEFAULT
                THROW_HARD('INVALID KWEIGHT_CHUNK ARGUMENT')
        end select
        select case(trim(self%kweight_pool))
            case('all','inpl','none','default')
                ! all valid
            case DEFAULT
                THROW_HARD('INVALID KWEIGHT_POOL ARGUMENT')
        end select
        ! automatically estimated lp
        self%l_lpauto = trim(self%lp_auto).ne.'no'
        select case(trim(self%lp_auto))
            case('yes')
                ! this is an lpset mode (no eo alignment), so update flag
                self%l_lpset = .true.
            case('no')
                ! don't touch l_lpset flag
            case('fsc')
                ! low-pass limit set from FSC (but no eo alignment)
                self%l_lpset = .true.
            case DEFAULT
                THROW_HARD('unsupported lp_auto flag')
        end select        
        ! reg options
        self%l_noise_reg = cline%defined('snr_noise_reg')
        if( self%l_noise_reg )then
            self%eps_bounds(2) = self%snr_noise_reg
            self%eps_bounds(1) = self%eps_bounds(2) / 2.
            self%eps           = self%eps_bounds(1)
        endif
        self%l_lam_anneal = trim(self%lam_anneal).eq.'yes'
        ! ML regularization
        self%l_ml_reg = trim(self%ml_reg).eq.'yes'
        if( self%l_ml_reg )then
            self%l_ml_reg = self%l_needs_sigma .or. self%cc_objfun==OBJFUN_EUCLID
        endif
        ! resolution limit
        self%l_incrreslim = trim(self%incrreslim) == 'yes' .and. .not.self%l_lpset
        ! linearized states
        self%l_linstates = trim(self%linstates) == 'yes'
        ! refs delinearization
        self%l_refs_delin = trim(self%refs_delin) == 'yes'
        ! B-facor
        self%l_bfac = cline%defined('bfac')
        ! smoothing extension
        is_2D = .false.
        if( str_has_substr(self%prg, '2D') ) is_2D = .true.
        ! atoms
        if( cline%defined('element') )then
            if( .not. atoms_obj%element_exists(self%element) )then
                THROW_HARD('Element: '//trim(self%element)//' unsupported for now')
            endif
        endif
        ! sanity check imgkind
        select case(trim(self%imgkind))
            case('movie','mic','ptcl','cavg','cavg3D','vol','vol_cavg')
                ! alles gut!
            case DEFAULT
                write(logfhandle,*) 'imgkind: ', trim(self%imgkind)
                THROW_HARD('unsupported imgkind; new')
        end select
        ! refine flag dependent things
        ! -- neigh defaults
        self%l_neigh = .false.
        if( str_has_substr(self%refine, 'neigh') )then
            if( .not. cline%defined('nspace') )then
                self%nspace = 20000
            else
                self%nspace = max(self%nspace, 20000)
            endif
            if( .not. cline%defined('athres') ) self%athres = 10.
            self%l_neigh = .true.
        endif
        ! -- shift defaults
        if( .not. cline%defined('trs') )then
            select case(trim(self%refine))
                case('snhc','snhc_smpl')
                    self%trs = 0.
                case DEFAULT
                    self%trs = MINSHIFT
            end select
        endif
        self%trs = abs(self%trs)
        self%l_doshift = .true.
        if( self%trs < 0.1 )then
            self%trs       = 0.
            self%l_doshift = .false.
        endif
        self%l_prob_inpl = trim(self%prob_inpl).eq.'yes'
        self%l_prob_sh   = trim(self%prob_sh)  .eq.'yes'
        self%l_sh_first  = trim(self%sh_first) .eq.'yes'
        ! motion correction
        if( self%mcpatch.eq.'yes' .and. self%nxpatch*self%nypatch<=1 ) self%mcpatch = 'no'
        if( self%mcpatch.eq.'no' )then
            self%nxpatch = 0
            self%nypatch = 0
        endif
        select case(trim(self%mcconvention))
            case('simple','unblur','motioncorr','relion','first','central','cryosparc','cs')
            case DEFAULT
                THROW_HARD('Invalid entry for MCCONVENTION='//trim(self%mcconvention))
        end select
        ! initial class generation
        if( cline%defined('cls_init') )then
            select case(trim(self%cls_init))
            case('ptcl','rand','randcls')
                ! supported
            case DEFAULT
                THROW_HARD('Unsupported mode of initial class generation CLS_INIT='//trim(self%cls_init))
            end select
        endif
        !>>> END, IMAGE-PROCESSING-RELATED
        ! set global pointer to instance
        ! first touch policy here
        if( .not. associated(params_glob) ) params_glob => self
        if( L_VERBOSE_GLOB ) write(logfhandle,'(A)') '>>> DONE PROCESSING PARAMETERS'

    contains

        subroutine check_vol( volname, is_even )
            character(len=*),  intent(inout) :: volname
            logical, optional, intent(in)    :: is_even
            character(len=STDLEN)            :: key
            character(len=LONGSTRLEN)        :: vol
            character(len=:), allocatable    :: abs_volname
            if( present(is_even) )then
                if( is_even )then
                    key = 'vol_even'
                else
                    key = 'vol_odd'
                endif
            else
                key = 'vol'//int2str(i)
            endif
            if( cline%defined(key) )then
                vol = trim(cline%get_carg(key))
                if( vol(1:1).eq.PATH_SEPARATOR )then
                    ! already in absolute path format
                    call check_file(key, volname, notAllowed='T')
                    if( .not. file_exists(volname) )then
                        write(logfhandle,*) 'Input volume:', trim(volname), ' does not exist! 1'
                        stop
                    endif
                else
                    if( self%mkdir .eq. 'yes' )then
                        ! with respect to parent folder
                        ! needs to be done here because not part of the check_file list
                        vol = PATH_PARENT//trim(vol)
                        call cline%set(key, vol)
                    endif
                    call check_file(key, volname, notAllowed='T')
                    if( .not. file_exists(volname) )then
                        write(logfhandle,*) 'Input volume:', trim(volname), ' does not exist! 2'
                        stop
                    else
                        abs_volname = simple_abspath(volname,'parameters :: check_vol', check_exists=.false.)
                        if( len_trim( abs_volname) > LONGSTRLEN )then
                            THROW_HARD('argument too long: '//trim( abs_volname)//' new :: check_vol')
                        endif
                        volname = trim(abs_volname)
                        call cline%set(key, trim(volname))
                        deallocate(abs_volname)
                    endif
                endif
            endif
        end subroutine check_vol

        subroutine read_masks
            character(len=LONGSTRLEN)     :: filename, name
            character(len=:), allocatable :: abs_name
            integer                       :: nl, fnr, i, io_stat
            filename = cline%get_carg('msklist')
            if( filename(1:1).ne.PATH_SEPARATOR )then
                if( self%mkdir.eq.'yes' ) filename = PATH_PARENT//trim(filename)
            endif
            nl = nlines(filename)
            call fopen(fnr, file=filename, iostat=io_stat)
            if(io_stat /= 0) call fileiochk("parameters ; read_masks error opening "//trim(filename), io_stat)
            do i=1,nl
                read(fnr,*, iostat=io_stat) name
                if(io_stat /= 0) call fileiochk("parameters ; read_masks error reading "//trim(filename), io_stat)
                if( name .ne. '' )then
                    abs_name = simple_abspath(name,errmsg='parameters :: read_masks', check_exists=.false.)
                    self%mskvols(i) = trim(abs_name)
                    deallocate(abs_name)
                endif
            end do
            call fclose(fnr)
        end subroutine read_masks

        subroutine check_file( file, var, allowed1, allowed2, notAllowed )
            character(len=*),           intent(in)    :: file
            character(len=*),           intent(inout) :: var
            character(len=1), optional, intent(in)    :: allowed1, allowed2, notAllowed
            character(len=:), allocatable :: abspath_file
            character(len=1)              :: file_descr
            logical                       :: raise_exception
            if( cline%defined(file) )then
                var             = trim(cline%get_carg(file))
                file_descr      = fname2format(var)
                raise_exception = .false.
                if( present(allowed1) )then
                    if( present(allowed2) )then
                        if( allowed1 == file_descr .or. allowed2 == file_descr )then
                            ! all good
                        else
                            raise_exception = .true.
                        endif
                    else
                        if( allowed1 /= file_descr ) raise_exception = .true.
                    endif
                endif
                if( present(notAllowed) )then
                    if( notAllowed == file_descr ) raise_exception = .true.
                endif
                if( raise_exception )then
                    write(logfhandle,*) 'This format: ', file_descr, ' is not allowed for this file: ', trim(var)
                    write(logfhandle,*) 'flag:', trim(file)
                    stop
                endif
                select case(file_descr)
                    case ('I')
                        THROW_HARD('Support for IMAGIC files is not implemented!')
                    case ('M')
                        ! MRC files are supported
                        cntfile = cntfile+1
                        checkupfile(cntfile) = 'M'
                    case ('S')
                        ! SPIDER files are supported
                        cntfile = cntfile+1
                        checkupfile(cntfile) = 'S'
                    case ('N')
                        write(logfhandle,*) 'file: ', trim(var)
                        THROW_HARD('This file format is not supported by SIMPLE')
                    case ('T','B','P','O', 'R')
                        ! text files are supported
                        ! binary files are supported
                        ! PDB files are supported
                        ! *.simple project files are supported
                        ! R=*.star format -- in testing
#ifdef USING_TIFF
                    case('J')
                        ! TIFF
                        cntfile = cntfile+1
                        checkupfile(cntfile) = 'J'
                    case('L')
                        ! .gain, which is a single tiff image
                        cntfile = cntfile+1
                        checkupfile(cntfile) = 'L'
                    case('K')
                        ! .eer
                        cntfile = cntfile+1
                        checkupfile(cntfile) = 'K'
#endif
                    case DEFAULT
                        write(logfhandle,*) 'file: ', trim(var)
                        THROW_HARD('This file format is not supported by SIMPLE')
                end select
                if( file_exists(var) )then
                    ! updates name to include absolute path
                    abspath_file = simple_abspath(var,errmsg='parameters :: check_file', check_exists=.false.)
                    if( len_trim(abspath_file) > LONGSTRLEN )then
                        THROW_HARD('argument too long: '//trim(abspath_file)//' new :: checkfile')
                    endif
                    var = trim(abspath_file)
                    call cline%set(file,trim(var))
                    deallocate(abspath_file)
                endif
            endif
        end subroutine check_file

        subroutine check_dir( dir, var )
            character(len=*), intent(in)    :: dir
            character(len=*), intent(inout) :: var
            character(len=:), allocatable   :: abspath_dir
            if( cline%defined(dir) )then
                var = trim(cline%get_carg(dir))
                if( file_exists(var) )then
                    ! updates name to include absolute path
                    abspath_dir = simple_abspath(var,errmsg='parameters :: check_dir', check_exists=.false.)
                    if( len_trim(abspath_dir) > LONGSTRLEN )then
                        THROW_HARD('argument too long: '//trim(abspath_dir)//' new :: checkdir')
                    endif
                    var = trim(abspath_dir)
                    call cline%set(dir,trim(var))
                    deallocate(abspath_dir)
                endif
            endif
        end subroutine check_dir

        subroutine check_file_formats
            integer :: i, j
            if( cntfile > 0 )then
                do i=1,cntfile
                    do j=1,cntfile
                        if( i == j ) cycle
                        if( checkupfile(i) == checkupfile(j) ) cycle ! all ok
                    end do
                end do
                call self%set_img_format(checkupfile(1))
            endif
        end subroutine check_file_formats

        subroutine double_check_file_formats
            character(len=STDLEN) :: fname
            character(len=1)      :: form
            integer :: funit, io_stat
            if( cntfile == 0 )then
                if( cline%defined('filetab') )then
                    call fopen(funit, status='old', file=self%filetab, iostat=io_stat)
                    call fileiochk("In parameters:: double_check_file_formats fopen failed "//trim(self%filetab) , io_stat)
                    read(funit,'(a256)') fname
                    form = fname2format(fname)
                    call fclose(funit)
                    call self%set_img_format(form)
                endif
            endif
        end subroutine double_check_file_formats

        subroutine mkfnames
            if( .not. cline%defined('outstk')  ) self%outstk  = 'outstk'//self%ext
            if( .not. cline%defined('outvol')  ) self%outvol  = 'outvol'//self%ext
        end subroutine mkfnames

        subroutine check_carg( carg, var )
            character(len=*), intent(in)    :: carg
            character(len=*), intent(inout) :: var
            if( cline%defined(carg) )then
                var = cline%get_carg(carg)
            endif
        end subroutine check_carg

        subroutine check_iarg( iarg, var )
            character(len=*), intent(in)  :: iarg
            integer,          intent(out) :: var
            if( cline%defined(iarg) )then
                var = cline%get_iarg(iarg)
            endif
        end subroutine check_iarg

        subroutine check_rarg( rarg, var )
            character(len=*), intent(in)  :: rarg
            real,             intent(out) :: var
            if( cline%defined(rarg) )then
                var = cline%get_rarg(rarg)
            endif
        end subroutine check_rarg

        subroutine set_ldim_box_from_stk
            if( cline%defined('stk') )then
                if( file_exists(self%stk) )then
                    if( cline%defined('box') )then
                    else
                        call find_ldim_nptcls(self%stk, self%ldim, ifoo)
                        self%ldim(3) = 1
                        self%box     = self%ldim(1)
                        if( .not.cline%defined('box_crop') ) self%box_crop = self%box
                    endif
                else
                    write(logfhandle,'(a)')      'simple_parameters :: set_ldim_box_from_stk'
                    write(logfhandle,'(a,1x,a)') 'Stack file does not exist!', trim(self%stk)
                    THROW_HARD("set_ldim_box_from_stk")
                endif
            endif
        end subroutine set_ldim_box_from_stk

    end subroutine new

    subroutine set_img_format( self, ext )
        class(parameters), intent(inout) :: self
        character(len=*),  intent(in)    :: ext
        select case(trim(ext))
            case('M','D','B')
                self%ext = '.mrc'
            case('S')
                self%ext = '.spi'
#ifdef USING_TIFF
            case('J','K','L')
                ! for tiff/eer/gain we set .mrc as preferred output format
                self%ext = '.mrc'
#endif
            case DEFAULT
                write(logfhandle,*)'format: ', trim(ext)
                THROW_HARD('This file format is not supported by SIMPLE')
        end select
    end subroutine set_img_format

end module simple_parameters
