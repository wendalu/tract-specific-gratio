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
commit.setup()
# Files
tractogram      = sys.argv[1]
qmap        	= sys.argv[2]
wm_mask     	= sys.argv[3]

# Dirs
in_dir   	    = sys.argv[4]
dict_dir        = in_dir + "/MySD"

#------------------------------------
# Import usual MySD structure
#------------------------------------
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

mit.set_threads()
mit.build_operator()

# fitting
mit.fit( tol_fun=1e-3, max_iter=1000, verbose=True )
mit.save_results()











