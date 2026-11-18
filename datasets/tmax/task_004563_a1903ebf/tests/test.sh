#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess

import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/analyze.py"
CSV_PATH = "/home/user/sensor_data.csv"
JSON_PATH = "/home/user/similarities.json"
LOG_PATH = "/home/user/pipeline.log"
EXPECTED_KEYS = {"Device_B", "Device_C", "Device_D", "Device_E"}


def compute_expected(frame):
    df = frame.copy()
    df["timestamp"] = pd.to_datetime(df["timestamp"])
    sampled = df.groupby("device_id", group_keys=False).sample(frac=0.5, random_state=42)
    sampled["hour"] = sampled["timestamp"].dt.floor("h")
    aggregated = sampled.groupby(["device_id", "hour"])["value"].mean()

    full_hours = pd.date_range(
        df["timestamp"].min().floor("h"),
        df["timestamp"].max().floor("h"),
        freq="h",
    )
    series = {}
    for device in sorted(df["device_id"].unique()):
        values = aggregated.loc[device].reindex(full_hours).ffill().bfill()
        series[device] = values.to_numpy(dtype=float)

    reference = series["Device_A"]
    return {
        device: round(float(np.linalg.norm(values - reference)), 2)
        for device, values in series.items()
        if device != "Device_A"
    }


def run_pipeline():
    for path in (JSON_PATH, LOG_PATH):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=120,
    )


def assert_log():
    assert os.path.isfile(LOG_PATH), f"Log file missing at {LOG_PATH}"
    assert os.path.getsize(LOG_PATH) > 0, f"Log file {LOG_PATH} is empty."
    with open(LOG_PATH, "r", errors="replace") as f:
        text = f.read().lower()
    assert "sampl" in text, "Log must record completion of sampling."
    assert "aggregat" in text, "Log must record completion of aggregation."
    assert "distanc" in text, "Log must record completion of distance computation."


def assert_json(expected):
    assert os.path.isfile(JSON_PATH), f"Output JSON file missing at {JSON_PATH}"
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "distances" in data, "JSON must contain a 'distances' key at the root."
    distances = data["distances"]
    actual_keys = set(distances.keys())
    assert actual_keys == EXPECTED_KEYS, f"Expected devices {EXPECTED_KEYS}, but got {actual_keys}"

    for device, expected_val in expected.items():
        actual_val = distances[device]
        assert isinstance(actual_val, (int, float)), f"Value for {device} must be a number."
        assert abs(actual_val - expected_val) <= 0.05, \
            f"Expected distance for {device} to be near {expected_val}, but got {actual_val}"


@pytest.fixture(scope="module")
def original_state():
    assert os.path.exists(SCRIPT_PATH), f"Required script missing at {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a regular Python script, not a symlink"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file"
    with open(SCRIPT_PATH, "rb") as f:
        source = f.read()
    compile(source, SCRIPT_PATH, "exec")

    with open(CSV_PATH, "rb") as f:
        original_bytes = f.read()
    original_df = pd.read_csv(CSV_PATH)
    expected = compute_expected(original_df)
    run_pipeline()
    return original_bytes, original_df, expected


def test_pipeline_log_exists_and_not_empty(original_state):
    """Check that the logging requirement was met by executing the submitted script."""
    assert_log()


def test_similarities_json_structure_and_values(original_state):
    """Check valid JSON structure and distances derived independently from the CSV."""
    assert_json(original_state[2])


def test_pipeline_computes_results_instead_of_hardcoding(original_state):
    """Exercise the script on a second deterministic input with independently derived answers."""
    original_bytes, original_df, _ = original_state
    variant = original_df.copy()
    scales = {
        "Device_A": 1.30,
        "Device_B": 0.20,
        "Device_C": 1.70,
        "Device_D": -0.70,
        "Device_E": 0.50,
    }
    offsets = {
        "Device_A": 0.40,
        "Device_B": -1.00,
        "Device_C": 2.00,
        "Device_D": 0.30,
        "Device_E": -2.00,
    }
    variant["value"] = [
        value * scales[device] + offsets[device]
        for value, device in zip(variant["value"], variant["device_id"])
    ]
    expected_variant = compute_expected(variant)

    try:
        variant.to_csv(CSV_PATH, index=False)
        run_pipeline()
        assert_log()
        assert_json(expected_variant)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_bytes)
        run_pipeline()

    assert_json(original_state[2])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
