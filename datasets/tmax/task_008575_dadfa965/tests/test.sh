#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math

def test_best_model_exists_and_correct():
    best_model_path = "/home/user/best_model.txt"
    pdb_path = "/home/user/protein.pdb"
    csv_path = "/home/user/reference_models.csv"

    assert os.path.isfile(best_model_path), f"File {best_model_path} is missing."
    assert os.path.isfile(pdb_path), f"File {pdb_path} is missing."
    assert os.path.isfile(csv_path), f"File {csv_path} is missing."

    # 1. Parse PDB for Z-coordinates using the instructed 8th space-separated field.
    z_coords = []
    with open(pdb_path, "r") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 8 and parts[0] == "ATOM" and parts[2] == "CA":
                z_coords.append(float(parts[7]))

    assert len(z_coords) > 0, "No CA atoms found in protein.pdb"

    # 2. Linear regression
    n = len(z_coords)
    sum_x = sum(range(1, n + 1))
    sum_y = sum(z_coords)
    sum_xy = sum(x * y for x, y in zip(range(1, n + 1), z_coords))
    sum_xx = sum(x * x for x in range(1, n + 1))

    denominator = (n * sum_xx - sum_x ** 2)
    assert denominator != 0, "Denominator for linear regression is zero."

    m = (n * sum_xy - sum_x * sum_y) / denominator
    c = (sum_y - m * sum_x) / n

    # 3. Find best model
    best_model = None
    min_dist = float('inf')

    with open(csv_path, "r") as f:
        lines = f.readlines()

    # Skip header
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) == 3:
            model_name = parts[0]
            slope = float(parts[1])
            intercept = float(parts[2])

            dist = math.sqrt((m - slope) ** 2 + (c - intercept) ** 2)
            if dist < min_dist:
                min_dist = dist
                best_model = model_name

    assert best_model is not None, "No valid models found in reference_models.csv"

    # 4. Check student's output
    with open(best_model_path, "r") as f:
        student_output = f.read().strip()

    assert student_output == best_model, (
        f"Expected the best model to be '{best_model}', "
        f"but found '{student_output}' in {best_model_path}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
