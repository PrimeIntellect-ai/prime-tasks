#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def dot_product(v1, v2):
    return sum(x * y for x, y in zip(v1, v2))

def matrix_vector_mult(mat, vec):
    return [dot_product(row, vec) for row in mat]

def norm(vec):
    return math.sqrt(sum(x * x for x in vec))

def cosine_similarity(v1, v2):
    n1 = norm(v1)
    n2 = norm(v2)
    if n1 == 0 or n2 == 0:
        return 0.0
    return dot_product(v1, v2) / (n1 * n2)

def compute_expected_top_3():
    # Read weights
    weights_path = "/home/user/data/weights.csv"
    assert os.path.exists(weights_path), f"Missing {weights_path}"
    with open(weights_path, "r") as f:
        reader = csv.reader(f)
        W = [[float(x) for x in row] for row in reader]

    # Read target
    target_path = "/home/user/data/target.csv"
    assert os.path.exists(target_path), f"Missing {target_path}"
    with open(target_path, "r") as f:
        reader = csv.reader(f)
        target = [float(x) for x in next(reader)]

    target_transformed = matrix_vector_mult(W, target)

    # Read items
    items_path = "/home/user/data/items.csv"
    assert os.path.exists(items_path), f"Missing {items_path}"
    similarities = []
    with open(items_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            item_id = int(row[0])
            features = [float(x) for x in row[1:]]
            item_transformed = matrix_vector_mult(W, features)
            sim = cosine_similarity(target_transformed, item_transformed)
            similarities.append((sim, item_id))

    # Sort descending by similarity
    similarities.sort(key=lambda x: x[0], reverse=True)
    return [x[1] for x in similarities[:3]]

def test_c_source_exists():
    """Check that the C source code exists."""
    assert os.path.isfile("/home/user/recommend.c"), "The C source file /home/user/recommend.c is missing."

def test_executable_exists():
    """Check that the compiled executable exists and is executable."""
    exe_path = "/home/user/recommend"
    assert os.path.isfile(exe_path), f"The executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."

def test_recommendations_output():
    """Check that the recommendations output matches the expected top 3 IDs."""
    output_path = "/home/user/recommendations.txt"
    assert os.path.isfile(output_path), f"The output file {output_path} is missing."

    with open(output_path, "r") as f:
        lines = f.read().strip().splitlines()

    actual_ids = []
    for line in lines:
        line = line.strip()
        if line:
            try:
                actual_ids.append(int(line))
            except ValueError:
                pytest.fail(f"Invalid non-integer ID found in {output_path}: {line}")

    expected_ids = compute_expected_top_3()

    assert len(actual_ids) == 3, f"Expected exactly 3 IDs in {output_path}, but found {len(actual_ids)}."
    assert actual_ids == expected_ids, f"Output IDs {actual_ids} do not match the expected top 3 IDs {expected_ids}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
