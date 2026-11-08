#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def get_expected_max_step():
    pdb_path = "/home/user/enzyme.pdb"
    assert os.path.isfile(pdb_path), f"File {pdb_path} is missing."

    z_coords = []
    with open(pdb_path, "r") as f:
        for line in f:
            if line.startswith("ATOM"):
                # PDB Z coordinate is typically at columns 47-54 (1-indexed)
                z_str = line[46:54].strip()
                if not z_str:
                    # fallback to split
                    parts = line.split()
                    z_str = parts[8]
                z_coords.append(float(z_str))

    assert len(z_coords) > 0, "No ATOM records found to calculate initial condition."
    y0 = sum(z_coords) / len(z_coords)

    def is_stable(h, y_init):
        y = y_init
        t = 0.0
        # To avoid floating point infinite loops, add a safety break
        steps = 0
        max_steps = int(10.0 / h) + 2
        while t < 10.0 and steps < max_steps:
            y = y - h * 0.1 * (y ** 3)
            t += h
            steps += 1
            if abs(y) > 1000.0:
                return False
        return True

    i = 1
    max_h = 0.0
    while True:
        h = i * 0.001
        if is_stable(h, y0):
            max_h = h
            i += 1
        else:
            break

    return f"{max_h:.3f}"

def test_max_step_file():
    result_path = "/home/user/max_step.txt"
    assert os.path.isfile(result_path), f"Expected result file {result_path} is missing."

    with open(result_path, "r") as f:
        content = f.read().strip()

    expected = get_expected_max_step()

    assert content == expected, f"Expected max step to be '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
