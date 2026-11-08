#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math

import h5py
import numpy as np
from sklearn.decomposition import PCA

RAW_PATH = '/home/user/raw_data.csv'
LOG_PATH = '/home/user/experiment_log.json'
H5_PATH = '/home/user/reduced_features.h5'

# Independently derive the required PCA result from the source data.
raw_data = np.loadtxt(RAW_PATH, delimiter=',')
reference_pca = PCA()
reference_pca.fit(raw_data)
cumulative_variance = np.cumsum(reference_pca.explained_variance_ratio_)
expected_components = int(np.searchsorted(cumulative_variance, 0.95, side='left') + 1)
expected_features = reference_pca.transform(raw_data)[:, :expected_components]
expected_reconstruction = (
    expected_features @ reference_pca.components_[:expected_components] + reference_pca.mean_
)
expected_max_error = float(np.max(np.abs(raw_data - expected_reconstruction)))


def test_experiment_log():
    assert os.path.exists(LOG_PATH), f"Experiment log not found at {LOG_PATH}"

    with open(LOG_PATH, 'r') as f:
        try:
            log = json.load(f)
        except json.JSONDecodeError:
            assert False, "experiment_log.json is not valid JSON"

    assert 'optimal_components' in log, "Missing 'optimal_components' in experiment_log.json"
    assert 'reconstruction_max_error' in log, "Missing 'reconstruction_max_error' in experiment_log.json"
    assert set(log.keys()) == {'optimal_components', 'reconstruction_max_error'}, \
        "experiment_log.json must contain exactly the two required keys"

    assert type(log['optimal_components']) is int, "optimal_components must be an integer"
    assert log['optimal_components'] == expected_components, (
        f"Expected {expected_components} optimal components, got {log['optimal_components']}"
    )

    # Preserve the original fixed-data assertion.
    assert log['optimal_components'] == 50, \
        f"Expected 50 optimal components, got {log['optimal_components']}"

    max_error = log['reconstruction_max_error']
    assert isinstance(max_error, (int, float)) and not isinstance(max_error, bool), \
        "reconstruction_max_error must be a number"
    assert math.isfinite(max_error), "reconstruction_max_error must be finite"

    # Preserve the original fixed-data range assertion.
    assert 0.4 < max_error < 0.5, \
        f"Expected reconstruction_max_error to be around 0.44, got {max_error}"

    assert math.isclose(max_error, expected_max_error, rel_tol=1e-6, abs_tol=1e-5), (
        f"Incorrect reconstruction_max_error: expected {expected_max_error}, got {max_error}"
    )


def test_hdf5_file_exists_and_valid():
    assert os.path.exists(H5_PATH), f"HDF5 file not found at {H5_PATH}"
    assert os.path.isfile(H5_PATH), f"{H5_PATH} is not a file"

    # Preserve the original HDF5 signature assertion.
    with open(H5_PATH, 'rb') as f:
        header = f.read(8)
    expected_signature = b'\x89HDF\r\n\x1a\n'
    assert header == expected_signature, \
        f"File {H5_PATH} is not a valid HDF5 file (invalid signature)"

    with h5py.File(H5_PATH, 'r') as h5_file:
        assert 'features' in h5_file, "HDF5 file is missing the 'features' dataset"
        assert isinstance(h5_file['features'], h5py.Dataset), "'features' must be an HDF5 dataset"
        features = h5_file['features'][...]

    expected_shape = (raw_data.shape[0], expected_components)
    assert features.shape == expected_shape, \
        f"Expected features shape {expected_shape}, got {features.shape}"
    assert np.issubdtype(features.dtype, np.number), "features dataset must be numeric"
    assert np.all(np.isfinite(features)), "features dataset contains non-finite values"
    assert np.allclose(features, expected_features, rtol=1e-6, atol=2e-5), \
        "features dataset does not contain the PCA-transformed source data"

    # Also verify that the reported error agrees with reconstruction from the saved features.
    saved_reconstruction = (
        features @ reference_pca.components_[:expected_components] + reference_pca.mean_
    )
    saved_max_error = float(np.max(np.abs(raw_data - saved_reconstruction)))
    with open(LOG_PATH, 'r') as f:
        log = json.load(f)
    assert math.isclose(
        log['reconstruction_max_error'], saved_max_error, rel_tol=1e-6, abs_tol=1e-5
    ), "Reported reconstruction error does not agree with the saved reduced features"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
