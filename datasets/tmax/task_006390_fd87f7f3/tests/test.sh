#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import statistics
import subprocess

import pytest

PIPELINE_DIR = "/home/user/pipeline"
INPUT_PATH = "/home/user/data/interactions.csv"
CSV_PATH = "/home/user/test_features_corrected.csv"
LOG_PATH = "/home/user/experiment_log.json"


@pytest.fixture(scope="session", autouse=True)
def run_pipeline():
    assert os.path.isfile(os.path.join(PIPELINE_DIR, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PIPELINE_DIR, "src", "main.rs")), "src/main.rs is missing."

    for path in (CSV_PATH, LOG_PATH):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PIPELINE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Rust pipeline failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_expected():
    with open(INPUT_PATH, "r", newline="") as f:
        rows = list(csv.DictReader(f))

    assert len(rows) == 1000, f"Expected 1000 input rows, got {len(rows)}."
    train = rows[:800]
    test = rows[800:]

    train_a = [float(row["feature_a"]) for row in train]
    train_b = [float(row["feature_b"]) for row in train]
    mean_a = statistics.mean(train_a)
    mean_b = statistics.mean(train_b)
    std_a = statistics.stdev(train_a)
    std_b = statistics.stdev(train_b)

    expected_rows = []
    normalized_test_a = []
    for row in test:
        norm_a = (float(row["feature_a"]) - mean_a) / std_a
        norm_b = (float(row["feature_b"]) - mean_b) / std_b
        normalized_test_a.append(norm_a)
        expected_rows.append((row["user_id"], norm_a, norm_b))

    test_mean = statistics.mean(normalized_test_a)
    test_std = statistics.stdev(normalized_test_a)
    margin = 1.960 * test_std / math.sqrt(len(normalized_test_a))

    expected_log = {
        "train_feature_a_mean": round(mean_a, 4),
        "train_feature_a_std": round(std_a, 4),
        "test_normalized_feature_a_mean": round(test_mean, 4),
        "test_normalized_feature_a_ci_lower": round(test_mean - margin, 4),
        "test_normalized_feature_a_ci_upper": round(test_mean + margin, 4),
    }
    return expected_rows, expected_log


def test_test_features_corrected_csv():
    assert os.path.exists(CSV_PATH), f"File {CSV_PATH} is missing."

    with open(CSV_PATH, "r", newline="") as f:
        reader = list(csv.reader(f))

    assert len(reader) == 201, (
        f"Expected 201 lines (1 header + 200 data rows) in {CSV_PATH}, got {len(reader)}."
    )

    header = reader[0]
    assert header == ["user_id", "feature_a_norm", "feature_b_norm"], f"Unexpected CSV header: {header}"

    first_data_row = reader[1]
    assert first_data_row[0] == "u_800", (
        f"Expected first data row user_id to be 'u_800', got {first_data_row[0]}"
    )

    expected_rows, _ = load_expected()
    expected_u_800_norm = expected_rows[0][1]
    feature_a_norm = float(first_data_row[1])
    assert math.isclose(feature_a_norm, expected_u_800_norm, abs_tol=0.001), (
        f"Expected u_800 normalized feature_a to be ~{expected_u_800_norm:.4f}, "
        f"got {feature_a_norm:.4f}."
    )

    for index, (actual, expected) in enumerate(zip(reader[1:], expected_rows), start=800):
        assert len(actual) == 3, f"Row for u_{index} must contain exactly 3 columns, got {actual}."
        expected_id, expected_a, expected_b = expected
        assert actual[0] == expected_id, (
            f"Expected row {index - 799} user_id to be {expected_id!r}, got {actual[0]!r}."
        )
        actual_a = float(actual[1])
        actual_b = float(actual[2])
        assert math.isfinite(actual_a) and math.isclose(actual_a, expected_a, abs_tol=0.001), (
            f"Incorrect feature_a_norm for {expected_id}: expected ~{expected_a:.6f}, got {actual_a}."
        )
        assert math.isfinite(actual_b) and math.isclose(actual_b, expected_b, abs_tol=0.001), (
            f"Incorrect feature_b_norm for {expected_id}: expected ~{expected_b:.6f}, got {actual_b}."
        )


def test_experiment_log_json():
    assert os.path.exists(LOG_PATH), f"File {LOG_PATH} is missing."

    with open(LOG_PATH, "r") as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {LOG_PATH} is not valid JSON."

    _, expected_values = load_expected()
    assert isinstance(log_data, dict), f"File {LOG_PATH} must contain a JSON object."
    assert set(log_data) == set(expected_values), (
        f"JSON keys must exactly match {list(expected_values)}; got {list(log_data)}."
    )

    for key, expected in expected_values.items():
        assert key in log_data, f"Key '{key}' is missing from {LOG_PATH}."
        actual = float(log_data[key])
        assert math.isfinite(actual) and math.isclose(actual, expected, abs_tol=0.001), (
            f"Expected '{key}' to be ~{expected}, got {actual}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
