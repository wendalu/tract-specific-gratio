# Tract-Specific g-Ratio Pipeline

Automated pipeline for computing tract-specific g-ratio using MRtrix3 and COMMIT.

## Quick Start (Pre-built Container)

No installation required besides [Apptainer/Singularity](https://apptainer.org/).

### Download Image
Download the latest `tract-specific-gratio.sif` from [Releases](../../releases).

### Run
```bash
./tract-specific-gratio.sif \
    --dwi dwi.nii.gz \
    --bvec bvecs \
    --bval bvals \
    --tracks tracks.tck \
    --fod wmfod.mif \
    --mvf mvf.nii.gz \
    --mask wm_mask.nii.gz \
    --outdir results/
```

---

## Customizing / Modifying the Pipeline

If you want to modify `pipeline.sh` or the Python scripts without rebuilding the container:

1. Clone this repository:
   ```bash
   git clone [https://github.com/](https://github.com/)<your-username>/tract-specific-gratio.git
   cd tract-specific-gratio
   ```
2. Edit `pipeline.sh` or any `*.py` file.
3. Run the container while mounting your local edits over `/app`:
   ```bash
   singularity exec \
       -B $(pwd):/app \
       /path/to/tract-specific-gratio.sif \
       /app/pipeline.sh -d dwi.nii.gz ...
   ```
