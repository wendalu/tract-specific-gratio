#!/usr/bin/env python

import sys
import os
import numpy as np
import commit
from commit import trk2dictionary
import amico

"""
# 2021 Mark C Nelson, McConnell Brain Imaging Centre, MNI, McGill
# 2023 Wen Da Lu, BIC, Montreal Neurological Institute, McGill
#------------------------------------------------------------------------------------------------------------------------------------
"""

#-----------------------------------#
#------------- SETUP ---------------#
#-----------------------------------#

ID          = sys.argv[1]
in_dir   	= sys.argv[2]
tmp_dir     = sys.argv[3]
out_dir     = sys.argv[4]
tractogram  = sys.argv[5]
para_diff   = float(sys.argv[6])
perp_diff   = float(sys.argv[7])
iso_diff    = float(sys.argv[8])

print(".\n *** Initializing COMMIT for: ", ID)

# Dirs
dict_dir        = out_dir + "/dict"

# Files
dwi_b0 	    	= in_dir + "/" + ID + "_space-dwi_desc-b0.nii.gz"
wm_fod         	= tmp_dir + "/" + ID  + "_wm_fod_norm.nii.gz"
wm_mask        	= tmp_dir + "/" + ID  + "_dwi_wm_mask.nii.gz"
dwi_corr       	= tmp_dir + "/" + ID  + "_dwi_upscaled.nii.gz"
bvals        	= tmp_dir + "/" + ID  + "_bvals.txt"
bvecs       	= tmp_dir + "/" + ID  + "_bvecs.txt"
scheme 		    = tmp_dir + "/AMICO.scheme"

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
        peaks_use_affine        = True,
        verbose                 = 2
)

# load data
amico.util.fsl2scheme( bvals, bvecs, scheme )
mit = commit.Evaluation( out_dir, '.' )                                              # study_path, subject (relative to study_path)
mit.set_config('doNormalizeSignal', False)
mit.load_data(
        dwi_filename    = dwi_corr,
        scheme_filename = scheme
)

# set forward model
mit.set_model( 'StickZeppelinBall' )                                                    # model described in (Panagiotaki et al., NeuroImage, 2012)

d_par   = para_diff                                                                     # Parallel diffusivity [mm^2/s]
d_perps = [ perp_diff ]                                                                 # Perpendicular diffusivity(s) [mm^2/s]
d_isos  = [ 1.7E-3, iso_diff ]                                                          # Isotropic diffusivity(s) [mm^2/s]

mit.model.set( d_par, d_perps, d_isos )
mit.generate_kernels( regenerate=True )
mit.load_kernels()

# Load dictionary (sparse data structure)
mit.load_dictionary( dict_dir )

# Build linear operator A
mit.set_threads( 30 )                                                                       # use max possible; mit.set_threads( n ) to set manually
mit.build_operator()
# perform optimization
mit.fit(tol_fun=1e-3, max_iter=1000)

# saves to out_dir + /Results_StickZeppelinBall + path_suffix + /*
mit.save_results(path_suffix='_AdvancedSolvers')

