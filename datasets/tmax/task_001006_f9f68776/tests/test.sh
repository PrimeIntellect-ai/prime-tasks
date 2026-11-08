#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_features_csv_exists():
    """Test that the features.csv file has been created."""
    assert os.path.isfile("/home/user/features.csv"), "The file /home/user/features.csv does not exist."

def test_features_csv_contents():
    """Test that features.csv contains the correct CA coordinates and geometric center."""
    pdb_path = "/home/user/protein.pdb"
    csv_path = "/home/user/features.csv"

    assert os.path.isfile(pdb_path), f"Missing {pdb_path}"
    assert os.path.isfile(csv_path), f"Missing {csv_path}"

    # Extract expected CA coordinates from PDB
    ca_coords = []
    with open(pdb_path, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                atom_name = line[12:16].strip()
                if atom_name == "CA":
                    x = float(line[30:38].strip())
                    y = float(line[38:46].strip())
                    z = float(line[46:54].strip())
                    ca_coords.append((x, y, z))

    assert len(ca_coords) > 0, "No CA atoms found in the PDB file."

    # Calculate geometric center
    sum_x = sum(c[0] for c in ca_coords)
    sum_y = sum(c[1] for c in ca_coords)
    sum_z = sum(c[2] for c in ca_coords)
    n = len(ca_coords)
    center = (sum_x / n, sum_y / n, sum_z / n)

    # Format expected lines
    expected_lines = ["X,Y,Z"]
    for x, y, z in ca_coords:
        expected_lines.append(f"{x:.3f},{y:.3f},{z:.3f}")
    expected_lines.append(f"{center[0]:.3f},{center[1]:.3f},{center[2]:.3f}")

    # Read actual CSV
    with open(csv_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows, but got {len(actual_lines)}."

    assert actual_lines[0] == expected_lines[0], f"Header mismatch. Expected '{expected_lines[0]}', got '{actual_lines[0]}'."

    for i in range(1, len(expected_lines) - 1):
        assert actual_lines[i] == expected_lines[i], f"Coordinate mismatch at row {i + 1}. Expected '{expected_lines[i]}', got '{actual_lines[i]}'."

    assert actual_lines[-1] == expected_lines[-1], f"Geometric center mismatch. Expected '{expected_lines[-1]}', got '{actual_lines[-1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
