#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import math
import os
import stat
import subprocess

import numpy as np
import pandas as pd
import pytest

DATASET_PATH = '/home/user/dataset.csv'
CLEANED_PATH = '/home/user/cleaned_dataset.csv'
RESULTS_PATH = '/home/user/inference_results.json'
SCRIPT_PATH = '/home/user/run_inference.py'

EXPECTED_SCRIPT = '''import pandas as pd
import numpy as np
import time
import json
import sys

try:
    df = pd.read_csv('/home/user/cleaned_dataset.csv')
    X = df.drop(columns=['y']).values
    # Add intercept
    X = np.c_[np.ones(X.shape[0]), X]
    y = df['y'].values

    start = time.time()
    # Fails if matrix is singular (collinear features)
    beta = np.linalg.inv(X.T @ X) @ X.T @ y
    end = time.time()

    out = {
        "features": list(df.drop(columns=['y']).columns),
        "weights": [round(b, 4) for b in beta],
        "inference_time_ms": (end - start) * 1000
    }
    with open('/home/user/inference_results.json', 'w') as f:
        json.dump(out, f)
    print("Success: inference_results.json created.")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
'''


def derive_expected_features(df):
    features = [c for c in df.columns if c != 'y']
    redundant = set()
    for later_index, later in enumerate(features):
        later_values = df[later].to_numpy(dtype=float)
        for earlier in features[:later_index]:
            earlier_values = df[earlier].to_numpy(dtype=float)
            design = np.column_stack([np.ones(len(df)), earlier_values])
            coefficients, _, _, _ = np.linalg.lstsq(design, later_values, rcond=None)
            if np.allclose(design @ coefficients, later_values, rtol=1e-10, atol=1e-10):
                redundant.add(later)
                break
    return [c for c in features if c not in redundant]


def regenerate_original_dataset_csv():
    np.random.seed(42)
    f1 = np.random.normal(0, 1, 100)
    f2 = np.random.normal(0, 1, 100)
    f3 = 3 * f1 - 2
    y = 2.5 * f1 - 1.2 * f2 + np.random.normal(0, 0.1, 100)
    expected = pd.DataFrame({'f1': f1, 'f2': f2, 'f3': f3, 'y': y})
    stream = io.StringIO()
    expected.to_csv(stream, index=False)
    return stream.getvalue()


@pytest.fixture(scope='session', autouse=True)
def execute_and_validate_artifacts():
    assert os.path.isfile(DATASET_PATH), f"Verification failed: {DATASET_PATH} is not a file."
    with open(DATASET_PATH, 'r', newline='') as f:
        actual_raw_csv = f.read()
    assert actual_raw_csv == regenerate_original_dataset_csv(), \
        "Verification failed: dataset.csv was modified."

    assert os.path.exists(CLEANED_PATH), f"Verification failed: {CLEANED_PATH} does not exist."
    assert os.path.isfile(CLEANED_PATH), f"Verification failed: {CLEANED_PATH} is not a file."

    raw = pd.read_csv(DATASET_PATH)
    cleaned = pd.read_csv(CLEANED_PATH)
    expected_features = derive_expected_features(raw)
    assert expected_features == ['f1', 'f2'], \
        f"Verification failed: expected derived nonredundant features ['f1', 'f2'], got {expected_features}."
    expected_cleaned = raw[expected_features + ['y']]
    pd.testing.assert_frame_equal(cleaned, expected_cleaned, check_dtype=True, check_exact=True)

    assert os.path.isfile(SCRIPT_PATH), f"Verification failed: {SCRIPT_PATH} is not a file."
    with open(SCRIPT_PATH, 'r') as f:
        actual_script = f.read()
    assert actual_script == EXPECTED_SCRIPT, \
        "Verification failed: run_inference.py was modified."

    if os.path.lexists(RESULTS_PATH):
        mode = os.lstat(RESULTS_PATH).st_mode
        assert not stat.S_ISDIR(mode), \
            "Verification failed: inference_results.json is a directory."
        os.unlink(RESULTS_PATH)

    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "Verification failed: run_inference.py did not execute successfully.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.exists(RESULTS_PATH), \
        "Verification failed: running run_inference.py did not create inference_results.json."
    assert stat.S_ISREG(os.lstat(RESULTS_PATH).st_mode), \
        "Verification failed: inference_results.json is not a regular file."


def test_inference_results_exists():
    results_path = '/home/user/inference_results.json'
    assert os.path.exists(results_path), f"Verification failed: {results_path} does not exist."
    assert os.path.isfile(results_path), f"Verification failed: {results_path} is not a file."


def test_inference_results_content():
    results_path = '/home/user/inference_results.json'
    assert os.path.exists(results_path), f"Verification failed: {results_path} does not exist."

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Verification failed: {results_path} does not contain valid JSON.")

    assert 'features' in data, "Verification failed: 'features' key missing in JSON."
    assert 'weights' in data, "Verification failed: 'weights' key missing in JSON."
    assert 'inference_time_ms' in data, "Verification failed: 'inference_time_ms' key missing in JSON."

    raw = pd.read_csv(DATASET_PATH)
    expected_features = derive_expected_features(raw)
    actual_features = data.get('features')
    assert actual_features == expected_features, f"Verification failed: Expected features {expected_features}, got {actual_features}"

    expected_features_original = ['f1', 'f2']
    assert actual_features == expected_features_original, f"Verification failed: Expected features {expected_features_original}, got {actual_features}"

    X = raw[expected_features].to_numpy()
    X = np.c_[np.ones(X.shape[0]), X]
    y = raw['y'].to_numpy()
    recomputed_weights = [round(float(b), 4) for b in np.linalg.inv(X.T @ X) @ X.T @ y]
    actual_weights = data.get('weights', [])
    assert len(actual_weights) == len(recomputed_weights), \
        f"Verification failed: Incorrect number of weights. Expected {len(recomputed_weights)}, got {len(actual_weights)}."
    for expected, actual in zip(recomputed_weights, actual_weights):
        assert abs(expected - actual) <= 1e-12, \
            f"Verification failed: recomputed weight mismatch. Expected {expected}, got {actual}"

    expected_weights = [-0.0163, 2.4925, -1.2059]
    assert len(actual_weights) == 3, f"Verification failed: Incorrect number of weights. Expected 3, got {len(actual_weights)}."
    for expected, actual in zip(expected_weights, actual_weights):
        assert abs(expected - actual) <= 0.001, f"Verification failed: Weight mismatch. Expected ~{expected}, got {actual}"

    inference_time = data['inference_time_ms']
    assert isinstance(inference_time, (int, float)) and not isinstance(inference_time, bool), \
        "Verification failed: inference_time_ms must be numeric."
    assert math.isfinite(inference_time) and inference_time >= 0, \
        "Verification failed: inference_time_ms must be finite and nonnegative."


def test_cleaned_dataset_exists():
    cleaned_path = '/home/user/cleaned_dataset.csv'
    assert os.path.exists(cleaned_path), f"Verification failed: {cleaned_path} does not exist."
    assert os.path.isfile(cleaned_path), f"Verification failed: {cleaned_path} is not a file."

    with open(cleaned_path, 'r') as f:
        header = f.readline().strip().split(',')

    # Check that f3 is removed, but f1, f2, y are present
    assert 'f3' not in header, "Verification failed: 'f3' was not removed from cleaned_dataset.csv."
    assert 'f1' in header, "Verification failed: 'f1' is missing from cleaned_dataset.csv."
    assert 'f2' in header, "Verification failed: 'f2' is missing from cleaned_dataset.csv."
    assert 'y' in header, "Verification failed: 'y' is missing from cleaned_dataset.csv."

    raw = pd.read_csv(DATASET_PATH)
    cleaned = pd.read_csv(cleaned_path)
    expected_features = derive_expected_features(raw)
    pd.testing.assert_frame_equal(
        cleaned,
        raw[expected_features + ['y']],
        check_dtype=True,
        check_exact=True,
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
