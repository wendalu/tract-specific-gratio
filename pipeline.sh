#!/usr/bin/env bash
set -euo pipefail

# Print usage if requested or if arguments are missing
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Required Arguments:
  -d, --dwi     PATH    Preprocessed diffusion image at native resolution (>= 2 shells) (.nii / .nii.gz / .mif)
  -m, --mask    PATH    Binary brain mask matching native DWI grid (.nii / .nii.gz / .mif)
  -t, --tracks  PATH    Pre-computed tractogram / streamlines (.tck)
      --mvf     PATH    Myelin volume fraction map defining target grid (.nii / .nii.gz)
  -w, --wm      PATH    Binary white matter mask matching target MVF grid (.nii / .nii.gz)

Conditional Arguments:
      --bvec    PATH    b-vectors text file (Required if DWI is NIfTI)
      --bval    PATH    b-values text file (Required if DWI is NIfTI)

Optional Arguments:
  -o, --outdir  PATH    Output directory (default: ./results)
  -p, --parcel  PATH    Parcellation atlas matching target MVF grid (.nii / .nii.gz / .mif)
      --no-cleanup      Preserves temporary scratch directory for debugging
  -h, --help            Show this help message and exit
  
Notes:
  * Resolution Reference: The --mvf image defines the master output resolution.
    The native DWI is automatically upscaled internally to match the MVF voxel grid.
    If you wish to compute metrics at higher resolution (e.g., 1.0 mm T1w),
    resample/register your MVF and WM mask to that grid BEFORE running this pipeline.

Examples:
  # Using NIfTI inputs (bvec/bval required)
  ./tract-specific-gratio.sif -d dwi.nii.gz --bvec bvecs --bval bvals -m mask.nii.gz -t tracks.tck --mvf mvf.nii.gz -w wm_mask.nii.gz -o output/

  # Using .mif input (gradients extracted automatically)
  ./tract-specific-gratio.sif -d dwi.mif -m mask.nii.gz -t tracks.tck --mvf mvf.nii.gz -w wm_mask.nii.gz -o output/
  
  # Optional connectome generation (AV, MV, and g-ratio weighted)
  ./tract-specific-gratio.sif -d dwi.mif -m mask.nii.gz -t tracks.tck --mvf mvf.nii.gz -w wm_mask.nii.gz -p parcel.nii.gz -o output/
EOF
    exit 1
}

# Initialize variables
DWI=""
BVEC=""
BVAL=""
TRACKS=""
MASK=""
MVF=""
WM_MASK=""
OUTDIR="./results"
PARCEL=""
CLEANUP=true

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dwi)       DWI="$2"; shift 2 ;;
        --bvec)         BVEC="$2"; shift 2 ;;
        --bval)         BVAL="$2"; shift 2 ;;
        -t|--tracks)    TRACKS="$2"; shift 2 ;;
        -m|--mask)      MASK="$2"; shift 2 ;;
        --mvf)          MVF="$2"; shift 2 ;;
        -w|--wm)        WM_MASK="$2"; shift 2 ;;
        -o|--outdir)    OUTDIR="$2"; shift 2 ;;
        -p|--parcel)    PARCEL="$2"; shift 2 ;;  
        --no-cleanup)   CLEANUP=false; shift ;;
        -h|--help)      usage ;;
        *) echo "Error: Unknown argument '$1'" >&2; usage ;;
    esac
done

# --- Base Validation Checks ---
missing_args=()
[[ -z "$DWI" ]]     && missing_args+=("--dwi")
[[ -z "$TRACKS" ]]  && missing_args+=("--tracks")
[[ -z "$MASK" ]]    && missing_args+=("--mask")
[[ -z "$MVF" ]]     && missing_args+=("--mvf")
[[ -z "$WM_MASK" ]] && missing_args+=("--wm")

# Check if DWI is NIfTI; if so, require bvec and bval
if [[ "$DWI" =~ \.nii(\.gz)?$ ]]; then
    [[ -z "$BVEC" ]] && missing_args+=("--bvec (required for NIfTI)")
    [[ -z "$BVAL" ]] && missing_args+=("--bval (required for NIfTI)")
fi

if [[ ${#missing_args[@]} -gt 0 ]]; then
    echo "Error: Missing required argument(s):" >&2
    for arg in "${missing_args[@]}"; do
        echo "  - $arg" >&2
    done
    echo ""
    usage
fi

# Verify input files that were supplied actually exist
for file in "$DWI" "$TRACKS" "$MASK" "$MVF" "$WM_MASK" "$BVEC" "$BVAL" "$PARCEL"; do
    if [[ -n "$file" && ! -f "$file" ]]; then
        echo "Error: Input file does not exist: $file" >&2
        exit 1
    fi
done

# Create output folder
mkdir -p "$OUTDIR"

# --- Setup Temporary Directory & Trap ---
TMPDIR=$(mktemp -d "$OUTDIR/tmp.XXXXXXXXXX")

cleanup_function() {
    local exit_code=$?
    if [ "$CLEANUP" = true ]; then
        echo "[*] Cleaning up temporary directory: $TMPDIR"
        rm -rf "$TMPDIR"
    else
        echo "[!] Clean-up skipped (--no-cleanup set). Intermediate files kept in: $TMPDIR"
    fi
    exit $exit_code
}

trap cleanup_function EXIT SIGINT SIGTERM

echo "=== Pipeline Configuration ==="
echo "DWI:        $DWI"
echo "bvec:       ${BVEC:-[Will extract from MIF]}"
echo "bval:       ${BVAL:-[Will extract from MIF]}"
echo "Tracks:     $TRACKS"
echo "Mask:       $MASK"
echo "MVF:        $MVF"
echo "WM Mask:    $WM_MASK"
echo "Output:     $OUTDIR"
echo "Parcel:     ${PARCEL:-[None]}"
echo "Temp Dir:   $TMPDIR"
echo "Cleanup:    $CLEANUP"
echo "=============================="

# ==============================================================================
# Format Normalization: Ensure both .mif and .nii.gz versions exist
# ==============================================================================

if [[ "$DWI" =~ \.mif(\.gz)?$ ]]; then
    echo "[*] Input DWI is in MIF format."
    DWI_MIF="$DWI"

    # Extract gradient table if not explicitly provided
    if [[ -z "$BVEC" || -z "$BVAL" ]]; then
        echo "[*] Extracting embedded diffusion gradient table..."
        BVEC="$TMPDIR/extracted_bvecs"
        BVAL="$TMPDIR/extracted_bvals"

        if ! mrinfo "$DWI_MIF" -export_grad_fsl "$BVEC" "$BVAL" -force > /dev/null 2>&1; then
            echo "Error: Failed to extract gradient table from $DWI_MIF." >&2
            echo "Please provide --bvec and --bval manually or verify that the MIF file has embedded DW grad info." >&2
            exit 1
        fi
        echo "[*] Successfully extracted bvecs and bvals from MIF header."
    fi

    # Generate NIfTI representation for Python/COMMIT tools
    echo "[*] Converting MIF to NIfTI format..."
    DWI_NII="$TMPDIR/DWI.nii.gz"
    mrconvert "$DWI_MIF" "$DWI_NII" -nthreads 1 -force

else
    echo "[*] Input DWI is in NIfTI format."
    DWI_NII="$DWI"

    # Generate MRtrix .mif with embedded gradients
    echo "[*] Converting NIfTI to MRtrix .mif..."
    DWI_MIF="$TMPDIR/DWI.mif"
    mrconvert "$DWI_NII" -fslgrad "$BVEC" "$BVAL" "$DWI_MIF" -nthreads 1 -force
fi

# ==============================================================================
# Preprocessing
# ==============================================================================
echo "[*] Upscaling and extracting mean b0..."
DWI_UP_MIF="$TMPDIR/DWI_up.mif"
DWI_UP_NII="$TMPDIR/DWI_up.nii.gz"
MASK_UP="$TMPDIR/DWI_up_mask.nii.gz"
B0_UP="$TMPDIR/DWI_mean_up_b0.nii.gz"

run_cmd mrgrid "$DWI_MIF" regrid -template "$MVF" "$DWI_UP_MIF" -force
run_cmd mrconvert "$DWI_UP_MIF" "$DWI_UP_NII" -nthreads 1 -force
run_cmd dwiextract "$DWI_UP_MIF" "$TMPDIR/DWI_up_b0.mif" -bzero -nthreads 1 -force
run_cmd mrmath "$TMPDIR/DWI_up_b0.mif" mean "$B0" -axis 3 -nthreads 1 -force
run_cmd mrgrid "$MASK" regrid -template "$MVF" -interpolation nearest "$MASK_UP" -force

echo "[*] Checking diffusion shells..."

# Extract all unique b-values detected by MRtrix
raw_shells=($(mrinfo "$DWI_MIF" -shell_bvalues))

# Filter out b0 shells (b <= 50 s/mm^2 to account for scanner rounding/noise)
nonzero_shells=()
for b in "${raw_shells[@]}"; do
    b_int="${b%.*}"
    if (( b_int > 50 )); then
        nonzero_shells+=("$b_int")
    fi
done

num_nonzero=${#nonzero_shells[@]}

if (( num_nonzero < 2 )); then
    echo "Error: Multi-shell diffusion data required, but found only $num_nonzero non-b0 shell(s): [${nonzero_shells[*]:-None}]." >&2
    echo "This pipeline requires b=0 plus at least 2 non-zero shells (e.g., b=1000 and b=2000 s/mm²) for MSMT-CSD and COMMIT microstructural fitting." >&2
    exit 1
fi

echo "[*] Multi-shell data verified: detected ${num_nonzero} non-b0 shells (${nonzero_shells[*]} s/mm²)."

# Response function estimation
echo "[*] Estimating response functions..."
WM_RESPONSE="$TMPDIR/response_wm.txt"
GM_RESPONSE="$TMPDIR/response_gm.txt"
CSF_RESPONSE="$TMPDIR/response_csf.txt"

run_cmd dwi2response dhollander "$DWI_MIF" \
    "$WM_RESPONSE" "$GM_RESPONSE" "$CSF_RESPONSE" \
    -mask "$MASK" \
    -force

# CSD + peaks
echo "[*] Generating peaks..."
PEAKS="$TMPDIR/peaks.nii.gz"

run_cmd dwi2fod msmt_csd "$DWI_MIF" \
    "$WM_RESPONSE" "$TMPDIR/wm.mif" \
    "$GM_RESPONSE" "$TMPDIR/gm.mif" \
    "$CSF_RESPONSE" "$TMPDIR/csf.mif" \
    -mask "$MASK" \
    -force

run_cmd sh2peaks "$TMPDIR/wm.mif" "$PEAKS" -num 3 -force

# ==============================================================================
# Step 1
# ==============================================================================
# File definitions
COMMIT_tck="${TMPDIR}/COMMIT-filtered.tck"
COMMIT_length="${TMPDIR}/COMMIT-filtered_length.txt"
COMMIT_weights="${TMPDIR}/COMMIT-filtered_weights.txt"
COMMIT_volume="${OUTDIR}/COMMIT-filtered_volume.txt"
weights_commit="${TMPDIR}/COMMIT_init/dict/Results_StickZeppelinBall_AdvancedSolvers/streamline_weights.txt"

echo "[*] Step 1: Running COMMIT filtering..."

counter=0
max_attempts=3

while [[ ! -f "$weights_commit" && $counter -lt $max_attempts ]]; do
    counter=$((counter + 1))
    echo "[*] Attempt $counter for COMMIT initialization..."

    # Call COMMIT_init.py (found in /app on PATH)
    run_cmd python /app/scripts/COMMIT_init.py \
        "$DWI_UP_NII" "$BVEC" "$BVAL" "$B0_UP" "$WM_MASK" "$PEAKS" "$TRACKS" "$TMPDIR"

    if [[ -f "$weights_commit" ]]; then
        run_cmd tckedit \
            -minweight 1e-12 \
            -tck_weights_in "$weights_commit" \
            -tck_weights_out "$COMMIT_weights" \
            "$TRACKS" "$COMMIT_tck" \
            -force

        # Extract streamline count robustly
        streamline_count=$(tckinfo "$COMMIT_tck" -count 2>/dev/null | awk -F': ' '/actual count/ {print $2}' | tr -d ' ')
        
        # Fallback if tckinfo format differs
        if [[ -z "$streamline_count" ]]; then
            streamline_count=$(tckinfo "$COMMIT_tck" -count 2>/dev/null | grep -oE '[0-9]+' | tail -n1)
        fi

        if [[ "$streamline_count" -eq 0 ]]; then
            echo "[!] Streamline count is 0. Resetting attempt..."
            rm -rf "${TMPDIR}/COMMIT_init"
            rm -f "$weights_commit" "$COMMIT_tck" "$COMMIT_weights"
        fi
    else
        echo "[!] Output weights file not found on attempt $counter."
        rm -rf "${TMPDIR}/COMMIT_init"
    fi
done

if [[ ! -f "$COMMIT_tck" ]]; then
    echo "Error: COMMIT failed after $counter attempts." >&2
    exit 1
fi

echo "[*] Extracting streamline lengths..."
run_cmd tckstats "$COMMIT_tck" -dump "$COMMIT_length" -force

echo "[*] Computing streamline intra-axonal volume (weights × lengths)..."
run_cmd python /app/scripts/weight_times_length.py "$COMMIT_weights" "$COMMIT_length" "$COMMIT_volume"

# ==============================================================================
# Step 2
# ==============================================================================
# File definitions
MySD_tck="${OUTDIR}/MySD-filtered.tck"
MySD_length="${TMPDIR}/MySD-filtered_length.txt"
MySD_weights="${TMPDIR}/MySD-filtered_weights.txt"
MySD_volume="${OUTDIR}/MySD-filtered_volume.txt"
weights_mysd="${TMPDIR}/MySD/Results_VolumeFractions/streamline_weights.txt"

echo "[*] Step 2: Running bundle specific myelin content estimation..."

counter=0
max_attempts=3

while [[ ! -f "$weights_mysd" && $counter -lt $max_attempts ]]; do
    counter=$((counter + 1))
    echo "[*] Attempt $counter for bundle specific myelin estimation..."

    # Call MySD.py (found in /app on PATH)
    run_cmd python /app/scripts/MySD.py \
        "$TRACKS" "$MVF" "$WM_MASK" "$TMPDIR"

    if [[ -f "$weights_mysd" ]]; then
        run_cmd tckedit \
            -minweight 1e-12 \
            -tck_weights_in "$weights_mysd" \
            -tck_weights_out "$MySD_weights" \
            "$COMMIT_tck" "$MySD_tck" \
            -force

        # Extract streamline count robustly
        streamline_count=$(tckinfo "$MySD_tck" -count 2>/dev/null | awk -F': ' '/actual count/ {print $2}' | tr -d ' ')
        
        # Fallback if tckinfo format differs
        if [[ -z "$streamline_count" ]]; then
            streamline_count=$(tckinfo "$MySD_tck" -count 2>/dev/null | grep -oE '[0-9]+' | tail -n1)
        fi

        if [[ "$streamline_count" -eq 0 ]]; then
            echo "[!] Streamline count is 0. Resetting attempt..."
            rm -rf "${TMPDIR}/MySD"
            rm -f "$weights_mysd" "$MySD_tck" "$MySD_weights"
        fi
    else
        echo "[!] Output weights file not found on attempt $counter."
        rm -rf "${TMPDIR}/MySD"
    fi
done

if [[ ! -f "$MySD_tck" ]]; then
    echo "Error: Bundle specific myelin failed after $counter attempts." >&2
    exit 1
fi

echo "[*] Extracting streamline lengths..."
run_cmd tckstats "$MySD_tck" -dump "$MySD_length" -force

echo "[*] Computing streamline intra-axonal volume (weights × lengths)..."
run_cmd python /app/scripts/weight_times_length.py "$MySD_weights" "$MySD_length" "$MySD_volume"

# ==============================================================================
# Step 3
# ==============================================================================
# File definitions
COMMITscl_tck="${OUTDIR}/COMMITscl-filtered.tck"
COMMITscl_length="${TMPDIR}/COMMITscl-filtered_length.txt"
COMMITscl_weights="${TMPDIR}/COMMITscl-filtered_weights.txt"
COMMITscl_volume="${OUTDIR}/COMMITscl-filtered_volume.txt"
weights_commitscl="${TMPDIR}/COMMITscl/dict/Results_StickZeppelinBall_AdvancedSolvers/streamline_weights.txt"

echo "[*] Step 3: Running bundle specific axonal content estimation..."

# Obtain MVF scaled DWI
run_cmd mrgrid "$MVF" regrid -template "$MASK" "$TMPDIR/MVF_low.nii.gz" -force
run_cmd mrcalc 1 "$TMPDIR/MVF_low.nii.gz" -subtract "$TMPDIR/scaling_1.nii.gz" -force
run_cmd dwiextract "$DWI_MIF" -bzero "$TMPDIR/b0s.mif" -force
run_cmd mrmath "$TMPDIR/b0s.mif" mean -axis 3 "$TMPDIR/mean_b0s.mif"
run_cmd mrcalc "$DWI_MIF" "$TMPDIR/scaling_1.nii.gz" -mult "$TMPDIR/mean_b0s.mif" -div "$TMPDIR/dwi_scaled_norm.mif" -force
run_cmd mrcalc "$TMPDIR/dwi_scaled_norm.mif" -finite "$TMPDIR/dwi_scaled_norm.mif" 0.0 -if "$TMPDIR/dwi_scaled_norm_nonan.mif"
run_cmd mrcalc "$TMPDIR/dwi_scaled_norm_nonan.mif" 2 -lt "$TMPDIR/dwi_scaled_norm_nonan.mif" 0.0 -if 0 -gt "$TMPDIR/dwi_scaled_norm_nonan.mif" 0.0 -if "$TMPDIR/dwi_scaled_norm_bound.mif"
run_cmd mrgrid "$TMPDIR/dwi_scaled_norm_bound.mif" regrid -template "$MVF" "$TMPDIR/dwi_up_scaled_norm_nonan_bound.nii.gz"

counter=0
max_attempts=3

while [[ ! -f "$weights_commitscl" && $counter -lt $max_attempts ]]; do
    counter=$((counter + 1))
    echo "[*] Attempt $counter for bundle specific axonal estimation..."

    # Call COMMIT.py (found in /app on PATH)
    run_cmd python /app/scripts/COMMIT.py \
        "$DWI_UP_NII" "$BVEC" "$BVAL" "$B0_UP" "$WM_MASK" "$PEAKS" "$TRACKS" "$TMPDIR"
        
    if [[ -f "$weights_commitscl" ]]; then
        run_cmd tckedit \
            -minweight 1e-12 \
            -tck_weights_in "$weights_commitscl" \
            -tck_weights_out "$COMMITscl_weights" \
            "$MySD_tck" "$COMMITscl_tck" \
            -force

        # Extract streamline count robustly
        streamline_count=$(tckinfo "$COMMITscl_tck" -count 2>/dev/null | awk -F': ' '/actual count/ {print $2}' | tr -d ' ')
        
        # Fallback if tckinfo format differs
        if [[ -z "$streamline_count" ]]; then
            streamline_count=$(tckinfo "$COMMITscl_tck" -count 2>/dev/null | grep -oE '[0-9]+' | tail -n1)
        fi

        if [[ "$streamline_count" -eq 0 ]]; then
            echo "[!] Streamline count is 0. Resetting attempt..."
            rm -rf "${TMPDIR}/COMMITscl"
            rm -f "$weights_commitscl" "$COMMITscl_tck" "$COMMITscl_weights"
        fi
    else
        echo "[!] Output weights file not found on attempt $counter."
        rm -rf "${TMPDIR}/COMMITscl"
    fi
done

if [[ ! -f "$COMMITscl_tck" ]]; then
    echo "Error: Bundle specific axonal content failed after $counter attempts." >&2
    exit 1
fi

echo "[*] Extracting streamline lengths..."
run_cmd tckstats "$COMMITscl_tck" -dump "$COMMITscl_length" -force

echo "[*] Computing streamline intra-axonal volume (weights × lengths)..."
run_cmd python /app/scripts/weight_times_length.py "$COMMITscl_weights" "$COMMITscl_length" "$COMMITscl_volume"

# ==============================================================================
# Optional: Structural Connectome Generation
# ==============================================================================
if [[ -n "$PARCEL" ]]; then
    echo "[*] Parcellation image provided. Building connectomes with tck2connectome..."

    # Output connectome matrices
    CONNECTOME_MV="${OUTDIR}/connectome_myelin_weighted.txt"
    CONNECTOME_AV="${OUTDIR}/connectome_axonal_weighted.txt"
    CONNECTOME_GRATIO="${OUTDIR}/connectome_gratio_weighted.txt"

    echo "[*] Generating myelin volume weighted connectome..."
    tck2connectome "$MySD_tck" "$PARCEL" "$CONNECTOME_MV" \
        -tck_weights_in "$MySD_weights" \
        -assignment_radial_search 2 \
        -symmetric \
        -force
    echo "[*] Generating axonal volume weighted connectome..."
    tck2connectome "$COMMITscl_tck" "$PARCEL" "$CONNECTOME_AV" \
        -tck_weights_in "$COMMITscl_weights" \
        -assignment_radial_search 2 \
        -symmetric \
        -force
    echo "[*] Generating gratio weighted connectome..."
    python - <<EOF
import numpy as np

# Load 2D connectome matrices (delimiter handling for CSV or whitespace)
mv = np.loadtxt('${CONNECTOME_MV}')
av = np.loadtxt('${CONNECTOME_AV}')

# Total fiber volume = AV + MV
total_vol = av + mv

# Safe element-wise computation: sqrt(AV / (AV + MV))
# Mask where total volume is greater than 0 to prevent ZeroDivisionError / NaN warnings
gratio = np.zeros_like(av, dtype=np.float64)
valid = (total_vol > 0) & (av >= 0) & (mv >= 0)

np.divide(av, total_vol, out=gratio, where=valid)
np.sqrt(gratio, out=gratio, where=valid)

np.savetxt('${CONNECTOME_GRATIO}', gratio, fmt='%.6f', delimiter=' ')
EOF

    echo "[*] Connectome matrices saved to $OUTDIR"
fi

