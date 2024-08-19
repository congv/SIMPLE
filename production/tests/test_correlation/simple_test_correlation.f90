program simple_test_correlation
    include 'simple_lib.f08'
    use simple_nanoparticle
    use simple_parameters

    type(nanoparticle) :: nano_new, nano_old ! nano_new is for new atom detection method, nano_old is for old atom detection method
    type(parameters), target :: params
    character(len=100) :: img_filename
    character(len=100) :: new_pdb_filename,  old_pdb_filename
    character(len=100) :: atoms_new_in_old,  atoms_old_in_new
    character(len=100) :: atoms_new_not_old, atoms_old_not_new
    character(len=2)   :: element
    real               :: smpd, mskdiam

    ! files
    img_filename      = 'rec_merged.mrc'
    new_pdb_filename  = 'experimental_centers.pdb'       ! generated by nano_detect_atoms
    old_pdb_filename  = 'rec_merged_ATMS.pdb'            ! generated by identify_atomic_pos
    atoms_new_in_old  = 'common_atoms_01in02.pdb'        ! generated by tseries_atoms_analysis between new_pdb_filename and old_pdb_filename
    atoms_old_in_new  = 'common_atoms_02in01.pdb'        ! generated by tseries_atoms_analysis between new_pdb_filename and old_pdb_filename
    atoms_new_not_old = 'different_atoms_01not_in02.pdb' ! generated by tseries_atoms_analysis between new_pdb_filename and old_pdb_filename
    atoms_old_not_new = 'different_atoms_02not_in01.pdb' ! generated by tseries_atoms_analysis between new_pdb_filename and old_pdb_filename

    ! parameters
    element             = 'Pt'
    smpd                = 0.358
    mskdiam             = 28.4 ! mask diameter in angstroms

    ! must define params_glob attributes because of the way nanoparticle is set up
    params_glob         => params
    params_glob%element = element
    params_glob%smpd    = smpd

    ! initialize nanoparticle objects
    call nano_new%new(trim(img_filename), msk=(mskdiam / smpd)/2)
    call nano_old%new(trim(img_filename), msk=(mskdiam / smpd)/2)

    ! set coordinates - based on corresponding atom detection method
    call nano_new%set_atomic_coords(trim(new_pdb_filename))
    call nano_old%set_atomic_coords(trim(old_pdb_filename))

    ! find per-atom valid correlation for overlapping and differing atoms
    call nano_new%per_atom_valid_corr_from_pdb(trim(atoms_new_not_old),output_file='atoms_new_not_old_corrs.csv')
    call nano_new%per_atom_valid_corr_from_pdb(trim(atoms_new_in_old), output_file='atoms_new_in_old_corrs.csv' )
    call nano_old%per_atom_valid_corr_from_pdb(trim(atoms_old_not_new),output_file='atoms_old_not_new_corrs.csv')
    call nano_new%per_atom_valid_corr_from_pdb(trim(atoms_old_in_new), output_file='atoms_old_in_new_corrs.csv' )

end program simple_test_correlation