#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess
import sys

import h5py
import numpy as np
import pytest
from sklearn.decomposition import IncrementalPCA, PCA

SCRIPT_PATH = "/home/user/test_pca.py"
REPORT_PATH = "/home/user/report.json"
DATA_PATH = "/home/user/data/features.h5"
BACKUP_PATH = "/tmp/original_features.h5"


def calculate_expected(data):
    exact = PCA(n_components=10, svd_solver="full")
    incremental = IncrementalPCA(n_components=10, batch_size=100)
    exact.fit(data)
    incremental.fit(data)
    return float(np.max(np.abs(
        exact.explained_variance_ratio_ - incremental.explained_variance_ratio_
    )))


def execute_and_check(expected):
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"test_pca.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "Executing test_pca.py did not create report.json."

    try:
        with open(REPORT_PATH, "r") as f:
            report = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Generated report.json is not valid JSON: {exc}")

    assert set(report) == {"max_diff"}, "Generated report.json must contain exactly the key 'max_diff'."
    actual = report["max_diff"]
    assert isinstance(actual, float), "The generated max_diff must be a float."
    assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-12), (
        f"Script generated max_diff {actual}, independently calculated value is {expected}."
    )


def test_script_executes_pipeline_on_supplied_and_unseen_data():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    shutil.copy2(DATA_PATH, BACKUP_PATH)

    try:
        with h5py.File(DATA_PATH, "r") as f:
            original = f["dataset"][:]
        execute_and_check(calculate_expected(original))

        seed = int.from_bytes(os.urandom(8), "big")
        rng = np.random.default_rng(seed)
        alternate = rng.normal(size=(1000, 100))
        alternate[:, 10:20] += 0.35 * alternate[:, :10]
        alternate[:, 20:30] -= 0.2 * alternate[:, :10]
        with h5py.File(DATA_PATH, "w") as f:
            f.create_dataset("dataset", data=alternate)
        execute_and_check(calculate_expected(alternate))
    finally:
        shutil.copy2(BACKUP_PATH, DATA_PATH)
        with h5py.File(DATA_PATH, "r") as f:
            restored = f["dataset"][:]
        execute_and_check(calculate_expected(restored))


def test_script_exists():
    """Check if the user script was created."""
    script_path = "/home/user/test_pca.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."


def test_report_json_exists():
    """Check if the report.json file was created."""
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."


def test_report_json_content():
    """Check if report.json contains the correct max_diff value."""
    report_path = "/home/user/report.json"
    if not os.path.isfile(report_path):
        pytest.fail(f"Report file {report_path} does not exist.")

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert "max_diff" in data, "Key 'max_diff' not found in report.json."
    assert len(data) == 1, "report.json should contain exactly one key."

    actual_diff = data["max_diff"]
    assert isinstance(actual_diff, float), "The value for 'max_diff' must be a float."

    expected_diff = 0.00018596616462788574
    assert math.isclose(actual_diff, expected_diff, rel_tol=1e-3), (
        f"Expected max_diff to be approx {expected_diff}, but got {actual_diff}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
