#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import subprocess

import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/clean_sensors.py"
JSON_PATH = "/home/user/anomalies.json"
LOG_PATH = "/home/user/pipeline.log"
REFERENCE_PATH = "/home/user/reference.csv"
SENSOR_DIR = "/home/user/sensor_data"


def run_pipeline():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_pipeline():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    for path in (JSON_PATH, LOG_PATH):
        if os.path.lexists(path):
            os.remove(path)
    run_pipeline()


def expected_results():
    reference = pd.read_csv(REFERENCE_PATH)["temperature"].to_numpy(dtype=float)
    expected = {}
    for i in range(1, 21):
        filename = f"machine_{i:02d}.csv"
        temperatures = pd.read_csv(os.path.join(SENSOR_DIR, filename))["temperature"]
        values = temperatures.to_numpy(dtype=float)
        distance = float(np.linalg.norm(values - reference))
        changepoint = bool(temperatures.rolling(window=50).std().max() > 2.5)
        expected[filename] = (distance, changepoint)
    return expected


def assert_outputs_match_inputs():
    expected = expected_results()
    expected_anomalies = sorted(
        filename
        for filename, (distance, changepoint) in expected.items()
        if distance > 100.0 or changepoint
    )

    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} does not exist."
    with open(JSON_PATH, "r") as f:
        anomalies = json.load(f)
    assert isinstance(anomalies, list), f"Expected a JSON list in {JSON_PATH}."
    assert anomalies == expected_anomalies, (
        f"Anomalies do not match computations from the CSV inputs. "
        f"Expected {expected_anomalies}, got {anomalies}."
    )

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        lines = f.read().splitlines()

    pattern = re.compile(
        r"^.+ - INFO - Processed (machine_\d{2}\.csv) - "
        r"Distance: (\d+\.\d{2}) - Changepoint: (True|False)$"
    )
    records = []
    for line in lines:
        match = pattern.match(line)
        if match:
            records.append((match.group(1), match.group(2), match.group(3)))

    assert len(records) == 20, (
        f"Expected exactly 20 correctly formatted INFO records, found {len(records)}."
    )
    assert len({record[0] for record in records}) == 20, (
        "Each of the 20 machine files must be logged exactly once."
    )

    for filename, distance_text, changepoint_text in records:
        assert filename in expected, f"Unexpected machine in log: {filename}"
        distance, changepoint = expected[filename]
        assert distance_text == f"{distance:.2f}", (
            f"Incorrect logged distance for {filename}: expected {distance:.2f}, "
            f"got {distance_text}."
        )
        assert changepoint_text == str(changepoint), (
            f"Incorrect logged changepoint for {filename}: expected {changepoint}, "
            f"got {changepoint_text}."
        )


def test_anomalies_json_exists_and_correct():
    json_path = "/home/user/anomalies.json"
    assert os.path.isfile(json_path), f"Output file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            anomalies = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    expected_anomalies = [
        "machine_03.csv",
        "machine_07.csv",
        "machine_08.csv",
        "machine_14.csv",
        "machine_19.csv"
    ]

    assert isinstance(anomalies, list), f"Expected a JSON list in {json_path}."
    assert anomalies == expected_anomalies, f"Anomalies list incorrect. Expected {expected_anomalies}, got {anomalies}."


def test_pipeline_log_exists_and_format():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) >= 20, f"Log file should have at least 20 lines, found {len(lines)}."

    pattern = re.compile(r".* - INFO - Processed machine_\d{2}\.csv - Distance: \d+\.\d{2} - Changepoint: (True|False)")

    matched_lines = [line for line in lines if pattern.match(line)]
    assert len(matched_lines) == 20, f"Expected exactly 20 log lines matching the required format, found {len(matched_lines)}."

    machines_logged = set()
    for line in matched_lines:
        match = re.search(r"Processed (machine_\d{2}\.csv)", line)
        if match:
            machines_logged.add(match.group(1))

    assert len(machines_logged) == 20, "Not all 20 machines were logged."


def test_script_uses_required_parallel_and_logging_modules():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    imported_roots = set()
    imported_bindings = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split(".")[0]
                imported_roots.add(root)
                imported_bindings[alias.asname or root] = alias.name
        elif isinstance(node, ast.ImportFrom) and node.module:
            root = node.module.split(".")[0]
            imported_roots.add(root)
            for alias in node.names:
                imported_bindings[alias.asname or alias.name] = f"{node.module}.{alias.name}"

    assert imported_roots.intersection({"multiprocessing", "concurrent"}), (
        "The script must import multiprocessing or concurrent.futures."
    )
    assert "logging" in imported_roots, "The script must use Python's logging module."

    parallel_constructors = {
        "Pool", "ThreadPool", "Process", "ProcessPoolExecutor", "ThreadPoolExecutor"
    }
    parallel_call_found = False
    logging_config_found = False
    logging_emit_found = False

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            called_name = node.func.id
            resolved = imported_bindings.get(called_name, called_name)
            terminal_name = resolved.rsplit(".", 1)[-1]
        elif isinstance(node.func, ast.Attribute):
            terminal_name = node.func.attr
        else:
            continue

        if terminal_name in parallel_constructors:
            parallel_call_found = True
        if terminal_name in {"basicConfig", "fileConfig", "dictConfig", "FileHandler"}:
            logging_config_found = True
        if terminal_name in {"info", "log"}:
            logging_emit_found = True

    assert parallel_call_found, (
        "The script must construct a multiprocessing worker/pool or a concurrent.futures executor."
    )
    assert logging_config_found, "The script must configure file-based pipeline logging."
    assert logging_emit_found, "The script must emit INFO-level processing records."


def test_computed_log_values_match_original_inputs():
    assert_outputs_match_inputs()


def test_pipeline_on_independently_changed_sensor_inputs():
    sensor_paths = [
        os.path.join(SENSOR_DIR, f"machine_{i:02d}.csv") for i in range(1, 21)
    ]
    backups = {}
    for path in sensor_paths:
        with open(path, "rb") as f:
            backups[path] = f.read()

    try:
        reference_df = pd.read_csv(REFERENCE_PATH)
        reference = reference_df["temperature"].to_numpy(dtype=float)
        x = np.arange(len(reference), dtype=float)

        for i, path in enumerate(sensor_paths, start=1):
            temperatures = reference + 0.1 * np.sin(x / (7.0 + i))
            if i == 2:
                temperatures = temperatures + 4.0
            elif i == 3:
                temperatures = temperatures.copy()
                temperatures[400:450] += np.where(np.arange(50) % 2 == 0, 3.5, -3.5)
            elif i == 5:
                temperatures = temperatures + 3.3

            pd.DataFrame({
                "timestamp": reference_df["timestamp"].to_numpy(),
                "temperature": temperatures,
            }).to_csv(path, index=False)

        for path in (JSON_PATH, LOG_PATH):
            if os.path.lexists(path):
                os.remove(path)

        run_pipeline()
        assert_outputs_match_inputs()
    finally:
        for path, contents in backups.items():
            with open(path, "wb") as f:
                f.write(contents)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
