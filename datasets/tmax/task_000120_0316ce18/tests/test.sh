#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

import pytest

RAW_PATH = "/app/raw_data.csv"
EVAL_PATH = "/app/eval_data.csv"
AUDIO_PATH = "/app/backup_log.wav"
CLEAN_PATH = "/home/user/clean_data.csv"
STATS_PATH = "/home/user/model_stats.txt"
PREDICTIONS_PATH = "/home/user/predictions.csv"


def read_csv(path):
    with open(path, newline="") as f:
        return list(csv.reader(f))


def derive_expected_data():
    transcript = subprocess.check_output(
        ["/usr/local/bin/transcriber", AUDIO_PATH], text=True
    )
    recovered = {
        timestamp: value
        for timestamp, value in re.findall(
            r"At timestamp\s+(\d+),\s+the value is\s+(-?\d+)\.", transcript
        )
    }

    raw = read_csv(RAW_PATH)
    assert raw and raw[0] == ["Timestamp", "SensorA", "SensorB"]

    expected_clean = [raw[0]]
    points = []
    for row in raw[1:]:
        assert len(row) == 3
        timestamp, sensor_a, sensor_b = row
        if sensor_a == "NaN":
            assert timestamp in recovered, f"No transcription value for {timestamp}"
            sensor_a = recovered[timestamp]
        expected_clean.append([timestamp, sensor_a, sensor_b])
        points.append((float(sensor_a), float(sensor_b)))

    n = len(points)
    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n
    ss_x = sum((x - mean_x) ** 2 for x, _ in points)
    ss_y = sum((y - mean_y) ** 2 for _, y in points)
    cross = sum((x - mean_x) * (y - mean_y) for x, y in points)
    slope = cross / ss_x
    intercept = mean_y - slope * mean_x
    correlation = cross / math.sqrt(ss_x * ss_y)

    evaluation = read_csv(EVAL_PATH)
    assert evaluation and evaluation[0] == ["Timestamp", "SensorA"]
    expected_predictions = [
        (row[0], slope * float(row[1]) + intercept) for row in evaluation[1:]
    ]
    return expected_clean, slope, intercept, correlation, expected_predictions


EXPECTED_CLEAN, EXPECTED_SLOPE, EXPECTED_INTERCEPT, EXPECTED_CORRELATION, EXPECTED_PREDICTIONS = derive_expected_data()


def test_predictions_mse():
    assert os.path.isfile(PREDICTIONS_PATH), f"Predictions file missing at {PREDICTIONS_PATH}"

    rows = read_csv(PREDICTIONS_PATH)
    assert rows, "Predictions file is empty or missing a header"
    assert rows[0] == ["Timestamp", "PredictedSensorB"], "Invalid predictions header"
    assert len(rows) == len(EXPECTED_PREDICTIONS) + 1, "Predictions must contain exactly one row per evaluation timestamp"

    sum_sq_err = 0.0
    count = 0
    for row, (expected_timestamp, expected_value) in zip(rows[1:], EXPECTED_PREDICTIONS):
        assert len(row) == 2, "Each prediction row must contain exactly two columns"
        assert row[0] == expected_timestamp, f"Missing, duplicate, or out-of-order prediction for timestamp {expected_timestamp}"
        try:
            predicted = float(row[1])
        except ValueError:
            pytest.fail(f"Invalid predicted value for timestamp {row[0]}: '{row[1]}'")
        assert math.isfinite(predicted), f"Non-finite prediction for timestamp {row[0]}"
        difference = predicted - expected_value
        sum_sq_err += difference * difference
        count += 1

    assert count == len(EXPECTED_PREDICTIONS), "Not all evaluation timestamps were predicted"
    mse = sum_sq_err / count
    threshold = 0.5
    assert mse <= threshold, f"MSE {mse:.4f} exceeds the threshold of {threshold}."


def test_auxiliary_files_exist_and_are_valid():
    assert os.path.isfile(CLEAN_PATH), f"Cleaned dataset missing at {CLEAN_PATH}"
    assert os.path.isfile(STATS_PATH), f"Model stats file missing at {STATS_PATH}"

    actual_clean = read_csv(CLEAN_PATH)
    assert actual_clean == EXPECTED_CLEAN, "clean_data.csv does not correctly impute and preserve the source dataset"
    assert all("NaN" not in row for row in actual_clean[1:]), "clean_data.csv still contains NaN values"

    with open(STATS_PATH) as f:
        lines = [line.rstrip("\n") for line in f]
    assert len(lines) == 3, "model_stats.txt must contain exactly three lines"

    expected_names = ["Slope", "Intercept", "Correlation"]
    values = {}
    number_pattern = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
    for line, name in zip(lines, expected_names):
        match = re.fullmatch(rf"{name}:\s*({number_pattern})", line)
        assert match, f"Invalid {name} line in model_stats.txt"
        value = float(match.group(1))
        assert math.isfinite(value), f"{name} must be finite"
        values[name] = value

    assert values["Slope"] == pytest.approx(EXPECTED_SLOPE, abs=1e-4)
    assert values["Intercept"] == pytest.approx(EXPECTED_INTERCEPT, abs=1e-4)
    assert values["Correlation"] == pytest.approx(EXPECTED_CORRELATION, abs=1e-4)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
