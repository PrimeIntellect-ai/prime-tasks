#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import math
import os
import runpy
import shutil
import subprocess
import tempfile

import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.linear_model import LogisticRegression, Ridge
from sklearn.metrics import accuracy_score, mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

HOME = "/home/user"
RAW = f"{HOME}/raw_data.csv"
PROCESSED = f"{HOME}/processed_data.csv"
EXPERIMENTS = f"{HOME}/experiments.jsonl"


def run_checked(command, timeout=120):
    result = subprocess.run(
        command,
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Command failed: {command}\n{result.stdout}"
    return result


def expected_etl(raw):
    result = raw.dropna(subset=["temperature"]).copy()
    result["vibration"] = result["vibration"].fillna(result["vibration"].median())
    features = ["temperature", "vibration", "pressure"]
    result.loc[:, features] = StandardScaler().fit_transform(result[features])
    return result.reset_index(drop=True)


def expected_metrics(processed):
    features = processed[["temperature", "vibration", "pressure"]]

    x_train, x_test, y_train, y_test = train_test_split(
        features, processed["status"], test_size=0.2, random_state=42
    )
    classifier = LogisticRegression(random_state=42)
    classifier.fit(x_train, y_train)
    accuracy = round(float(accuracy_score(y_test, classifier.predict(x_test))), 4)

    x_train, x_test, y_train, y_test = train_test_split(
        features, processed["remaining_life"], test_size=0.2, random_state=42
    )
    regressor = Ridge(alpha=1.0, random_state=42)
    regressor.fit(x_train, y_train)
    mse = round(float(mean_squared_error(y_test, regressor.predict(x_test))), 4)
    return accuracy, mse


def read_jsonl(path):
    entries = []
    with open(path, "r") as handle:
        for line in handle:
            if line.strip():
                entries.append(json.loads(line))
    return entries


def assert_processed_matches(raw):
    assert os.path.isfile(PROCESSED), "processed_data.csv was not produced"
    actual = pd.read_csv(PROCESSED)
    expected = expected_etl(raw)
    assert list(actual.columns) == list(expected.columns), "Processed CSV columns or order are incorrect"
    assert_frame_equal(
        actual.reset_index(drop=True),
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-9,
        atol=1e-9,
    )
    return actual


def assert_two_metrics(entries, processed):
    assert len(entries) == 2, f"Training must append exactly two entries; got {len(entries)}"
    accuracy, mse = expected_metrics(processed)
    expected = {
        ("LogisticRegression", "status", "accuracy"): accuracy,
        ("Ridge", "remaining_life", "mse"): mse,
    }
    seen = {}
    for entry in entries:
        assert set(entry) == {"model_type", "target", "metric_name", "metric_value"}
        key = (entry["model_type"], entry["target"], entry["metric_name"])
        assert key in expected, f"Unexpected experiment entry: {entry}"
        assert key not in seen, f"Duplicate experiment entry: {key}"
        value = entry["metric_value"]
        assert isinstance(value, (int, float)) and not isinstance(value, bool)
        assert math.isfinite(float(value))
        assert float(value) == expected[key], f"Wrong metric for {key}: expected {expected[key]}, got {value}"
        seen[key] = value
    assert set(seen) == set(expected)


def test_scripts_and_makefile_exist():
    """Verify that the required scripts and Makefile exist."""
    for filename in ["etl.py", "train.py", "Makefile"]:
        path = f"/home/user/{filename}"
        assert os.path.exists(path), f"Required file {path} is missing."
        assert os.path.isfile(path), f"{path} is not a regular file."


def test_raw_data_was_not_replaced():
    np.random.seed(100)
    n_samples = 1000
    data = {
        "sensor_id": np.random.randint(1, 10, n_samples),
        "temperature": np.random.normal(50, 10, n_samples),
        "vibration": np.random.normal(5, 2, n_samples),
        "pressure": np.random.normal(100, 15, n_samples),
    }
    data["status"] = (data["temperature"] > 55).astype(int)
    data["remaining_life"] = 1000 - (
        data["temperature"] * 5
        + data["vibration"] * 10
        + np.random.normal(0, 20, n_samples)
    )
    expected = pd.DataFrame(data)
    expected.loc[np.random.choice(expected.index, 50, replace=False), "temperature"] = np.nan
    expected.loc[np.random.choice(expected.index, 100, replace=False), "vibration"] = np.nan

    # Apply the same CSV round trip used by setup before comparing.
    buffer = io.StringIO()
    expected.to_csv(buffer, index=False)
    buffer.seek(0)
    expected = pd.read_csv(buffer)
    actual = pd.read_csv(RAW)
    assert_frame_equal(actual, expected, check_dtype=False, check_exact=False, rtol=1e-12, atol=1e-12)


def test_scripts_and_makefile_execute_correctly():
    with open(RAW, "rb") as handle:
        original_raw = handle.read()

    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "big"))
    count = 180
    temperature = rng.normal(50, 11, count)
    vibration = rng.normal(5, 2.5, count)
    pressure = rng.normal(100, 17, count)
    challenge = pd.DataFrame({
        "sensor_id": rng.integers(1, 30, count),
        "temperature": temperature,
        "vibration": vibration,
        "pressure": pressure,
        "status": (temperature + 0.15 * pressure > 69).astype(int),
        "remaining_life": 1100 - 4.5 * temperature - 8 * vibration + rng.normal(0, 12, count),
    })
    challenge.loc[rng.choice(count, 17, replace=False), "temperature"] = np.nan
    challenge.loc[rng.choice(count, 31, replace=False), "vibration"] = np.nan

    try:
        challenge.to_csv(RAW, index=False)
        for path in (PROCESSED, EXPERIMENTS):
            if os.path.lexists(path):
                os.remove(path)

        run_checked(["python3", f"{HOME}/etl.py"])
        processed = assert_processed_matches(pd.read_csv(RAW))

        sentinel = {"sentinel": "preexisting"}
        with open(EXPERIMENTS, "w") as handle:
            handle.write(json.dumps(sentinel) + "\n")
        run_checked(["python3", f"{HOME}/train.py"])
        entries = read_jsonl(EXPERIMENTS)
        assert len(entries) == 3, "One train.py run must append exactly two JSON lines"
        assert entries[0] == sentinel, "train.py must append rather than overwrite existing experiments"
        assert_two_metrics(entries[1:], processed)
    finally:
        with open(RAW, "wb") as handle:
            handle.write(original_raw)

    # Instrument the submitted scripts to prove that `make all` invokes etl.py
    # followed by train.py, rather than merely containing target-shaped text.
    script_paths = [f"{HOME}/etl.py", f"{HOME}/train.py"]
    backups = []
    trace_fd, trace_path = tempfile.mkstemp(prefix="pipeline-trace-")
    os.close(trace_fd)
    os.remove(trace_path)
    try:
        for script_path, label in zip(script_paths, ("etl", "train")):
            fd, backup = tempfile.mkstemp(prefix=f"original-{label}-", suffix=".py")
            os.close(fd)
            shutil.copyfile(script_path, backup)
            backups.append((script_path, backup, os.stat(script_path).st_mode))
            wrapper = (
                "#!/usr/bin/env python3\n"
                "import runpy\n"
                f"with open({trace_path!r}, 'a') as f: f.write({label!r} + '\\n')\n"
                f"runpy.run_path({backup!r}, run_name='__main__')\n"
            )
            with open(script_path, "w") as handle:
                handle.write(wrapper)
            os.chmod(script_path, os.stat(backup).st_mode)

        for path in (PROCESSED, EXPERIMENTS):
            if os.path.lexists(path):
                os.remove(path)
        run_checked(["make", "-B", "all"])
        with open(trace_path, "r") as handle:
            trace = handle.read().splitlines()
        assert trace == ["etl", "train"], f"make all must run etl.py then train.py; observed {trace}"
    finally:
        for script_path, backup, mode in backups:
            shutil.copyfile(backup, script_path)
            os.chmod(script_path, mode)
            os.remove(backup)
        if os.path.exists(trace_path):
            os.remove(trace_path)

    # Run the real, restored pipeline through the submitted Makefile and verify
    # the final artifacts against independently recomputed results.
    for path in (PROCESSED, EXPERIMENTS):
        if os.path.lexists(path):
            os.remove(path)
    run_checked(["make", "-B", "all"])
    raw = pd.read_csv(RAW)
    processed = assert_processed_matches(raw)
    assert_two_metrics(read_jsonl(EXPERIMENTS), processed)


def test_processed_data_exists_and_structure():
    """Verify that processed_data.csv exists and has the correct columns and no missing values."""
    processed_path = "/home/user/processed_data.csv"
    assert os.path.exists(processed_path), f"File {processed_path} is missing."

    expected_columns = {"sensor_id", "temperature", "vibration", "pressure", "status", "remaining_life"}

    with open(processed_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None, f"{processed_path} has no header."
        actual_columns = set(reader.fieldnames)
        missing_columns = expected_columns - actual_columns
        assert not missing_columns, f"Processed data is missing columns: {missing_columns}"

        for row_idx, row in enumerate(reader, start=2):
            for col in expected_columns:
                val = row[col].strip()
                assert val != "", f"Missing value found in row {row_idx}, column {col}."
                try:
                    float(val)
                except ValueError:
                    pytest.fail(f"Non-numeric value '{val}' found in row {row_idx}, column {col}.")


def test_experiments_jsonl_structure():
    """Verify that experiments.jsonl exists and contains the correct JSON structure."""
    jsonl_path = "/home/user/experiments.jsonl"
    assert os.path.exists(jsonl_path), f"File {jsonl_path} is missing."

    lines = []
    with open(jsonl_path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                lines.append(json.loads(line))

    assert len(lines) >= 2, f"Expected at least 2 JSON lines in {jsonl_path}, found {len(lines)}."
    cls_result = None
    reg_result = None
    for entry in lines:
        if entry.get("model_type") == "LogisticRegression" and entry.get("target") == "status":
            cls_result = entry
        elif entry.get("model_type") == "Ridge" and entry.get("target") == "remaining_life":
            reg_result = entry

    assert cls_result is not None, "Missing LogisticRegression result for 'status' in experiments.jsonl."
    assert reg_result is not None, "Missing Ridge result for 'remaining_life' in experiments.jsonl."
    assert cls_result.get("metric_name") == "accuracy", f"Expected metric_name 'accuracy', got {cls_result.get('metric_name')}"
    assert isinstance(cls_result.get("metric_value"), (int, float)), "Classification metric_value must be a number."
    assert reg_result.get("metric_name") == "mse", f"Expected metric_name 'mse', got {reg_result.get('metric_name')}"
    assert isinstance(reg_result.get("metric_value"), (int, float)), "Regression metric_value must be a number."


def test_makefile_targets():
    """Verify that the Makefile contains the required targets."""
    makefile_path = "/home/user/Makefile"
    with open(makefile_path, "r") as f:
        content = f.read()

    assert "etl:" in content, "Makefile is missing 'etl' target."
    assert "train:" in content, "Makefile is missing 'train' target."
    assert "all:" in content, "Makefile is missing 'all' target."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
