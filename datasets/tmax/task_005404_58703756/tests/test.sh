#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess

import numpy as np
import pytest

REPORT_PATH = "/home/user/metrics_report.json"
SCRIPT_PATH = "/home/user/clean_and_bootstrap.py"
RAW_PATH = "/home/user/raw_data.csv"
EXPECTED_KEYS = {
    "cleaned_row_count",
    "mean_memory_ratio",
    "cpu_usage_bootstrap_mean",
    "cpu_usage_95_ci_lower",
    "cpu_usage_95_ci_upper",
}


@pytest.fixture(scope="session", autouse=True)
def run_submission_on_original_data():
    """Require the requested script and execute it on the original dataset."""
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} was not created."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed on the original data.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_metrics_report_exists():
    """Test that the metrics report JSON file was created."""
    assert os.path.exists(REPORT_PATH), f"File {REPORT_PATH} was not created."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."


def test_metrics_report_content():
    """Test that the metrics report contains the correctly computed values."""
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    expected_keys = {
        "cleaned_row_count",
        "mean_memory_ratio",
        "cpu_usage_bootstrap_mean",
        "cpu_usage_95_ci_lower",
        "cpu_usage_95_ci_upper"
    }

    assert set(data.keys()) == expected_keys, f"JSON keys do not match expected keys. Found: {list(data.keys())}"

    # Check cleaned_row_count
    assert data["cleaned_row_count"] == 6, f"Expected cleaned_row_count to be 6, got {data['cleaned_row_count']}"

    # Check mean_memory_ratio
    expected_memory_ratio = 0.5052
    assert math.isclose(data["mean_memory_ratio"], expected_memory_ratio, abs_tol=1e-3), \
        f"Expected mean_memory_ratio close to {expected_memory_ratio}, got {data['mean_memory_ratio']}"

    # Check bootstrap statistics
    expected_boot_mean = 50.2982
    expected_ci_lower = 45.5333
    expected_ci_upper = 55.1500

    assert math.isclose(data["cpu_usage_bootstrap_mean"], expected_boot_mean, abs_tol=1e-2), \
        f"Expected cpu_usage_bootstrap_mean close to {expected_boot_mean}, got {data['cpu_usage_bootstrap_mean']}"

    assert math.isclose(data["cpu_usage_95_ci_lower"], expected_ci_lower, abs_tol=1e-2), \
        f"Expected cpu_usage_95_ci_lower close to {expected_ci_lower}, got {data['cpu_usage_95_ci_lower']}"

    assert math.isclose(data["cpu_usage_95_ci_upper"], expected_ci_upper, abs_tol=1e-2), \
        f"Expected cpu_usage_95_ci_upper close to {expected_ci_upper}, got {data['cpu_usage_95_ci_upper']}"


def test_script_recomputes_metrics_for_unseen_data():
    """Run the submitted ETL on a held-out dataset and derive its expected output."""
    original_raw = open(RAW_PATH, "rb").read()
    rng = secrets.SystemRandom()

    rows = []
    for i in range(9):
        rows.append([
            f"2024-02-{i + 1:02d}",
            f"{rng.uniform(3.0, 97.0):.3f}",
            str(rng.randint(3000, 15000)),
            str(rng.randint(0, 4)),
        ])
    # Zero and 100 are valid because filtering is strictly outside the range.
    rows.extend([
        ["2024-03-01", "0.0", "4000", "0"],
        ["2024-03-02", "100.0", "12000", "1"],
        ["2024-03-03", "NULL", "7000", "0"],
        ["2024-03-04", "", "7100", "0"],
        ["2024-03-05", "NaN", "7200", "0"],
        ["2024-03-06", "-0.001", "7300", "0"],
        ["2024-03-07", "100.001", "7400", "0"],
    ])
    rng.shuffle(rows)

    try:
        with open(RAW_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "cpu_usage", "memory_usage_mb", "disk_io_errors"])
            writer.writerows(rows)

        cleaned_cpu = []
        cleaned_memory = []
        for row in rows:
            try:
                cpu = float(row[1])
            except ValueError:
                continue
            if math.isnan(cpu) or cpu < 0.0 or cpu > 100.0:
                continue
            cleaned_cpu.append(cpu)
            cleaned_memory.append(float(row[2]))

        cpu_array = np.asarray(cleaned_cpu, dtype=float)
        np.random.seed(42)
        bootstrap_means = []
        for _ in range(1000):
            sample = np.random.choice(cpu_array, size=len(cpu_array), replace=True)
            bootstrap_means.append(float(np.mean(sample)))

        expected = {
            "cleaned_row_count": len(cleaned_cpu),
            "mean_memory_ratio": round(float(np.mean(np.asarray(cleaned_memory) / 16000.0)), 4),
            "cpu_usage_bootstrap_mean": round(float(np.mean(bootstrap_means)), 4),
            "cpu_usage_95_ci_lower": round(float(np.percentile(bootstrap_means, 2.5)), 4),
            "cpu_usage_95_ci_upper": round(float(np.percentile(bootstrap_means, 97.5)), 4),
        }

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"{SCRIPT_PATH} failed on held-out data.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(REPORT_PATH), "The script did not recreate metrics_report.json."

        with open(REPORT_PATH, "r") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"File {REPORT_PATH} is not valid JSON after rerunning the script.")

        assert set(actual.keys()) == EXPECTED_KEYS, (
            f"JSON keys do not match expected keys. Found: {list(actual.keys())}"
        )
        assert actual["cleaned_row_count"] == expected["cleaned_row_count"]
        for key in EXPECTED_KEYS - {"cleaned_row_count"}:
            assert isinstance(actual[key], float), f"{key} must be a float."
            assert actual[key] == expected[key], (
                f"Expected {key} to be {expected[key]}, got {actual[key]}"
            )
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
