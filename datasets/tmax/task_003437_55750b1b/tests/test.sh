#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import numpy as np


def test_files_exist():
    required_files = [
        "/home/user/compute_variance.c",
        "/home/user/evaluate.sh",
        "/home/user/fold_variances.csv"
    ]
    for path in required_files:
        assert os.path.isfile(path), f"Required file {path} is missing."


def test_csv_results():
    actual_path = "/home/user/fold_variances.csv"
    dataset_path = "/home/user/dataset.bin"

    assert os.path.isfile(dataset_path), f"Dataset file {dataset_path} is missing."
    assert os.path.isfile(actual_path), f"Output file {actual_path} is missing."

    data = np.memmap(dataset_path, dtype=np.float64, mode='r', shape=(10000, 50))
    expected_data = {}
    for fold in range(5):
        fold_data = data[fold * 2000:(fold + 1) * 2000, :]
        trace = np.sum(np.var(fold_data, axis=0, ddof=1))
        expected_data[str(fold)] = float(f"{trace:.4f}")

    with open(actual_path, 'r') as f:
        actual_reader = csv.DictReader(f)
        assert actual_reader.fieldnames is not None, "Output CSV is missing a header."
        assert 'Fold' in actual_reader.fieldnames and 'Trace' in actual_reader.fieldnames, \
            "Output CSV must have 'Fold' and 'Trace' headers."
        actual_data = {row['Fold'].strip(): float(row['Trace'].strip()) for row in actual_reader}

    for fold in [str(i) for i in range(5)]:
        assert fold in actual_data, f"Fold {fold} missing in output CSV."
        expected_val = expected_data[fold]
        actual_val = actual_data[fold]
        assert math.isclose(expected_val, actual_val, rel_tol=1e-3, abs_tol=1e-3), \
            f"Trace value mismatch for fold {fold}: expected approx {expected_val:.4f}, got {actual_val:.4f}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
