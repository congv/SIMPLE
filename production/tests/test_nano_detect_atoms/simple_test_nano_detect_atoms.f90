program simple_test_nano_detect_atoms

include 'simple_lib.f08'
use simple_nano_detect_atoms
use simple_nano_picker_utils
use simple_nanoparticle
use simple_nanoparticle_utils
use simple_image
use simple_parameters
use simple_strings, only: int2str
implicit none
#include "simple_local_flags.inc"
type(nano_picker)        :: test_sim
type(nano_picker)        :: test_exp4
type(nanoparticle)       :: nano
type(image)              :: simulated_NP
real                     :: smpd, dist_thres
character(len=2)         :: element
character(len=100)       :: filename_exp, filename_sim, pdbfile_ref
character(STDLEN)        :: timestr
integer                  :: offset, peak_thres_level, startTime, stopTime, subStart, subStop, ldim(3)
type(parameters), target :: params
logical                  :: denoise
logical                  :: debug

! keeping track of how long program takes
startTime        = real(time())
! Inputs
filename_exp     = 'rec_merged.mrc'
filename_sim     = 'simulated_NP.mrc'
!pdbfile_ref     = 'ATMS.pdb'
pdbfile_ref      = 'reference.pdb'
element          = 'PT'
smpd             = 0.358
offset           = 2
peak_thres_level = 2
dist_thres       = 3.
denoise          = .true.
debug            = .true.

! simulate nanoparticle
! params_glob has to be set because of the way simple_nanoparticle is set up
params_glob => params
params_glob%element = element
params_glob%smpd    = smpd

call nano%new(trim(filename_exp))
call nano%set_atomic_coords(trim(pdbfile_ref))
call nano%simulate_atoms(simatms=simulated_NP)
call simulated_NP%write(trim(filename_sim))
subStart = real(time())

call test_exp4%new(smpd, element, filename_exp, peak_thres_level, offset, denoise)
call test_exp4%simulate_atom()
call test_exp4%setup_iterators()
call test_exp4%match_boxes(circle=.true.)
if (debug) call test_exp4%write_dist(  'corr_dist_before_high_filter.csv','corr'   )
if (debug) call test_exp4%write_dist(   'int_dist_before_high_filter.csv','avg_int')
if (debug) call test_exp4%write_dist('euclid_dist_before_high_filter.csv','euclid' )
!call test_exp4%identify_threshold()
call test_exp4%identify_high_scores(use_zscores=.true.)
if (debug) call test_exp4%write_dist('corr_dist_after_high_filter.csv','corr'   )
if (debug) call test_exp4%write_dist( 'int_dist_after_high_filter.csv','avg_int')
call test_exp4%distance_filter(dist_thres)
if (debug) call test_exp4%write_dist(  'corr_dist_after_dist_filter_high.csv','corr'   )
if (debug) call test_exp4%write_dist(   'int_dist_after_dist_filter_high.csv','avg_int')
if (debug) call test_exp4%write_dist('euclid_dist_after_dist_filter_high.csv','euclid' )
call test_exp4%euclid_filter
if (debug) call test_exp4%write_dist(  'corr_dist_after_euclid_filter.csv','corr'  )
if (debug) call test_exp4%write_dist('euclid_dist_after_euclid_filter.csv','euclid')
call test_exp4%find_centers()
! call test_exp4%remove_outliers_position(10.,'close_atoms_distances.csv')
! if (debug) call test_exp4%write_corr_dist('corr_dist_after_remove_outliers.csv')
! if (debug) call test_exp4%write_int_dist( 'int_dist_after_remove_outliers.csv')
!call test_exp4%refine_threshold(10,pdbfile_ref,max_thres=0.75)
!call test_exp4%write_boximgs(foldername='boximgs')
! OUTPUT FILES
call test_exp4%write_positions_and_scores('pos_and_scores.csv','pixels')
call test_exp4%write_positions_and_scores('pos_and_scores_centers.csv','centers')
call test_exp4%write_positions_and_scores('pos_and_intensities.csv','intensities')
call test_exp4%write_positions_and_scores('pos_and_euclids.csv','euclid')
call test_exp4%write_pdb('experimental_centers')
call test_exp4%compare_pick('experimental_centers.pdb',trim(pdbfile_ref))
call test_exp4%write_NP_image('result.mrc')
!call test_exp4%calc_atom_stats
call test_exp4%kill
subStop = real(time())
print *, 'TEST 1 RUNTIME = ', (subStop - subStart), ' s'
print *, ' '
stopTime = time()
print *, 'TOTAL RUNTIME = ', (stopTime - startTime), ' s'

end program simple_test_nano_detect_atoms