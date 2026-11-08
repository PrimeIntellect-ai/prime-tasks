#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess

import numpy as np
import pandas as pd
from scipy import stats

SCRIPT_PATH = "/home/user/dq_check.py"
CSV_PATH = "/home/user/transactions.csv"
JSON_PATH = "/home/user/dq_metrics.json"
EXPECTED_KEYS = {"mean", "ci_lower", "ci_upper", "t_statistic", "p_value"}


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"dq_check.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_metrics():
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} is missing."
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a file."
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {JSON_PATH} does not contain valid JSON."
    assert set(data.keys()) == EXPECTED_KEYS, (
        f"JSON keys do not match expected keys. Found: {list(data.keys())}"
    )
    return data


def expected_metrics_from_csv():
    frame = pd.read_csv(CSV_PATH)
    amounts = frame.loc[frame["amount"].notna() & (frame["amount"] >= 0), "amount"].to_numpy()

    mean = float(np.mean(amounts))
    np.random.seed(42)
    resamples = np.random.choice(amounts, size=(10000, len(amounts)), replace=True)
    sample_means = np.mean(resamples, axis=1)
    ci_lower, ci_upper = np.percentile(sample_means, [2.5, 97.5])
    t_statistic, p_value = stats.ttest_1samp(amounts, 150.0)

    return {
        "mean": round(mean, 4),
        "ci_lower": round(float(ci_lower), 4),
        "ci_upper": round(float(ci_upper), 4),
        "t_statistic": round(float(t_statistic), 4),
        "p_value": round(float(p_value), 4),
    }


def assert_metrics(data, expected):
    for key, expected_val in expected.items():
        val = data[key]
        assert isinstance(val, (int, float)), (
            f"Value for {key} should be a number, got {type(val)}."
        )
        assert math.isclose(val, expected_val, abs_tol=1e-4), (
            f"Value for {key} is incorrect. Expected {expected_val}, got {val}."
        )


def test_dq_check_script_exists():
    """Test that the python script was created."""
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."


def test_dq_metrics_json_exists():
    """Execute the submitted script and ensure it creates the output JSON."""
    if os.path.lexists(JSON_PATH):
        os.remove(JSON_PATH)
    run_script()
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} is missing."
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a file."


def test_dq_metrics_json_content():
    """Test that the output JSON file contains the correct metrics."""
    data = load_metrics()
    expected_values = {
        "mean": 155.6793,
        "ci_lower": 153.0782,
        "ci_upper": 158.2104,
        "t_statistic": 4.1352,
        "p_value": 0.0000,
    }
    assert_metrics(data, expected_values)


def test_script_computes_metrics_from_current_csv():
    """Replace the CSV with an unpredictable fixture and derive its answers independently."""
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_json = None
    if os.path.isfile(JSON_PATH):
        with open(JSON_PATH, "rb") as f:
            original_json = f.read()

    rng = secrets.SystemRandom()
    positive_amounts = [round(rng.uniform(70.0, 260.0), 6) for _ in range(17)]
    fixture_amounts = positive_amounts + [-1.0, -93.25, None]

    try:
        pd.DataFrame({
            "id": list(range(len(fixture_amounts))),
            "amount": fixture_amounts,
        }).to_csv(CSV_PATH, index=False)

        expected = expected_metrics_from_csv()
        if os.path.lexists(JSON_PATH):
            os.remove(JSON_PATH)
        run_script()
        data = load_metrics()
        assert_metrics(data, expected)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if os.path.lexists(JSON_PATH):
            os.remove(JSON_PATH)
        if original_json is not None:
            with open(JSON_PATH, "wb") as f:
                f.write(original_json)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
