#!/usr/bin/env python
import argparse
import sys
import numpy as np


def compute_weight_times_length(weight_path, length_path, output_path):
    # np.loadtxt gracefully handles multi-space or tab delimiters
    weights = np.loadtxt(weight_path).squeeze()
    lengths = np.loadtxt(length_path).squeeze()

    # Flatten to 1D to guard against row vs column shape mismatches
    weights = np.atleast_1d(weights).ravel()
    lengths = np.atleast_1d(lengths).ravel()

    if weights.shape[0] != lengths.shape[0]:
        sys.exit(
            f"Error: Dimension mismatch! Weights have {weights.shape[0]} elements, "
            f"but lengths have {lengths.shape[0]} elements."
        )

    # Element-wise product: weight * length
    result = weights * lengths

    # Save as 1D column (matching MATLAB's ASCII dump)
    np.savetxt(output_path, result, fmt="%.10e")
    print(f"[*] Computed volume weights written to: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Compute element-wise product of streamline weights and lengths."
    )
    parser.add_argument("weights", help="Path to weights text file")
    parser.add_argument("lengths", help="Path to lengths text file")
    parser.add_argument("output", help="Path to output text file")

    args = parser.parse_args()
    compute_weight_times_length(args.weights, args.lengths, args.output)


if __name__ == "__main__":
    main()
