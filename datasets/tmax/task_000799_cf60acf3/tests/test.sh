#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import time
import shutil
import hashlib
import subprocess
import tempfile
from collections import Counter, defaultdict
import pytest

RAW_DIR = "/home/user/raw_sensors"
PROCESSED_DIR = "/home/user/processed"
SCRIPTS_DIR = "/home/user/scripts"
SUMMARY_FILE = "/home/user/summary.json"
PROCESS_SCRIPT = os.path.join(SCRIPTS_DIR, "process_sensor.py")
RUN_SCRIPT = os.path.join(SCRIPTS_DIR, "run_pipeline.sh")
EXPECTED_HEADER = ["timestamp", "sensor", "metric", "value"]


def raw_hashes():
    result = {}
    for name in sorted(os.listdir(RAW_DIR)):
        path = os.path.join(RAW_DIR, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                result[name] = hashlib.sha256(f.read()).hexdigest()
    return result


def expected_rows_for_raw(path):
    long_data = []
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = row["timestamp"]
            for col, val in row.items():
                if col == "timestamp":
                    continue
                sensor, metric = col.split("_", 1)
                long_data.append((ts, sensor, metric, float(val)))

    groups = defaultdict(list)
    for item in long_data:
        groups[item[2]].append(item)

    result = []
    for metric, items in groups.items():
        items.sort(key=lambda item: item[0])
        result.extend(items[:math.ceil(len(items) / 2)])
    return result


def read_processed(path):
    with open(path, newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"Processed file {path} is empty.")
        assert header == EXPECTED_HEADER, f"Header in {path} is incorrect. Expected {EXPECTED_HEADER}, got {header}"
        rows = []
        for row in reader:
            assert len(row) == 4, f"Malformed processed row in {path}: {row}"
            try:
                value = float(row[3])
            except ValueError:
                pytest.fail(f"Non-numeric value in {path}: {row[3]}")
            rows.append((row[0], row[1], row[2], value))
        return rows


def assert_rows_match(path, expected):
    actual = read_processed(path)
    assert Counter(actual) == Counter(expected), f"Processed rows in {path} do not match the required reshaping and sampling"
    by_metric = defaultdict(list)
    for row in actual:
        by_metric[row[2]].append(row[0])
    for metric, timestamps in by_metric.items():
        assert timestamps == sorted(timestamps), f"Rows for metric {metric} in {path} are not timestamp-sorted"


def compute_expected_summary():
    all_values = defaultdict(list)
    if not os.path.exists(RAW_DIR):
        return {}
    for filename in os.listdir(RAW_DIR):
        if filename.endswith(".csv"):
            for _, _, metric, value in expected_rows_for_raw(os.path.join(RAW_DIR, filename)):
                all_values[metric].append(value)
    return {metric: round(sum(vals) / len(vals), 2) for metric, vals in all_values.items()}


def load_and_check_summary(expected):
    assert os.path.isfile(SUMMARY_FILE), f"File {SUMMARY_FILE} is missing."
    with open(SUMMARY_FILE) as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_FILE} does not contain valid JSON.")
    assert isinstance(actual, dict), "The summary.json should contain a JSON object."
    assert set(actual) == set(expected), f"summary.json keys differ: expected {set(expected)}, got {set(actual)}"
    for metric, expected_value in expected.items():
        value = actual[metric]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"Value for '{metric}' must be a number."
        assert math.isclose(value, expected_value, rel_tol=1e-5, abs_tol=1e-8), f"Value for '{metric}' is incorrect. Expected {expected_value}, got {value}"


def aggregate_command(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".py":
        return ["python3", path]
    if ext == ".sh":
        return ["bash", path]
    if ext == ".awk":
        files = sorted(os.path.join(PROCESSED_DIR, f) for f in os.listdir(PROCESSED_DIR) if f.endswith(".csv"))
        return ["awk", "-f", path] + files
    if ext == ".pl":
        return ["perl", path]
    if ext == ".rb":
        return ["ruby", path]
    if os.access(path, os.X_OK):
        return [path]
    return ["bash", path]


def test_scripts_exist():
    assert os.path.isdir(SCRIPTS_DIR), f"Directory {SCRIPTS_DIR} is missing."
    assert os.path.isfile(PROCESS_SCRIPT), f"File {PROCESS_SCRIPT} is missing."
    assert os.path.isfile(RUN_SCRIPT), f"File {RUN_SCRIPT} is missing."
    aggregate_scripts = [f for f in os.listdir(SCRIPTS_DIR) if f.startswith("aggregate.") and os.path.isfile(os.path.join(SCRIPTS_DIR, f))]
    assert aggregate_scripts, "No aggregate script found in /home/user/scripts/"


def test_process_sensor_executes_on_unseen_input():
    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "unseen.csv")
        output = os.path.join(td, "out.csv")
        with open(source, "w", newline="") as f:
            f.write("timestamp,s1_temp,s1_vib,s2_temp,s2_vib\n")
            f.write("2042-06-03T00:00:00,91.5,9.1,191.5,19.1\n")
            f.write("2042-06-01T00:00:00,71.25,7.25,171.25,17.25\n")
            f.write("2042-06-02T00:00:00,81.75,8.75,181.75,18.75\n")
        result = subprocess.run(["python3", PROCESS_SCRIPT, source, output], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        assert result.returncode == 0, f"process_sensor.py failed on an unseen input:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(output), "process_sensor.py did not create its requested output"
        assert_rows_match(output, expected_rows_for_raw(source))


def test_run_pipeline_really_dispatches_in_parallel_and_processes_all_files():
    before = raw_hashes()
    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "process_sensor.py")
        shutil.copy2(PROCESS_SCRIPT, backup)
        state = "/tmp/pipeline_parallel_state"
        lock = "/tmp/pipeline_parallel_lock"
        with open(state, "w") as f:
            f.write("0 0")
        probe = r'''#!/usr/bin/env python3
import csv, fcntl, os, sys, time
state = "/tmp/pipeline_parallel_state"
lockpath = "/tmp/pipeline_parallel_lock"
def update(delta):
    with open(lockpath, "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with open(state) as f:
            active, maximum = map(int, f.read().split())
        active += delta
        maximum = max(maximum, active)
        with open(state, "w") as f:
            f.write(f"{active} {maximum}")
        fcntl.flock(lock, fcntl.LOCK_UN)
update(1)
try:
    time.sleep(0.75)
    os.makedirs(os.path.dirname(sys.argv[2]), exist_ok=True)
    with open(sys.argv[2], "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["timestamp", "sensor", "metric", "value"])
        w.writerow(["2000-01-01T00:00:00", "probe", "probe", "1"])
finally:
    update(-1)
'''
        try:
            with open(PROCESS_SCRIPT, "w") as f:
                f.write(probe)
            os.chmod(PROCESS_SCRIPT, 0o755)
            shutil.rmtree(PROCESSED_DIR, ignore_errors=True)
            result = subprocess.run(["bash", RUN_SCRIPT], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            assert result.returncode == 0, f"run_pipeline.sh failed while dispatching processors:\n{result.stdout}\n{result.stderr}"
            with open(state) as f:
                active, maximum = map(int, f.read().split())
            assert active == 0
            assert maximum >= 2, "run_pipeline.sh did not run process_sensor.py concurrently"
        finally:
            shutil.copy2(backup, PROCESS_SCRIPT)

    shutil.rmtree(PROCESSED_DIR, ignore_errors=True)
    result = subprocess.run(["bash", RUN_SCRIPT], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, f"run_pipeline.sh failed with the real processor:\n{result.stdout}\n{result.stderr}"
    assert raw_hashes() == before, "The workflow modified files in raw_sensors"


def test_processed_files_exist_format_and_data():
    assert os.path.isdir(PROCESSED_DIR), f"Directory {PROCESSED_DIR} is missing."
    raw_files = [f for f in os.listdir(RAW_DIR) if f.endswith(".csv")]
    processed_files = [f for f in os.listdir(PROCESSED_DIR) if f.endswith(".csv")]
    assert set(raw_files) == set(processed_files), "Processed files do not match raw files."
    for filename in processed_files:
        assert_rows_match(os.path.join(PROCESSED_DIR, filename), expected_rows_for_raw(os.path.join(RAW_DIR, filename)))


def test_aggregate_script_executes_on_unseen_processed_data_and_final_data():
    aggregate_scripts = sorted(os.path.join(SCRIPTS_DIR, f) for f in os.listdir(SCRIPTS_DIR) if f.startswith("aggregate.") and os.path.isfile(os.path.join(SCRIPTS_DIR, f)))
    parent = tempfile.mkdtemp(prefix="aggregate-check-")
    saved = os.path.join(parent, "saved_processed")
    os.rename(PROCESSED_DIR, saved)
    os.makedirs(PROCESSED_DIR)
    hidden_expected = {"alpha": 4.0, "beta": 15.0, "gamma": 8.25}
    try:
        with open(os.path.join(PROCESSED_DIR, "secret_a.csv"), "w", newline="") as f:
            w = csv.writer(f); w.writerow(EXPECTED_HEADER)
            w.writerow(["2050-01-01", "x", "alpha", "1.25"])
            w.writerow(["2050-01-02", "y", "beta", "10"])
            w.writerow(["2050-01-03", "x", "alpha", "6.75"])
        with open(os.path.join(PROCESSED_DIR, "secret_b.csv"), "w", newline="") as f:
            w = csv.writer(f); w.writerow(EXPECTED_HEADER)
            w.writerow(["2050-02-01", "z", "beta", "20"])
            w.writerow(["2050-02-02", "z", "gamma", "8.25"])

        selected = None
        diagnostics = []
        for script in aggregate_scripts:
            try:
                if os.path.exists(SUMMARY_FILE):
                    os.remove(SUMMARY_FILE)
                result = subprocess.run(aggregate_command(script), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
                if result.returncode == 0:
                    try:
                        load_and_check_summary(hidden_expected)
                        selected = script
                        break
                    except AssertionError as exc:
                        diagnostics.append(f"{script}: {exc}")
                else:
                    diagnostics.append(f"{script}: exit {result.returncode}: {result.stderr}")
            except (OSError, subprocess.TimeoutExpired) as exc:
                diagnostics.append(f"{script}: {exc}")
        assert selected is not None, "No aggregate script correctly processed unseen files. " + " | ".join(diagnostics)
    finally:
        shutil.rmtree(PROCESSED_DIR, ignore_errors=True)
        os.rename(saved, PROCESSED_DIR)
        shutil.rmtree(parent, ignore_errors=True)

    if os.path.exists(SUMMARY_FILE):
        os.remove(SUMMARY_FILE)
    result = subprocess.run(aggregate_command(selected), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert result.returncode == 0, f"Aggregate script failed on pipeline output:\n{result.stdout}\n{result.stderr}"
    load_and_check_summary(compute_expected_summary())


def test_summary_json_content():
    load_and_check_summary(compute_expected_summary())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
