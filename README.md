# Tract-Specific g-Ratio Pipeline

[![DOI](https://img.shields.io/badge/DOI-10.1162%2FIMAG.a.49-blue.svg)](https://doi.org/10.1162/IMAG.a.49)

Automated pipeline for computing tract-specific g-ratio using MRtrix3 and COMMIT.

Based on the methodology described in:
> **Mapping the aggregate g-ratio of white matter tracts using multi-modal MRI Open Access**  
> *Imaging Neuroscience* (2024). DOI: [10.1162/IMAG.a.49](https://doi.org/10.1162/IMAG.a.49)

If you use this pipeline in your research, please cite the paper above.

---

## Important Note on Resolution and Voxel Grids

To get accurate voxel-wise overlap between tractography and myelin maps, the inputs must be properly aligned before running the pipeline:

### 1. Spatial Alignment (Co-registration)
* **All inputs must already be aligned in the same physical space.**
* Typically, this involves registering structural T1w and quantitative myelin maps (MVF) into the subject's distortion-corrected DWI space.
* If you overlay `--dwi` (b0 volume) and `--mvf` in an image viewer like `mrview` or `fsleyes`, anatomical structures must align accurately.

### 2. Resolution & Voxel Grid (The Role of `--mvf`)
* **Do not pre-resample or upscale the 4D DWI yourself.** Provide your diffusion series at its **native acquisition resolution** (with corrections applied).
* **The `--mvf` image acts as the master spatial grid.** The pipeline automatically handles upscaling the native 4D DWI internally to match the exact matrix dimensions, affine header, and voxel size of the `--mvf` file.
* **Targeting Higher Resolution (e.g., 1.0 mm isotropic / T1w resolution):**
  * When preparing your MVF map, register the MVF onto your desired high-resolution grid (for example, by aligning it to an upscaled reference b0) *before* passing it to `--mvf`.
  * Pass that high-resolution `--mvf` and your native `--dwi` into the pipeline.
  * The pipeline will detect the high-res grid from `--mvf` and upscale the native 4D DWI in one clean step under the hood—ensuring full voxel-for-voxel alignment while avoiding repeated interpolation blur across your diffusion shells.

---

## Quick Start (Pre-built Container)

No local dependencies required besides [Apptainer/Singularity](https://apptainer.org/).

### 1. Download Container
Download the latest `tract-specific-gratio.sif` from [Releases](../../releases) (or pull it directly on your cluster).

### 2. Run

**Using NIfTI inputs:**
```bash
./tract-specific-gratio.sif \
    --dwi dwi.nii.gz \
    --bvec bvecs \
    --bval bvals \
    --mask mask.nii.gz \
    --tracks tracks.tck \
    --mvf mvf.nii.gz \
    --wm wm_mask.nii.gz \
    --outdir results/
```

*(Optional)* Add `--parcel parcellation.nii.gz` to compute structural connectome matrices weighted by axonal volume, myelin volume, and g-ratio.

---

## Input Requirements & Options

| Input Flag | Description | Required | Notes |
| :--- | :--- | :--- | :--- |
| `-d`, `--dwi` | Diffusion image (`.nii`, `.nii.gz`, `.mif`) | Yes | Needs at least 2 shells.<br>Resampled internally to match `--mvf` |
| `--bvec` | FSL b-vectors text file | Conditional | Required only if `--dwi` is NIfTI |
| `--bval` | FSL b-values text file | Conditional | Required only if `--dwi` is NIfTI |
| `-m`, `--mask` | Brain mask (`.nii.gz`, `.mif`) | Yes | Binary skull-stripped mask.<br>**Must match native `--dwi` resolution and grid** |
| `-t`, `--tracks` | Tractogram (`.tck`) | Yes | Pre-computed streamlines |
| `--mvf` | Myelin Volume Fraction map (`.nii.gz`) | Yes | **Defines target output resolution grid** |
| `-w`, `--wm` | White matter mask (`.nii.gz`) | Yes | Binary white matter mask.<br>**Must match target `--mvf` resolution and grid** |
| `-p`, `--parcel` | Parcellation atlas (`.nii.gz`, `.mif`) | Optional | Generates AV, MV, and g-ratio connectomes |
| `-o`, `--outdir` | Output directory | Optional | Default: `./results` |
| `--no-cleanup` | Keep temporary scratch files | Optional | Preserves scratch `$TMPDIR` for debugging |

---

## Customizing / Modifying the Pipeline

You do not need to rebuild the Singularity image to tweak algorithm parameters, test code changes, or debug. You can use the pre-built `.sif` file strictly as a runtime environment while executing your own local scripts.

### 1. Clone the repository
```bash
git clone [https://github.com/wendalu/tract-specific-gratio.git](https://github.com/wendalu/tract-specific-gratio.git)
cd tract-specific-gratio
```

### 2. Make your edits
Edit `pipeline.sh` or any of the scripts inside `scripts/` locally using your preferred text editor.

### 3. Run using your local code
Use `singularity exec` with the `-B` (bind mount) flag to overlay your cloned folder onto `/app` inside the container:

```bash
singularity exec \
    -B $(pwd):/app \
    /path/to/tract-specific-gratio.sif \
    /app/pipeline.sh \
        -d /path/to/dwi.nii.gz \
        --bvec /path/to/bvecs \
        --bval /path/to/bvals \
        -m /path/to/mask.nii.gz \
        -t /path/to/tracks.tck \
        --mvf /path/to/mvf.nii.gz \
        -w /path/to/wm_mask.nii.gz \
        -o /path/to/output_dir/
```

