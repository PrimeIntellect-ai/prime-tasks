#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import csv
import pytest

def test_correlated_features_file():
    input_path = '/home/user/raw_noise.csv'
    output_path = '/home/user/correlated_features.csv'

    assert os.path.exists(output_path), f"Output file not found: {output_path}"

    # Read raw noise
    raw_noise = []
    with open(input_path, 'r') as f:
        for line in f:
            if line.strip():
                raw_noise.append([float(x) for x in line.strip().split(',')])

    # Compute Cholesky decomposition of the target covariance matrix manually
    # C = [[1.0, 0.5, 0.2],
    #      [0.5, 1.0, 0.3],
    #      [0.2, 0.3, 1.0]]
    L = [
        [1.0, 0.0, 0.0],
        [0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0]
    ]
    L[0][0] = math.sqrt(1.0)
    L[1][0] = 0.5 / L[0][0]
    L[2][0] = 0.2 / L[0][0]
    L[1][1] = math.sqrt(1.0 - L[1][0]**2)
    L[2][1] = (0.3 - L[2][0]*L[1][0]) / L[1][1]
    L[2][2] = math.sqrt(1.0 - L[2][0]**2 - L[2][1]**2)

    # Read output
    with open(output_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['id', 'f1', 'f2', 'f3'], f"Incorrect headers. Expected ['id', 'f1', 'f2', 'f3'], got {header}"

        output_data = []
        for row in reader:
            if row:
                output_data.append(row)

    assert len(output_data) == len(raw_noise), f"Expected {len(raw_noise)} rows, got {len(output_data)}"

    for i in range(len(raw_noise)):
        z1, z2, z3 = raw_noise[i]

        # Expected X = L * Z
        e1 = L[0][0]*z1
        e2 = L[1][0]*z1 + L[1][1]*z2
        e3 = L[2][0]*z1 + L[2][1]*z2 + L[2][2]*z3

        out_id, out_f1, out_f2, out_f3 = output_data[i]

        assert int(out_id) == i, f"Row {i}: Expected id {i}, got {out_id}"

        f1, f2, f3 = float(out_f1), float(out_f2), float(out_f3)

        assert abs(f1 - e1) <= 1.5e-4, f"Row {i}: f1 expected {e1:.4f}, got {f1}"
        assert abs(f2 - e2) <= 1.5e-4, f"Row {i}: f2 expected {e2:.4f}, got {f2}"
        assert abs(f3 - e3) <= 1.5e-4, f"Row {i}: f3 expected {e3:.4f}, got {f3}"
TEST_EOF

if [ -f /home/user/augment.c ] \
   && gcc -std=c11 -O2 /home/user/augment.c -lm -o /tmp/augment_submission \
   && rm -f /home/user/correlated_features.csv \
   && (cd /home/user && timeout 30s /tmp/augment_submission) \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
