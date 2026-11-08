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
from sklearn.linear_model import Ridge
from sklearn.model_selection import KFold, cross_val_score

SCRIPT_PATH = "/home/user/run_analysis.sh"
RESULTS_PATH = "/home/user/results.json"
DATA_PATH = "/home/user/sensor_data.csv"
EXPECTED_KEYS = ["correlation", "bootstrap_ci_5th", "bootstrap_ci_95th", "best_alpha"]


def run_script():
    if os.path.lexists(RESULTS_PATH):
        os.unlink(RESULTS_PATH)

    completed = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(RESULTS_PATH), (
        f"The file {RESULTS_PATH} does not exist after executing the script."
    )
    assert os.path.isfile(RESULTS_PATH), f"The path {RESULTS_PATH} is not a file."

    try:
        with open(RESULTS_PATH, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"The file {RESULTS_PATH} does not contain valid JSON: {exc}")


def assert_result(results, expected, tolerance=0.0002):
    for key in EXPECTED_KEYS:
        assert key in results, f"Key '{key}' is missing from {RESULTS_PATH}."

    for key, expected_value in expected.items():
        actual = results[key]
        assert isinstance(actual, (int, float)), f"Value for '{key}' should be a number."
        assert math.isclose(actual, expected_value, abs_tol=tolerance), (
            f"Value for '{key}' is {actual}, expected {expected_value} "
            f"(within +/- {tolerance})."
        )


def reference_analysis(path):
    df = pd.read_csv(path)
    temp = df["temp"].to_numpy()
    pressure = df["pressure"].to_numpy()

    correlation = np.corrcoef(temp, pressure)[0, 1]

    np.random.seed(42)
    bootstrap_correlations = []
    for _ in range(1000):
        indices = np.random.choice(len(df), size=len(df), replace=True)
        bootstrap_correlations.append(
            np.corrcoef(temp[indices], pressure[indices])[0, 1]
        )

    ci_5th, ci_95th = np.percentile(bootstrap_correlations, [5, 95])

    features = df[["temp", "pressure", "humidity"]]
    target = df["vibration"]
    folds = KFold(n_splits=5, shuffle=True, random_state=42)
    mse_by_alpha = {}
    for alpha in (0.1, 1.0, 10.0):
        scores = cross_val_score(
            Ridge(alpha=alpha),
            features,
            target,
            cv=folds,
            scoring="neg_mean_squared_error",
        )
        mse_by_alpha[alpha] = -scores.mean()

    return {
        "correlation": round(float(correlation), 4),
        "bootstrap_ci_5th": round(float(ci_5th), 4),
        "bootstrap_ci_95th": round(float(ci_95th), 4),
        "best_alpha": float(min(mse_by_alpha, key=mse_by_alpha.get)),
    }


def test_analysis_pipeline_executes_and_computes_results():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").lower()
    assert first_line.startswith("#!") and "bash" in first_line, (
        f"{SCRIPT_PATH} must be an executable Bash script."
    )

    original_results = run_script()
    assert_result(
        original_results,
        {
            "correlation": 0.7788,
            "bootstrap_ci_5th": 0.7570,
            "bootstrap_ci_95th": 0.7998,
            "best_alpha": 10.0,
        },
    )
    original_results_bytes = open(RESULTS_PATH, "rb").read()

    fd, backup_path = tempfile.mkstemp(prefix="sensor_data_backup_", suffix=".csv")
    os.close(fd)
    shutil.copy2(DATA_PATH, backup_path)
    try:
        varied = pd.read_csv(DATA_PATH)
        row = np.arange(len(varied), dtype=float)
        varied["pressure"] = (
            -2.0 * varied["temp"]
            + 0.15 * varied["humidity"]
            + 8.0 * np.sin(row / 7.0)
        )
        varied["vibration"] = (
            1.2 * varied["temp"]
            + 0.4 * varied["pressure"]
            - 0.3 * varied["humidity"]
            + 3.0 * np.cos(row / 11.0)
        )
        varied.to_csv(DATA_PATH, index=False)

        expected_varied = reference_analysis(DATA_PATH)
        varied_results = run_script()
        assert_result(varied_results, expected_varied)
    finally:
        shutil.copy2(backup_path, DATA_PATH)
        os.unlink(backup_path)
        with open(RESULTS_PATH, "wb") as f:
            f.write(original_results_bytes)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
