#!/usr/bin/env python

import sys
import numpy as np
import commit
from commit import trk2dictionary
import amico

import nibabel as nib

"""
# 2023 Wen Da Lu, BIC, Montreal Neurological Institute, McGill
#------------------------------------------------------------------------------------------------------------------------------------
"""

#-----------------------------------#
#------------- SETUP ---------------#
#-----------------------------------#
commit.core.setup()       # precomputes the rotation matrices used internally by COMMIT
# Inputs
ID          = sys.argv[1]
in_dir   	= sys.argv[2]
tmp_dir     = sys.argv[3]
dict_dir    = sys.argv[4]
tractogram  = sys.argv[5]
qmap        = sys.argv[6]

print(".\n *** Initializing COMMIT for: ", ID)
print(".\n *** Tractogram: ", tractogram)

# Files
wm_mask        	= tmp_dir + "/" + ID  + "_dwi_wm_mask.nii.gz"

trk2dictionary.run(
     filename_tractogram = tractogram,
     filename_mask  = wm_mask,
     fiber_shift    = 0.5,
     path_out       = dict_dir,
     ndirs = 1
)

# Setting parameters
mit = commit.Evaluation()
mit.set_config('doNormalizeSignal', False)

mit.load_data( qmap, None )

# Set model and generate the kernel
mit.set_model( 'VolumeFractions' )
mit.model.set()
mit.generate_kernels( ndirs=1, regenerate=True )
mit.load_kernels()

# Load dictionary and buid the operator
mit.load_dictionary( dict_dir )

mit.set_threads(30)
mit.build_operator()

# fitting
mit.fit( tol_fun=1e-3, max_iter=1000, verbose=True )
mit.save_results()











