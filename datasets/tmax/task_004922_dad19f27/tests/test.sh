#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
import h5py
import pytest

RAW_PATH = "/home/user/raw_data.h5"
FEATURES_PATH = "/home/user/training_features.h5"
MEANS_PATH = "/home/user/feature_means.txt"


def compute_expected():
    with h5py.File(RAW_PATH, "r") as f:
        sequences = f["sequences"][:]
        interaction_matrix = np.asarray(f["interaction_matrix"][:], dtype=np.float64)

    rhs = []
    for raw_sequence in sequences:
        if isinstance(raw_sequence, bytes):
            sequence = raw_sequence.decode("ascii").rstrip("\x00")
        else:
            sequence = bytes(raw_sequence).decode("ascii").rstrip("\x00")

        counts = np.array([sequence.count(n) for n in "ACGT"], dtype=np.float64)
        rhs.append(counts / len(sequence))

    rhs = np.asarray(rhs, dtype=np.float64)
    features = np.linalg.solve(interaction_matrix, rhs.T).T
    return features, np.mean(features, axis=0)


def test_feature_means_file():
    assert os.path.exists(MEANS_PATH), f"{MEANS_PATH} does not exist."
    _, expected_means = compute_expected()

    with open(MEANS_PATH, "r") as f:
        student_content = f.read().strip()

    student_means = [x.strip() for x in student_content.split(",")]
    assert len(student_means) == 4, \
        f"Expected 4 comma-separated means, got {len(student_means)} in {MEANS_PATH}."

    try:
        parsed_means = np.asarray([float(x) for x in student_means], dtype=np.float64)
    except ValueError as exc:
        pytest.fail(f"Could not parse mean value as float: {exc}")

    assert np.all(np.isfinite(parsed_means)), "Mean values must all be finite."
    np.testing.assert_allclose(parsed_means, expected_means, rtol=0.0, atol=1e-4)


def test_training_features_h5():
    assert os.path.exists(FEATURES_PATH), f"{FEATURES_PATH} does not exist."
    expected_features, _ = compute_expected()

    with h5py.File(FEATURES_PATH, "r") as f:
        assert "features" in f, "Dataset 'features' is missing in the HDF5 file."
        dataset = f["features"]
        assert dataset.shape == (1000, 4), \
            f"Incorrect shape for 'features' dataset: expected (1000, 4), got {dataset.shape}."
        assert str(dataset.dtype) == "float64", \
            f"Incorrect dtype for 'features' dataset: expected float64, got {dataset.dtype}."
        student_features = dataset[:]

    assert np.all(np.isfinite(student_features)), "Feature values must all be finite."
    np.testing.assert_allclose(student_features, expected_features, rtol=1e-8, atol=1e-10)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
