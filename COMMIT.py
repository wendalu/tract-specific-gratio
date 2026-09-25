#!/usr/bin/env python

import sys
import os
import numpy as np
import commit
from commit import trk2dictionary
import amico

"""
# 2021 Mark C Nelson, McConnell Brain Imaging Centre, MNI, McGill
# 2023 Wen Da Lu, McConnell Brain Imaging Centre, MNI, McGill
#------------------------------------------------------------------------------------------------------------------------------------
"""
#-----------------------------------#
#------------- SETUP ---------------#
#-----------------------------------#
# Files
dwi_corr       	= sys.argv[1]
bvals        	= sys.argv[2]
bvecs       	= sys.argv[3]
dwi_b0 	    	= sys.argv[4]
wm_mask     	= sys.argv[5]
peaks         	= sys.argv[6]
tractogram      = sys.argv[7]

# Dirs
in_dir   	    = sys.argv[8]
commit_dir      = in_dir + "/COMMITscl"
dict_dir        = commit_dir + "/dict"

scheme 		    = in_dir + "/AMICO.scheme"

#------------------------------------
# Import usual COMMIT structure
#------------------------------------
commit.core.setup()                                                                     # precomputes the rotation matrices used internally by COMMIT
trk2dictionary.run(
        filename_tractogram     = tractogram,
        filename_peaks          = wm_fod,
        filename_mask           = wm_mask,
        TCK_ref_image           = dwi_b0,
        path_out                = dict_dir,
        fiber_shift             = 0.5,
        peaks_use_affine        = True
)

# load data
amico.util.fsl2scheme( bvals, bvecs, scheme )
mit = commit.Evaluation( commit_dir, '.' )                                              # study_path, subject (relative to study_path)
mit.set_config('doNormalizeSignal', False)
mit.load_data(
        dwi_filename    = dwi_corr,
        scheme_filename = scheme
)

# set forward model
mit.set_model( 'StickZeppelinBall' )                                                    # model described in (Panagiotaki et al., NeuroImage, 2012)
d_par   = 1.7E-3                                                                        # Parallel diffusivity [mm^2/s]
d_perps = [ 0.51E-3 ]                                                                   # Perpendicular diffusivity(s) [mm^2/s]
d_isos  = [ 1.7E-3, 3.0E-3 ]                                                            # Isotropic diffusivity(s) [mm^2/s]
mit.model.set( d_par, d_perps, d_isos )
mit.generate_kernels( regenerate=True )
mit.load_kernels()

# Load dictionary (sparse data structure)
mit.load_dictionary( dict_dir )

# Build linear operator A
mit.set_threads()                                                                       # use max possible; mit.set_threads( n ) to set manually
mit.build_operator()
# perform optimization
mit.fit(tol_fun=1e-3, max_iter=1000)

# saves to out_dir + /Results_StickZeppelinBall + path_suffix + /*
mit.save_results(path_suffix='_AdvancedSolvers')

