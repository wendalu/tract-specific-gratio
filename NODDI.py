#!/usr/bin/env python

import sys
import os
import amico

"""
# 2024 Wen Da Lu, BIC, Montreal Neurological Institute, McGill
#------------------------------------------------------------------------------------------------------------------------------------
"""
amico.setup() 
#-----------------------------------#
#------------- SETUP ---------------#
#-----------------------------------#

ID          = sys.argv[1]
in_dir   	= sys.argv[2]
tmp_dir     = sys.argv[3]

print(".\n *** Initializing COMMIT for: ", ID)

# Dirs
out_dir     = in_dir + "/NODDI_AMICO"

# Files
mask            = tmp_dir + "/" + ID  + "_brain_mask.nii.gz"
dwi_corr       	= tmp_dir + "/" + ID  + "_dwi.nii.gz"
bvals        	= tmp_dir + "/" + ID  + "_bvals.txt"
bvecs       	= tmp_dir + "/" + ID  + "_bvecs.txt"
scheme 		    = tmp_dir + "/AMICO.scheme"

#------------------------------------
# Import usual COMMIT structure
#------------------------------------

ae = amico.Evaluation( out_dir, '.' )
amico.util.fsl2scheme( bvals, bvecs, scheme)

ae.load_data( dwi_corr, scheme, mask_filename=mask, b0_thr=0)

ae.set_model('NODDI')
ae.generate_kernels(regenerate=True)

ae.load_kernels()
ae.fit()
ae.save_results()
