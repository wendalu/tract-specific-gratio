#!/usr/bin/env bash
set -euo pipefail

# Print usage if requested or if arguments are missing
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Required Arguments:
  --dwi, -d      PATH    Diffusion image (.nii / .nii.gz / .mif)
  --tracks, -t   PATH    Pre-computed tractogram / streamlines (.tck)
  --fod, -f      PATH    White matter fiber orientation distribution (.nii / .nii.gz / .mif)
  --mvf          PATH    Myelin volume fraction map (.nii / .nii.gz)
  --mask, -m     PATH    White matter mask (.nii / .nii.gz)

Conditional Arguments:
  --bvec         PATH    b-vectors text file (Required if DWI is NIfTI)
  --bval         PATH    b-values text file (Required if DWI is NIfTI)

Optional Arguments:
  --outdir, -o   PATH    Output directory (default: ./results)
  --no-cleanup           Keep temporary intermediate files for debugging
  --help, -h             Show this help message and exit

Examples:
  # Using NIfTI inputs (bvec/bval required)
  ./tract-specific-gratio.sif -d dwi.nii.gz --bvec bvecs --bval bvals -t tracks.tck -f wmfod.nii.gz --mvf mvf.nii.gz -m mask.nii.gz -o output/

  # Using .mif input (embedded grad table extracted automatically)
  ./tract-specific-gratio.sif -d dwi.mif -t tracks.tck -f wmfod.mif --mvf mvf.nii.gz -m mask.nii.gz -o output/
EOF
    exit 1
}

# Initialize variables
DWI=""
BVEC=""
BVAL=""
TRACKS=""
FOD=""
MVF=""
WM_MASK=""
OUTDIR="./results"
CLEANUP=true

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dwi)    DWI="$2"; shift 2 ;;
        --bvec)      BVEC="$2"; shift 2 ;;
        --bval)      BVAL="$2"; shift 2 ;;
        -t|--tracks) TRACKS="$2"; shift 2 ;;
        -f|--fod)    FOD="$2"; shift 2 ;;
        --mvf)       MVF="$2"; shift 2 ;;
        -m|--mask)   WM_MASK="$2"; shift 2 ;;
        -o|--outdir) OUTDIR="$2"; shift 2 ;;
        --no-cleanup) CLEANUP=false; shift ;;
        -h|--help)   usage ;;
        *) echo "Error: Unknown argument '$1'" >&2; usage ;;
    esac
done

# --- Base Validation Checks ---
missing_args=()
[[ -z "$DWI" ]]     && missing_args+=("--dwi")
[[ -z "$TRACKS" ]]  && missing_args+=("--tracks")
[[ -z "$FOD" ]]     && missing_args+=("--fod")
[[ -z "$MVF" ]]     && missing_args+=("--mvf")
[[ -z "$WM_MASK" ]] && missing_args+=("--mask")

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
for file in "$DWI" "$TRACKS" "$FOD" "$MVF" "$WM_MASK" "$BVEC" "$BVAL"; do
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
echo "FOD:        $FOD"
echo "MVF:        $MVF"
echo "WM Mask:    $WM_MASK"
echo "Output:     $OUTDIR"
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
# Processing
# ==============================================================================
echo "[*] Extracting mean b0..."
B0="$TMPDIR/DWI_mean_b0.nii.gz"

run_cmd dwiextract "$DWI_MIF" "$TMPDIR/DWI_b0.mif" -bzero -nthreads 1 -force
run_cmd mrmath "$TMPDIR/DWI_b0.mif" mean "$B0" -axis 3 -nthreads 1 -force

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
    run_cmd python /app/COMMIT_init.py \
        "$DWI" "$BVEC" "$BVAL" "$B0" "$WM_MASK" "$FOD" "$TRACKS" "$TMPDIR"

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
run_cmd python /app/weight_times_length.py "$COMMIT_weights" "$COMMIT_length" "$COMMIT_volume"

# ==============================================================================
# Step 2
# ==============================================================================
# File definitions
MySD_tck="${TMPDIR}/MySD-filtered.tck"
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
    run_cmd python /app/MySD.py \
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
run_cmd python /app/weight_times_length.py "$MySD_weights" "$MySD_length" "$MySD_volume"

