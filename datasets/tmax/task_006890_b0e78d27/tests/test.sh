#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess

import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/etl_pipeline.py"
RAW_PATH = "/home/user/raw_telemetry.csv"
CLEAN_PATH = "/home/user/clean_telemetry.csv"
LOG_PATH = "/home/user/pipeline_log.json"


def run_pipeline():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_on_original_fixture():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."

    original = pd.DataFrame({
        "timestamp": [
            "2023-10-01T10:00:00", "2023-10-01T10:01:00",
            "2023-10-01T10:02:00", "2023-10-01T10:03:00",
            "2023-10-01T10:04:00", "2023-10-01T10:05:00",
            "2023-10-01T10:06:00",
        ],
        "temperature": [20.0, 22.0, np.nan, 32.0, 40.0, np.nan, 62.0],
        "pressure": [1013.25, np.nan, 1011.00, 1009.50, np.nan, 1005.00, 1002.25],
    })
    original.to_csv(RAW_PATH, index=False)
    for path in (CLEAN_PATH, LOG_PATH):
        if os.path.exists(path):
            os.remove(path)
    run_pipeline()


def test_clean_telemetry_file_exists():
    assert os.path.isfile(CLEAN_PATH), f"Output file {CLEAN_PATH} does not exist."


def test_pipeline_log_file_exists():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."


def test_clean_telemetry_content():
    expected_rows = [
        ["2023-10-01T10:00:00", "20.00", "1013.25", "0.00"],
        ["2023-10-01T10:01:00", "22.00", "1012.25", "2.00"],
        ["2023-10-01T10:02:00", "26.00", "1011.00", "4.00"],
        ["2023-10-01T10:03:00", "32.00", "1009.50", "6.00"],
        ["2023-10-01T10:04:00", "40.00", "1007.50", "8.00"],
        ["2023-10-01T10:05:00", "50.00", "1005.00", "10.00"],
        ["2023-10-01T10:06:00", "62.00", "1002.25", "12.00"],
    ]

    with open(CLEAN_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["timestamp", "temperature", "pressure", "temp_roc"], \
            f"Incorrect header in {CLEAN_PATH}: {header}"
        rows = list(reader)

    assert len(rows) == 7, f"Expected 7 data rows in {CLEAN_PATH}, found {len(rows)}"
    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual[0] == expected[0], \
            f"Row {i} timestamp mismatch: expected {expected[0]}, got {actual[0]}"
        try:
            temp = float(actual[1])
            pres = float(actual[2])
            roc = float(actual[3])
        except (ValueError, IndexError):
            pytest.fail(f"Row {i} contains invalid temperature, pressure, or temp_roc values.")
        assert f"{temp:.2f}" == expected[1], \
            f"Row {i} temperature mismatch: expected {expected[1]}, got {actual[1]}"
        assert f"{pres:.2f}" == expected[2], \
            f"Row {i} pressure mismatch: expected {expected[2]}, got {actual[2]}"
        assert f"{roc:.2f}" == expected[3], \
            f"Row {i} temp_roc mismatch: expected {expected[3]}, got {actual[3]}"


def test_pipeline_log_content():
    with open(LOG_PATH, "r") as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {LOG_PATH} is not valid JSON.")

    assert "imputed_temperature_count" in log_data
    assert "imputed_pressure_count" in log_data
    assert "max_temp_roc" in log_data
    assert log_data["imputed_temperature_count"] == 2
    assert log_data["imputed_pressure_count"] == 2
    max_roc = log_data["max_temp_roc"]
    assert isinstance(max_roc, (int, float)), "max_temp_roc should be a number."
    assert abs(max_roc - 12.0) < 1e-5, f"Expected max_temp_roc to be 12.0, got {max_roc}"


def test_pipeline_executes_on_unseen_input():
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    n = 11
    timestamps = pd.date_range("2025-02-03 08:00:00", periods=n, freq="3min").strftime("%Y-%m-%dT%H:%M:%S")
    temperature = 15.0 + np.cumsum(rng.uniform(-3.5, 6.0, n))
    pressure = 990.0 + np.cumsum(rng.uniform(-4.0, 3.0, n))
    temperature[[2, 5, 8]] = np.nan
    pressure[[1, 4, 7, 9]] = np.nan

    dynamic = pd.DataFrame({
        "timestamp": timestamps,
        "temperature": temperature,
        "pressure": pressure,
    })
    dynamic.to_csv(RAW_PATH, index=False)

    # Derive expected values from the exact serialized input supplied to the script.
    source = pd.read_csv(RAW_PATH)
    temp_missing = int(source["temperature"].isna().sum())
    pressure_missing = int(source["pressure"].isna().sum())
    expected = source.copy()
    expected["temperature"] = expected["temperature"].interpolate(method="polynomial", order=2)
    expected["pressure"] = expected["pressure"].interpolate(method="polynomial", order=2)
    expected["temp_roc"] = expected["temperature"].diff().fillna(0.0)
    expected[["temperature", "pressure", "temp_roc"]] = expected[
        ["temperature", "pressure", "temp_roc"]
    ].round(2)
    expected_max = round(float(expected["temp_roc"].max()), 2)

    for path in (CLEAN_PATH, LOG_PATH):
        if os.path.exists(path):
            os.remove(path)
    run_pipeline()

    assert os.path.isfile(CLEAN_PATH), "Pipeline did not create clean_telemetry.csv on unseen input."
    assert os.path.isfile(LOG_PATH), "Pipeline did not create pipeline_log.json on unseen input."

    actual = pd.read_csv(CLEAN_PATH, dtype={"timestamp": str})
    assert list(actual.columns) == ["timestamp", "temperature", "pressure", "temp_roc"]
    assert actual["timestamp"].tolist() == expected["timestamp"].tolist()
    for column in ("temperature", "pressure", "temp_roc"):
        assert pd.api.types.is_numeric_dtype(actual[column]), f"{column} must be numeric."
        np.testing.assert_allclose(
            actual[column].to_numpy(dtype=float),
            expected[column].to_numpy(dtype=float),
            rtol=0,
            atol=1e-9,
            err_msg=f"Incorrect dynamically computed {column}",
        )

    with open(LOG_PATH, "r") as f:
        log_data = json.load(f)
    assert set(log_data) == {
        "imputed_temperature_count", "imputed_pressure_count", "max_temp_roc"
    }
    assert log_data["imputed_temperature_count"] == temp_missing
    assert log_data["imputed_pressure_count"] == pressure_missing
    assert isinstance(log_data["max_temp_roc"], (int, float))
    assert abs(float(log_data["max_temp_roc"]) - expected_max) < 1e-9
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
