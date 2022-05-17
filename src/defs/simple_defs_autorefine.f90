module simple_defs_autorefine
character(len=*), parameter :: RECVOL        = 'recvol_state01.mrc'
character(len=*), parameter :: EVEN          = 'recvol_state01_even.mrc'
character(len=*), parameter :: EVEN_FILT     = 'recvol_state01_even_filt.mrc'
character(len=*), parameter :: EVEN_ATOMS    = 'recvol_state01_even_filt_ATMS_COMMON.pdb'
character(len=*), parameter :: EVEN_SIM      = 'recvol_state01_even_filt_ATMS_COMMON_SIM.mrc'
character(len=*), parameter :: EVEN_BIN      = 'recvol_state01_even_filt_BIN.mrc'
character(len=*), parameter :: EVEN_CCS      = 'recvol_state01_even_filt_CC.mrc'
character(len=*), parameter :: EVEN_SPLIT    = 'split_ccs_even.mrc'
character(len=*), parameter :: ODD           = 'recvol_state01_odd.mrc'
character(len=*), parameter :: ODD_FILT      = 'recvol_state01_odd_filt.mrc'
character(len=*), parameter :: ODD_ATOMS     = 'recvol_state01_odd_filt_ATMS_COMMON.pdb'
character(len=*), parameter :: ODD_SIM       = 'recvol_state01_odd_filt_ATMS_COMMON_SIM.mrc'
character(len=*), parameter :: ODD_BIN       = 'recvol_state01_odd_filt_BIN.mrc'
character(len=*), parameter :: ODD_CCS       = 'recvol_state01_odd_filt_CC.mrc'
character(len=*), parameter :: ODD_SPLIT     = 'split_ccs_odd.mrc'
character(len=*), parameter :: AVG_MAP       = 'recvol_state01_filt_AVG.mrc'
character(len=*), parameter :: AVG_ATOMS     = 'recvol_state01_ATMS_AVG.pdb'
character(len=*), parameter :: AVG_ATOMS_SIM = 'recvol_state01_ATMS_AVG_SIM.mrc'
character(len=*), parameter :: TAG           = 'xxx' ! for checking command lines
end module simple_defs_autorefine