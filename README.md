# Tract-Specific g-Ratio Pipeline

Automated pipeline for computing tract-specific g-ratio using MRtrix3 and COMMIT.

---

## Input Requirements & Spatial Resolution

| Input Flag | Description | Required | Notes |
| :--- | :--- | :--- | :--- |
| `-d`, `--dwi` | Diffusion image (`.nii`, `.nii.gz`, `.mif`) | Yes | Resampled internally to match `--mvf` |
| `--bvec` | FSL b-vectors text file | Conditional | Required only if `--dwi` is NIfTI |
| `--bval` | FSL b-values text file | Conditional | Required only if `--dwi` is NIfTI |
| `-t`, `--tracks` | Tractogram (`.tck`) | Yes | Pre-computed streamlines |
| `-f`, `--fod` | White matter FOD (`.nii.gz`, `.mif`) | Yes | Fiber orientation distribution map |
| `--mvf` | Myelin Volume Fraction map (`.nii.gz`) | Yes | **Defines target output resolution** |
| `-m`, `--mask` | White matter mask (`.nii.gz`) | Yes | Binary mask in DWI/MVF space |
| `-o`, `--outdir` | Output directory | No | Default: `./results` |
| `--no-cleanup` | Keep temporary scratch files | No | Preserves `$TMPDIR` for troubleshooting |

### !!! Important Note on Resolution and Voxel Grids

1. **Native-Resolution Preprocessed DWI:**
   * Provide the fully corrected diffusion data.
   * **Do not pre-resample or upsample the DWI yourself.** Interpolating diffusion data prior to this pipeline introduces spatial smoothing, alters noise distributions, and degrades angular precision. Pass the corrected data at its **native acquisition resolution**.

2. **Target Resolution Defined by MVF:**
   * The pipeline handles the DWI upsampling internally to align voxel-for-voxel with the `--mvf` image grid.
   * If you wish to compute tract-specific g-ratio at an anatomical resolution (e.g., 1.0 mm isotropic or T1w space), **register/resample your MVF to that anatomical target before running this pipeline**. The native DWI will be scaled to match it automatically.

---

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
