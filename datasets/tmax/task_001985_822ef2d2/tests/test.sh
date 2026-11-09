#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess
import tempfile
import uuid

import cv2
import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/log_sanitizer.py"
VIDEO_PATH = "/app/drone_feed.mp4"
TELEMETRY_PATH = "/home/user/visual_telemetry.csv"
SUMMARY_PATH = "/home/user/strata_summary.json"


def run_sanitizer(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    ).returncode


def test_log_sanitizer_adversarial_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Expected {SCRIPT_PATH} to be a file"

    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"
    assert os.path.exists(clean_dir), f"Missing directory: {clean_dir}"
    assert os.path.exists(evil_dir), f"Missing directory: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".csv")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".csv")]
    assert len(clean_files) > 0, "No clean corpus files found to test."
    assert len(evil_files) > 0, "No evil corpus files found to test."

    clean_failed = [os.path.basename(p) for p in clean_files if run_sanitizer(p) != 0]
    evil_failed = [os.path.basename(p) for p in evil_files if run_sanitizer(p) == 0]

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {clean_failed}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {evil_failed}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_log_sanitizer_on_path_neutral_generated_cases():
    assert os.path.isfile(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"

    smooth = [20.0 + i * 0.5 for i in range(20)]
    cases = []
    cases.append((smooth, 0, "ordinary smooth data"))

    boundary = [10.0] * 20
    boundary[10] = 60.0  # A jump of exactly 50 is allowed.
    cases.append((boundary, 0, "strict jump boundary"))

    zero_value = smooth.copy()
    zero_value[7] = 0.0
    cases.append((zero_value, 0, "zero is non-negative"))

    allowed_missing = smooth.copy()
    allowed_missing[4] = ""
    cases.append((allowed_missing, 0, "exactly five percent missing"))

    allowed_nan = smooth.copy()
    allowed_nan[8] = "NaN"
    cases.append((allowed_nan, 0, "NaN within five percent allowance"))

    excessive_missing = smooth.copy()
    excessive_missing[2] = ""
    excessive_missing[14] = "NaN"
    cases.append((excessive_missing, 1, "more than five percent missing"))

    negative = smooth.copy()
    negative[9] = -0.01
    cases.append((negative, 1, "negative reading"))

    jump = [10.0] * 20
    jump[11] = 60.001
    cases.append((jump, 1, "jump strictly greater than fifty"))

    injection = smooth.copy()
    injection[6] = "payload"
    cases.append((injection, 1, "non-numeric injection"))

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="telemetry_cases_") as directory:
        for readings, expected_code, description in cases:
            # Names and parent directory deliberately contain no clean/evil labels.
            path = os.path.join(directory, uuid.uuid4().hex + ".csv")
            with open(path, "w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(["timestamp", "sensor_reading"])
                for i, reading in enumerate(readings):
                    writer.writerow([f"{i / 10.0:.3f}", reading])
            actual_code = run_sanitizer(path)
            if actual_code != expected_code:
                failures.append(
                    f"{description}: expected exit {expected_code}, got {actual_code}"
                )

    assert not failures, "Generated sanitizer failures: " + " | ".join(failures)


def expected_video_telemetry():
    capture = cv2.VideoCapture(VIDEO_PATH)
    assert capture.isOpened(), f"Could not open input video: {VIDEO_PATH}"
    luminance = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        if frame.ndim == 3:
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        luminance.append(float(np.mean(frame)))
    capture.release()

    assert luminance, "Input video contains no decodable frames"
    values = np.asarray(luminance, dtype=float)
    valid = values != 0.0
    assert valid.any(), "Input video has no valid non-black frames"
    indices = np.arange(len(values), dtype=float)
    values[~valid] = np.interp(indices[~valid], indices[valid], values[valid])
    return pd.DataFrame({
        "frame_index": np.arange(len(values), dtype=int),
        "timestamp": np.arange(len(values), dtype=float) / 30.0,
        "luminance": values,
    })


def test_visual_telemetry_exists_and_matches_video():
    assert os.path.exists(TELEMETRY_PATH), f"Missing visual telemetry output: {TELEMETRY_PATH}"
    assert os.path.isfile(TELEMETRY_PATH), f"Expected {TELEMETRY_PATH} to be a file"

    actual = pd.read_csv(TELEMETRY_PATH)
    assert list(actual.columns) == ["frame_index", "timestamp", "luminance"], (
        "Visual telemetry must have exactly frame_index,timestamp,luminance columns"
    )
    expected = expected_video_telemetry()
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} telemetry rows, found {len(actual)}"
    )

    frame_index = pd.to_numeric(actual["frame_index"], errors="coerce").to_numpy()
    timestamps = pd.to_numeric(actual["timestamp"], errors="coerce").to_numpy()
    luminance = pd.to_numeric(actual["luminance"], errors="coerce").to_numpy()
    assert np.isfinite(frame_index).all(), "frame_index contains invalid values"
    assert np.isfinite(timestamps).all(), "timestamp contains invalid values"
    assert np.isfinite(luminance).all(), "luminance contains invalid values"
    np.testing.assert_array_equal(frame_index, expected["frame_index"].to_numpy())
    np.testing.assert_allclose(
        timestamps, expected["timestamp"].to_numpy(), atol=0.0006, rtol=0
    )
    np.testing.assert_allclose(
        luminance, expected["luminance"].to_numpy(), atol=0.75, rtol=0
    )
    assert (luminance > 0).all(), "Black frames were not imputed"


def semantically_clean_log(path):
    frame = pd.read_csv(path, dtype=str, keep_default_na=True)
    if list(frame.columns) != ["timestamp", "sensor_reading"]:
        return False
    raw = frame["sensor_reading"]
    numeric = pd.to_numeric(raw, errors="coerce")
    nonnumeric = raw.notna() & numeric.isna()
    if nonnumeric.any():
        return False
    if len(frame) and numeric.isna().sum() / len(frame) > 0.05:
        return False
    if (numeric.dropna() < 0).any():
        return False
    if (numeric.diff().abs() > 50.0).any():
        return False
    return True


def expected_summary():
    visual = expected_video_telemetry()[["timestamp", "luminance"]].sort_values("timestamp")
    clean_frames = []
    for name in sorted(os.listdir("/app/sensor_logs")):
        path = os.path.join("/app/sensor_logs", name)
        if name.endswith(".csv") and semantically_clean_log(path):
            frame = pd.read_csv(path)
            frame["timestamp"] = pd.to_numeric(frame["timestamp"], errors="raise")
            frame["sensor_reading"] = pd.to_numeric(frame["sensor_reading"], errors="coerce")
            clean_frames.append(frame[["timestamp", "sensor_reading"]])
    assert clean_frames, "No semantically clean sensor logs found"

    sensors = pd.concat(clean_frames, ignore_index=True).sort_values("timestamp")
    merged = pd.merge_asof(
        sensors,
        visual,
        on="timestamp",
        direction="nearest",
        tolerance=0.01,
    )
    merged["window"] = (np.floor(merged["timestamp"] / 5.0) * 5).astype(int)

    result = {}
    for window, group in merged.groupby("window", sort=True):
        result[str(int(window))] = {
            "mean_luminance": round(float(group["luminance"].mean()), 2),
            "mean_sensor": round(float(group["sensor_reading"].mean()), 2),
            "count_luminance": int(group["luminance"].count()),
            "count_sensor": int(group["sensor_reading"].count()),
        }
    return result


def test_strata_summary_exists_format_and_values():
    assert os.path.exists(SUMMARY_PATH), f"Missing final aggregation output: {SUMMARY_PATH}"
    assert os.path.isfile(SUMMARY_PATH), f"Expected {SUMMARY_PATH} to be a file"

    with open(SUMMARY_PATH, "r") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_PATH} is not valid JSON")

    assert isinstance(data, dict), "Root JSON object must be a dictionary"
    assert data, "Summary must contain at least one stratum"

    expected_keys = {"mean_luminance", "mean_sensor", "count_luminance", "count_sensor"}
    for key, value in data.items():
        assert isinstance(key, str), f"Keys must be strings, got {type(key)}"
        assert key.isdigit(), f"Keys must be string representation of integers, got {key}"
        assert isinstance(value, dict), f"Value for key {key} must be a dictionary"
        missing_keys = expected_keys - set(value.keys())
        assert not missing_keys, f"Missing keys {missing_keys} in stratum {key}"
        for field in expected_keys:
            assert isinstance(value[field], (int, float)), (
                f"Expected numeric value for {field} in stratum {key}"
            )
            assert not isinstance(value[field], bool), f"Boolean is not valid for {field}"
            assert math.isfinite(value[field]), f"Non-finite value for {field} in stratum {key}"

    expected = expected_summary()
    assert set(data) == set(expected), (
        f"Expected strata {sorted(expected)}, found {sorted(data)}"
    )
    for key, wanted in expected.items():
        got = data[key]
        assert got["count_luminance"] == wanted["count_luminance"], (
            f"Wrong luminance count in stratum {key}"
        )
        assert got["count_sensor"] == wanted["count_sensor"], (
            f"Wrong sensor count in stratum {key}"
        )
        assert abs(got["mean_luminance"] - wanted["mean_luminance"]) <= 0.05, (
            f"Wrong mean luminance in stratum {key}: expected {wanted['mean_luminance']}, "
            f"got {got['mean_luminance']}"
        )
        assert abs(got["mean_sensor"] - wanted["mean_sensor"]) <= 0.011, (
            f"Wrong mean sensor reading in stratum {key}: expected {wanted['mean_sensor']}, "
            f"got {got['mean_sensor']}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
