#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest

BASE = "/home/user/experiment_data"
PARQUET_PATH = os.path.join(BASE, "processed", "consolidated.parquet")
RESULTS_PATH = os.path.join(BASE, "results", "correlations.json")
MODEL_PATH = os.path.join(BASE, "model", "architecture_and_weights.json")
SCRIPT_PATH = os.path.join(BASE, "verify_pipeline.py")
FEATURES = [f"feature_{i}" for i in range(20)]


def load_weights():
    assert os.path.isfile(MODEL_PATH), "Original model weights missing."
    with open(MODEL_PATH, "r") as f:
        weights = json.load(f)
    return (
        np.asarray(weights["hidden.weight"], dtype=np.float64),
        np.asarray(weights["hidden.bias"], dtype=np.float64),
        np.asarray(weights["output.weight"], dtype=np.float64),
        np.asarray(weights["output.bias"], dtype=np.float64),
    )


def infer(data):
    hw, hb, ow, ob = load_weights()
    predictions = np.empty(data.shape[0], dtype=np.float64)
    batch_size = 20000
    for start in range(0, data.shape[0], batch_size):
        batch = data[start:start + batch_size]
        hidden = batch @ hw.T + hb
        np.maximum(hidden, 0.0, out=hidden)
        predictions[start:start + len(batch)] = (hidden @ ow.T + ob).reshape(-1)
    return predictions


def correlations(data):
    predictions = infer(data)
    centered_predictions = predictions - predictions.mean()
    prediction_ss = float(np.dot(centered_predictions, centered_predictions))
    result = {}
    for i, name in enumerate(FEATURES):
        feature = data[:, i]
        centered_feature = feature - feature.mean()
        feature_ss = float(np.dot(centered_feature, centered_feature))
        denominator = math.sqrt(feature_ss * prediction_ss)
        corr = float(np.dot(centered_feature, centered_predictions) / denominator) if denominator else 0.0
        result[name] = round(corr, 4)
    return result


def read_all_raw():
    chunks = []
    raw_dir = os.path.join(BASE, "raw")
    for i in range(50):
        csv_path = os.path.join(raw_dir, f"sim_{i}.csv")
        assert os.path.isfile(csv_path), f"Missing original CSV {csv_path}"
        chunk = pd.read_csv(csv_path, header=None).to_numpy(dtype=np.float64)
        assert chunk.shape == (10000, 20), f"Unexpected shape in {csv_path}: {chunk.shape}"
        chunks.append(chunk)
    return np.concatenate(chunks, axis=0)


def load_result(path=RESULTS_PATH):
    assert os.path.isfile(path), f"Correlations JSON missing at {path}"
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Correlations file is not valid JSON.")


def assert_correlations_match(actual, expected):
    assert isinstance(actual, dict), "Correlations JSON must contain a dictionary."
    for name in FEATURES:
        assert name in actual, f"Missing {name} in output JSON."
        assert isinstance(actual[name], (int, float)) and not isinstance(actual[name], bool), \
            f"Correlation for {name} must be numeric."
        assert math.isfinite(float(actual[name])), f"Correlation for {name} must be finite."
        assert abs(float(actual[name]) - expected[name]) <= 0.0002, \
            f"Mismatch in {name}. Expected {expected[name]}, got {actual[name]}"


def test_consolidated_parquet_exists():
    assert os.path.isfile(PARQUET_PATH), f"Parquet file missing at {PARQUET_PATH}"

    consolidated = pd.read_parquet(PARQUET_PATH)
    assert list(consolidated.columns) == FEATURES, \
        f"Parquet columns must be exactly {FEATURES}"
    assert consolidated.shape == (500000, 20), \
        f"Parquet must contain all 500,000 rows and 20 features, got {consolidated.shape}"

    values = consolidated.to_numpy(dtype=np.float64, copy=False)
    raw_dir = os.path.join(BASE, "raw")
    offset = 0
    for i in range(50):
        csv_path = os.path.join(raw_dir, f"sim_{i}.csv")
        assert os.path.isfile(csv_path), f"Missing original CSV {csv_path}"
        expected_chunk = pd.read_csv(csv_path, header=None).to_numpy(dtype=np.float64)
        actual_chunk = values[offset:offset + len(expected_chunk)]
        assert np.array_equal(actual_chunk, expected_chunk), \
            f"Parquet data does not exactly match {csv_path} at the required position"
        offset += len(expected_chunk)
    assert offset == 500000


def test_correlations_json_correctness():
    student_correlations = load_result()
    raw_data = read_all_raw()
    expected_correlations = correlations(raw_data)
    assert_correlations_match(student_correlations, expected_correlations)


def test_verify_pipeline_script():
    assert os.path.isfile(SCRIPT_PATH), f"Verification script missing at {SCRIPT_PATH}"

    # Exercise the script against a valid but deliberately altered parquet dataset.
    # This ensures it actually reads the parquet and recomputes model inference and
    # correlations rather than merely exiting successfully or preserving old output.
    original = pd.read_parquet(PARQUET_PATH)
    probe_values = original.to_numpy(dtype=np.float64, copy=True)[:, ::-1]
    probe_values *= np.linspace(0.5, 2.0, 20, dtype=np.float64)
    probe_values[:, 0] += np.linspace(-3.0, 3.0, len(probe_values), dtype=np.float64)
    probe = pd.DataFrame(probe_values, columns=FEATURES)
    expected_probe = correlations(probe_values)

    parquet_dir = os.path.dirname(PARQUET_PATH)
    fd, parquet_backup = tempfile.mkstemp(prefix="consolidated_backup_", suffix=".parquet", dir=parquet_dir)
    os.close(fd)
    shutil.copy2(PARQUET_PATH, parquet_backup)

    result_existed = os.path.isfile(RESULTS_PATH)
    result_backup = None
    if result_existed:
        with open(RESULTS_PATH, "rb") as f:
            result_backup = f.read()

    try:
        probe.to_parquet(PARQUET_PATH, index=False)
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)

        completed = subprocess.run(
            ["python3", SCRIPT_PATH],
            capture_output=True,
            text=True
        )
        assert completed.returncode == 0, \
            f"verify_pipeline.py failed with exit code {completed.returncode}.\nStderr: {completed.stderr}"

        recomputed = load_result()
        assert_correlations_match(recomputed, expected_probe)
    finally:
        os.replace(parquet_backup, PARQUET_PATH)
        if result_existed:
            os.makedirs(os.path.dirname(RESULTS_PATH), exist_ok=True)
            with open(RESULTS_PATH, "wb") as f:
                f.write(result_backup)
        elif os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
