#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_final_state():
    pdb_path = "/home/user/protein.pdb"
    output_path = "/home/user/z_density.txt"

    assert os.path.isfile(pdb_path), f"Missing required file: {pdb_path}"
    assert os.path.isfile(output_path), f"Missing required output file: {output_path}"

    # Recompute the expected density from the PDB file directly
    expected_counts = {}
    with open(pdb_path, "r") as f:
        for line in f:
            parts = line.split()
            # Check for ATOM and CA
            if len(parts) >= 8 and parts[0] == "ATOM" and parts[2] == "CA":
                z_str = parts[7]
                # Truncate decimal portion
                z_bin_str = z_str.split('.')[0]
                z_bin = int(z_bin_str)  # Converts '-0' to 0
                expected_counts[z_bin] = expected_counts.get(z_bin, 0) + 1

    expected_sorted = sorted(expected_counts.items())

    # Read and parse the generated output file
    actual_data = []
    with open(output_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            assert len(parts) == 2, f"Output file must have exactly 2 columns, found {len(parts)} in line: '{line}'"

            try:
                z_bin = int(parts[0])
                count = int(parts[1])
            except ValueError:
                raise AssertionError(f"Output file must contain integers, failed to parse line: '{line}'")

            actual_data.append((z_bin, count))

    # Verify that the output is strictly sorted by Z_BIN
    z_bins = [x[0] for x in actual_data]
    assert z_bins == sorted(z_bins), "The output file is not sorted strictly numerically by Z_BIN in ascending order."

    # Verify that the bins are unique (no duplicate Z_BIN lines)
    assert len(z_bins) == len(set(z_bins)), "The output file contains duplicate Z_BIN entries."

    # Compare actual vs expected
    assert actual_data == expected_sorted, (
        f"The computed density does not match the expected results.\n"
        f"Expected: {expected_sorted}\n"
        f"Actual:   {actual_data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
