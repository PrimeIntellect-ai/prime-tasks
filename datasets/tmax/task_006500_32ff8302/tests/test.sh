#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import sys
from datetime import datetime, timedelta, timezone

import numpy as np
import pandas as pd
from pandas.api.types import is_float_dtype

HOME = "/home/user"
SCRIPT = f"{HOME}/etl_pipeline.py"
RAW = f"{HOME}/raw_sensors.csv"
PARQUET = f"{HOME}/aligned_data.parquet"
ANOMALIES = f"{HOME}/anomalies.json"
LOG = f"{HOME}/etl.log"

ORIGINAL_CSV = """sensor_id,timestamp,value
temp_A,1672531260,70.0
temp_A,1672531440,72.0
press_B,2023-01-01T00:02:00Z,100.0
temp_A,1672531620,86.0
press_B,2023-01-01T00:06:00Z,102.0
press_B,2023-01-01T00:11:00Z,115.0
temp_A,1672532280,80.0
"""


def clear_outputs():
    for path in (PARQUET, ANOMALIES, LOG):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                raise AssertionError(f"Output path unexpectedly is a directory: {path}")
            os.remove(path)


def run_pipeline():
    assert os.path.exists(SCRIPT), f"Missing required script: {SCRIPT}"
    assert os.path.isfile(SCRIPT), f"Script path is not a file: {SCRIPT}"
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"ETL pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_and_check_parquet(expected_index, expected_values):
    # Preserve the original existence, regular-file, nonempty, and PAR1 assertions.
    assert os.path.exists(PARQUET), f"Missing required file: {PARQUET}"
    assert os.path.isfile(PARQUET), f"Path is not a file: {PARQUET}"
    assert os.path.getsize(PARQUET) > 0, f"File {PARQUET} is empty."
    with open(PARQUET, "rb") as f:
        assert f.read(4) == b"PAR1", (
            f"File {PARQUET} is not a valid Parquet file (missing PAR1 magic bytes)."
        )

    frame = pd.read_parquet(PARQUET)
    assert isinstance(frame.index, pd.DatetimeIndex), "Parquet index must be a DatetimeIndex."
    assert frame.index.tz is not None and str(frame.index.tz) == "UTC", (
        "Parquet index must contain UTC timestamps."
    )
    assert frame.index.equals(expected_index), (
        f"Incorrect aligned index. Expected {list(expected_index)}, got {list(frame.index)}"
    )
    assert list(frame.columns) == ["temp_A", "press_B"], (
        f"Expected exactly columns ['temp_A', 'press_B'], got {list(frame.columns)}"
    )
    assert is_float_dtype(frame["temp_A"].dtype), "temp_A must contain floats."
    assert is_float_dtype(frame["press_B"].dtype), "press_B must contain floats."
    np.testing.assert_allclose(
        frame[["temp_A", "press_B"]].to_numpy(dtype=float),
        np.asarray(expected_values, dtype=float),
        rtol=1e-10,
        atol=1e-10,
        equal_nan=True,
    )


def load_and_check_anomalies(expected):
    assert os.path.exists(ANOMALIES), f"Missing required file: {ANOMALIES}"
    with open(ANOMALIES, "r", encoding="utf-8") as f:
        anomalies = json.load(f)
    assert isinstance(anomalies, list), "Anomalies JSON must be a list of objects."
    assert len(anomalies) == len(expected), (
        f"Expected {len(expected)} anomalies, but found {len(anomalies)}."
    )

    # Preserve the original field-by-field exact-order assertions.
    for i, (actual, wanted) in enumerate(zip(anomalies, expected)):
        assert actual.get("timestamp") == wanted["timestamp"], (
            f"Mismatch in timestamp at index {i}. Expected {wanted['timestamp']}, "
            f"got {actual.get('timestamp')}"
        )
        assert actual.get("sensor_id") == wanted["sensor_id"], (
            f"Mismatch in sensor_id at index {i}. Expected {wanted['sensor_id']}, "
            f"got {actual.get('sensor_id')}"
        )
        assert actual.get("reason") == wanted["reason"], (
            f"Mismatch in reason at index {i}. Expected {wanted['reason']}, "
            f"got {actual.get('reason')}"
        )
        assert set(actual) == {"timestamp", "sensor_id", "reason"}, (
            f"Anomaly at index {i} must have exactly the required three fields."
        )


def check_log(count):
    assert os.path.exists(LOG), f"Missing required file: {LOG}"
    expected_msg = f"[INFO] Pipeline finished. Anomalies detected: {count}"
    with open(LOG, "r", encoding="utf-8") as f:
        log_content = f.read()
    # Preserve the original containment assertion.
    assert expected_msg in log_content, (
        f"Expected log message '{expected_msg}' not found in {LOG}."
    )
    nonempty_lines = [line for line in log_content.splitlines() if line]
    assert nonempty_lines and nonempty_lines[-1] == expected_msg, (
        "The pipeline's final log message has the wrong format or count."
    )


def test_pipeline_outputs_and_behavior():
    # Execute the submitted artifact on the supplied input and validate all outputs.
    with open(RAW, "w", encoding="utf-8") as f:
        f.write(ORIGINAL_CSV)
    clear_outputs()
    run_pipeline()

    original_index = pd.date_range(
        "2023-01-01T00:00:00Z", periods=4, freq="5min", tz="UTC"
    )
    load_and_check_parquet(
        original_index,
        [
            [71.0, 100.0],
            [86.0, 102.0],
            [86.0, 115.0],
            [80.0, 115.0],
        ],
    )
    original_anomalies = [
        {
            "timestamp": "2023-01-01T00:05:00Z",
            "sensor_id": "temp_A",
            "reason": "threshold_exceeded",
        },
        {
            "timestamp": "2023-01-01T00:10:00Z",
            "sensor_id": "press_B",
            "reason": "jump_exceeded",
        },
        {
            "timestamp": "2023-01-01T00:10:00Z",
            "sensor_id": "temp_A",
            "reason": "threshold_exceeded",
        },
    ]
    load_and_check_anomalies(original_anomalies)
    check_log(3)

    # Exercise the pipeline on fresh values and timestamps so fixed output files or
    # hardcoded answers cannot pass. Expected results are derived here independently.
    rng = secrets.SystemRandom()
    base = datetime(2024, 1, 1, tzinfo=timezone.utc) + timedelta(
        days=rng.randrange(300), hours=rng.randrange(24)
    )
    low = 60.0 + rng.randrange(0, 41) / 10.0
    high1 = 86.0 + rng.randrange(0, 31) / 10.0
    high2 = 87.0 + rng.randrange(0, 31) / 10.0
    pressure0 = 90.0 + rng.randrange(0, 101) / 10.0
    pressure_mid = pressure0 + 3.0
    pressure_jump = pressure_mid + 11.0 + rng.randrange(0, 31) / 10.0
    pressure_end = pressure_jump - 11.0 - rng.randrange(0, 31) / 10.0

    def epoch(minutes):
        return int((base + timedelta(minutes=minutes)).timestamp())

    def iso(minutes):
        return (base + timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")

    rows = [
        ["temp_A", str(epoch(1)), low],
        ["temp_A", str(epoch(4)), low + 4.0],
        ["temp_A", str(epoch(16)), high1],
        ["temp_A", str(epoch(21)), high2 - 2.0],
        ["temp_A", str(epoch(24)), high2 + 2.0],
        ["temp_A", str(epoch(31)), 75.0],
        ["press_B", iso(2), pressure0],
        ["press_B", iso(17), pressure_mid],
        ["press_B", iso(22), pressure_jump],
        ["press_B", iso(32), pressure_end],
    ]
    random.SystemRandom().shuffle(rows)
    with open(RAW, "w", encoding="utf-8") as f:
        f.write("sensor_id,timestamp,value\n")
        for sensor_id, timestamp, value in rows:
            f.write(f"{sensor_id},{timestamp},{value}\n")

    clear_outputs()
    run_pipeline()

    dynamic_index = pd.date_range(base, periods=7, freq="5min", tz="UTC")
    expected_values = [
        [low + 2.0, pressure0],
        [low + 2.0, pressure0],
        [np.nan, np.nan],
        [high1, pressure_mid],
        [high2, pressure_jump],
        [high2, pressure_jump],
        [75.0, pressure_end],
    ]
    load_and_check_parquet(dynamic_index, expected_values)

    def stamp(bin_number):
        return (base + timedelta(minutes=5 * bin_number)).strftime("%Y-%m-%dT%H:%M:%SZ")

    dynamic_anomalies = [
        {"timestamp": stamp(3), "sensor_id": "temp_A", "reason": "threshold_exceeded"},
        {"timestamp": stamp(4), "sensor_id": "press_B", "reason": "jump_exceeded"},
        {"timestamp": stamp(4), "sensor_id": "temp_A", "reason": "threshold_exceeded"},
        {"timestamp": stamp(5), "sensor_id": "temp_A", "reason": "threshold_exceeded"},
        {"timestamp": stamp(6), "sensor_id": "press_B", "reason": "jump_exceeded"},
    ]
    load_and_check_anomalies(dynamic_anomalies)
    check_log(5)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
