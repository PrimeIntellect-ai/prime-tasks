#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import pytest

def test_pipeline_script_exists_and_executable():
    path = "/home/user/pipeline.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."

def test_c_source_exists():
    path = "/home/user/matcher.c"
    assert os.path.isfile(path), f"{path} does not exist."

def test_executable_exists():
    path = "/home/user/matcher"
    assert os.path.isfile(path), f"{path} does not exist. Did pipeline.sh compile it?"
    assert os.access(path, os.X_OK), f"{path} is not executable."

def test_matches_csv_correctness():
    matches_path = "/home/user/matches.csv"
    assert os.path.isfile(matches_path), f"{matches_path} does not exist. Did pipeline.sh run successfully?"

    # Read sensors A
    data_a = {}
    with open('/home/user/sensors_A.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data_a[int(row['id'])] = (float(row['x']), float(row['y']), float(row['z']))

    # Read sensors B
    data_b = {}
    with open('/home/user/sensors_B.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data_b[int(row['id'])] = (float(row['x']), float(row['y']), float(row['z']))

    # Compute expected
    expected_matches = []
    for id_a in sorted(data_a.keys()):
        pt_a = data_a[id_a]
        min_dist = float('inf')
        best_b = -1
        for id_b, pt_b in data_b.items():
            dist = math.sqrt((pt_a[0]-pt_b[0])**2 + (pt_a[1]-pt_b[1])**2 + (pt_a[2]-pt_b[2])**2)
            if dist < min_dist:
                min_dist = dist
                best_b = id_b
            elif dist == min_dist and id_b < best_b:
                best_b = id_b
        expected_matches.append((str(id_a), str(best_b), f"{min_dist:.4f}"))

    # Read actual
    actual_matches = []
    with open(matches_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['id_A', 'id_B', 'distance'], f"Header in {matches_path} is incorrect. Expected ['id_A', 'id_B', 'distance'], got {header}"
        for row in reader:
            assert len(row) == 3, f"Row {row} does not have exactly 3 columns."
            actual_matches.append((row[0].strip(), row[1].strip(), row[2].strip()))

    assert len(actual_matches) == len(expected_matches), f"Expected {len(expected_matches)} rows, got {len(actual_matches)}."

    for i, (actual, expected) in enumerate(zip(actual_matches, expected_matches)):
        assert actual == expected, f"Mismatch at row {i+1} (excluding header). Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
