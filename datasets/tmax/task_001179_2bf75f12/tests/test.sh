#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import pytest

RAW_FILE = "/home/user/raw_metrics.csv"
SOURCE_FILE = "/home/user/process_metrics.cpp"
PROCESSED_FILE = "/home/user/processed.jsonl"
ANOMALIES_FILE = "/home/user/anomalies.jsonl"
EXECUTABLE_FILE = "/home/user/process_metrics"
EXPECTED_KEYS = {"ts", "hostname", "metric_name", "metric_value", "event_log"}


def build_expected():
    processed = []
    anomalies = []
    seen_keys = set()
    previous = {}

    with open(RAW_FILE, "r", newline="") as f:
        for row in csv.DictReader(f):
            ts = int(row["ts"])
            hostname = row["hostname"]
            event_log = row["event_log"]

            for metric_name in ("cpu", "mem", "disk"):
                dedup_key = f"{ts}_{hostname}_{metric_name}"
                if dedup_key in seen_keys:
                    continue
                seen_keys.add(dedup_key)

                metric_value = float(row[metric_name])
                record = {
                    "ts": ts,
                    "hostname": hostname,
                    "metric_name": metric_name,
                    "metric_value": metric_value,
                    "event_log": event_log,
                }
                processed.append(record)

                series_key = (hostname, metric_name)
                if series_key in previous and metric_value > 3.0 * previous[series_key]:
                    anomalies.append(record.copy())
                previous[series_key] = metric_value

    return processed, anomalies


EXPECTED_PROCESSED, EXPECTED_ANOMALIES = build_expected()


def load_jsonl(path):
    assert os.path.exists(path), f"Output file missing: {path}"
    records = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError as e:
                    pytest.fail(f"Invalid JSON in {path}: {e}")
    return records


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_run_submission():
    assert os.path.isfile(SOURCE_FILE), f"C++ source not found at {SOURCE_FILE}"
    assert os.path.exists(EXECUTABLE_FILE), f"Executable not found at {EXECUTABLE_FILE}"
    assert os.path.isfile(EXECUTABLE_FILE), f"Executable path is not a regular file: {EXECUTABLE_FILE}"
    assert os.access(EXECUTABLE_FILE, os.X_OK), f"File {EXECUTABLE_FILE} is not executable"
    with open(EXECUTABLE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_FILE} is not a compiled executable"

    rebuilt = "/tmp/process_metrics_rebuilt"
    compile_result = subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE_FILE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, f"Failed to compile process_metrics.cpp:\n{compile_result.stderr}"
    os.replace(rebuilt, EXECUTABLE_FILE)

    for path in (PROCESSED_FILE, ANOMALIES_FILE):
        if os.path.exists(path):
            os.remove(path)

    run_result = subprocess.run(
        [EXECUTABLE_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, (
        f"process_metrics exited with {run_result.returncode}\n"
        f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
    )


def test_executable_exists():
    assert os.path.exists(EXECUTABLE_FILE), f"Executable not found at {EXECUTABLE_FILE}"
    assert os.access(EXECUTABLE_FILE, os.X_OK), f"File {EXECUTABLE_FILE} is not executable"


def test_processed_jsonl_content():
    records = load_jsonl(PROCESSED_FILE)

    assert len(records) == 18, f"Expected exactly 18 processed records after deduplication, got {len(records)}"

    for i, rec in enumerate(records):
        assert set(rec.keys()) == EXPECTED_KEYS, f"Record {i} in processed.jsonl has incorrect keys: {rec.keys()}"
        assert isinstance(rec["ts"], int), f"Record {i} 'ts' must be an integer"
        assert isinstance(rec["hostname"], str), f"Record {i} 'hostname' must be a string"
        assert isinstance(rec["metric_name"], str), f"Record {i} 'metric_name' must be a string"
        assert isinstance(rec["metric_value"], (int, float)), f"Record {i} 'metric_value' must be a float"
        assert isinstance(rec["event_log"], str), f"Record {i} 'event_log' must be a string"

    ts_1700000060 = [r for r in records if r["ts"] == 1700000060]
    assert len(ts_1700000060) == 3, "Deduplication failed: expected exactly 3 records for ts=1700000060 (one for each metric)"

    spike_records = [r for r in records if r["ts"] == 1700000180 and r["hostname"] == "serverA"]
    assert len(spike_records) == 3, "Expected 3 records for serverA at ts=1700000180"
    for r in spike_records:
        assert r["event_log"] == "Spike detected\nHigh CPU load\nInvestigate immediately", \
            f"Embedded newlines not parsed correctly in event_log: {repr(r['event_log'])}"

    assert records == EXPECTED_PROCESSED, "processed.jsonl does not contain the complete expected records in input order"


def test_anomalies_jsonl_content():
    anomalies = load_jsonl(ANOMALIES_FILE)

    assert len(anomalies) == 4, f"Expected exactly 4 anomalies, got {len(anomalies)}"

    for i, rec in enumerate(anomalies):
        assert set(rec.keys()) == EXPECTED_KEYS, f"Anomaly record {i} has incorrect keys: {rec.keys()}"

    anom_tuples = [(a["hostname"], a["metric_name"], a["metric_value"]) for a in anomalies]
    assert ("serverA", "cpu", 45.0) in anom_tuples, "Missing anomaly: serverA cpu 45.0"
    assert ("serverA", "cpu", 140.0) in anom_tuples, "Missing anomaly: serverA cpu 140.0"
    assert ("serverA", "mem", 3200.0) in anom_tuples, "Missing anomaly: serverA mem 3200.0"
    assert ("serverA", "disk", 200.0) in anom_tuples, "Missing anomaly: serverA disk 200.0"

    assert anomalies == EXPECTED_ANOMALIES, "anomalies.jsonl does not contain exactly the anomalies implied by the processed sequence"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
