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

You do not need to rebuild the Singularity image to tweak algorithm parameters, test code changes, or debug. You can use the pre-built `.sif` file strictly as a runtime environment while running your own local scripts.

### 1. Clone the repository
```bash
git clone https://github.com/wendalu/tract-specific-gratio.git
cd tract-specific-gratio
```

### 2. Make your edits
Edit `pipeline.sh` or any of the `.py` files locally.

### 3. Run using your local code
Use `singularity exec` with the `-B` flag to map your current working directory over `/app` inside the container:

```bash
singularity exec \
    -B $(pwd):/app \
    /path/to/tract-specific-gratio.sif \
    /app/pipeline.sh \
        -d /path/to/dwi.nii.gz \
        --bvec /path/to/bvecs \
        --bval /path/to/bvals \
        -t /path/to/tracks.tck \
        -f /path/to/wmfod.mif \
        --mvf /path/to/mvf.nii.gz \
        -m /path/to/wm_mask.nii.gz \
        -o /path/to/output_dir/
```
