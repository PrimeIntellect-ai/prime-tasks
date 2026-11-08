#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import pytest

BASE = "/home/user/oncall"
AGGREGATOR_PATH = os.path.join(BASE, "aggregator.py")
FRONTEND_PATH = os.path.join(BASE, "frontend.log")
BACKEND_PATH = os.path.join(BASE, "backend.log")
OUTPUT_PATH = os.path.join(BASE, "fixed_anomalies.jsonl")


def read_jsonl(path):
    with open(path, "r") as f:
        raw = f.read().strip()
    lines = raw.split("\n")
    data = []
    for i, line in enumerate(lines):
        try:
            data.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {path} is not valid JSON: {line}")
    return lines, data


def expected_original_inputs():
    rng = random.Random(42)
    frontend = {}
    backend = {}
    for i in range(100):
        req_id = f"req_{i:04d}"
        ts_front = 1600000000 + i * 5
        ts_back = ts_front + rng.randint(1, 3)
        proc_time = rng.randint(150, 185)
        frontend[req_id] = {"ts": ts_front, "req_id": req_id, "endpoint": "/pay"}
        backend[req_id] = {"ts": ts_back, "req_id": req_id, "proc_time_ms": proc_time}
    return frontend, backend


def verify_original_logs_unchanged():
    expected_frontend, expected_backend = expected_original_inputs()
    front_lines, front = read_jsonl(FRONTEND_PATH)
    back_lines, back = read_jsonl(BACKEND_PATH)
    assert len(front_lines) == 100 and len(front) == 100, "frontend.log was modified."
    assert len(back_lines) == 100 and len(back) == 100, "backend.log was modified."
    assert {r.get("req_id"): r for r in front} == expected_frontend, "frontend.log was modified."
    assert {r.get("req_id"): r for r in back} == expected_backend, "backend.log was modified."
    return expected_frontend, expected_backend


def expected_merged(frontend, backend):
    records = []
    for req_id, front in frontend.items():
        if req_id in backend:
            record = dict(front)
            record["proc_time_ms"] = backend[req_id]["proc_time_ms"]
            records.append(record)
    records.sort(key=lambda r: r["ts"])
    return records


def verify_output_data(data, expected):
    assert len(data) == len(expected), f"Output must contain exactly {len(expected)} lines, found {len(data)}."
    window_size = 10
    for i, record in enumerate(data):
        assert "rolling_avg" in record, f"Record at index {i} is missing 'rolling_avg' key."
        assert "proc_time_ms" in record, f"Record at index {i} is missing 'proc_time_ms' key."

        exp = expected[i]
        assert record.get("req_id") == exp["req_id"], f"Wrong request or timeline order at index {i}."
        assert record.get("ts") == exp["ts"], f"Wrong frontend timestamp at index {i}."
        assert record.get("endpoint") == exp["endpoint"], f"Wrong endpoint at index {i}."
        assert record["proc_time_ms"] == exp["proc_time_ms"], f"Wrong processing time at index {i}."

        start_idx = max(0, i - window_size + 1)
        window = expected[start_idx:i + 1]
        expected_avg = sum(req["proc_time_ms"] for req in window) / len(window)
        actual_avg = record["rolling_avg"]
        assert isinstance(actual_avg, (int, float)) and not isinstance(actual_avg, bool), f"Invalid rolling average at index {i}."
        assert abs(expected_avg - actual_avg) < 1e-5, (
            f"Rolling average calculation is incorrect at index {i}. "
            f"Window slice: [{start_idx}:{i+1}], Elements: {len(window)}. "
            f"Expected {expected_avg}, got {actual_avg}."
        )
        assert actual_avg <= 200, f"Found an anomaly > 200 at index {i} after fixing."


def run_aggregator(frontend_path, backend_path):
    assert os.path.isfile(AGGREGATOR_PATH), f"Aggregator {AGGREGATOR_PATH} is missing."
    try:
        result = subprocess.run(
            ["python3", AGGREGATOR_PATH, frontend_path, backend_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("aggregator.py timed out.")
    assert result.returncode == 0, f"aggregator.py failed with exit code {result.returncode}: {result.stderr}"
    lines = result.stdout.strip().split("\n")
    data = []
    for i, line in enumerate(lines):
        try:
            data.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Fresh aggregator output line {i+1} is not valid JSON: {line}")
    return lines, data


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing. Did you run the aggregator script and redirect output?"


def test_output_file_content_and_logic_and_fresh_execution():
    frontend, backend = verify_original_logs_unchanged()
    expected = expected_merged(frontend, backend)

    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    lines, data = read_jsonl(OUTPUT_PATH)
    assert len(lines) == 100, f"Output must contain exactly 100 lines, found {len(lines)}."
    verify_output_data(data, expected)

    with open(FRONTEND_PATH, "rb") as f:
        frontend_before = f.read()
    with open(BACKEND_PATH, "rb") as f:
        backend_before = f.read()

    fresh_lines, fresh_data = run_aggregator(FRONTEND_PATH, BACKEND_PATH)
    assert len(fresh_lines) == 100, f"Fresh aggregator run must output exactly 100 lines, found {len(fresh_lines)}."
    verify_output_data(fresh_data, expected)

    with open(FRONTEND_PATH, "rb") as f:
        assert f.read() == frontend_before, "aggregator.py modified frontend.log."
    with open(BACKEND_PATH, "rb") as f:
        assert f.read() == backend_before, "aggregator.py modified backend.log."


def test_aggregator_on_independent_boundary_case():
    frontend_records = [
        {"ts": 5000 + i * 7, "req_id": f"case_{i:02d}", "endpoint": "/pay"}
        for i in range(14)
    ]
    proc_times = [181, 152, 177, 163, 169, 155, 184, 160, 173, 158, 166, 179, 151, 175]
    backend_records = [
        {"ts": 5002 + i * 7, "req_id": f"case_{i:02d}", "proc_time_ms": proc_times[i]}
        for i in range(14)
    ]
    front_map = {r["req_id"]: r for r in frontend_records}
    back_map = {r["req_id"]: r for r in backend_records}
    expected = expected_merged(front_map, back_map)

    with tempfile.TemporaryDirectory() as tmp:
        front_path = os.path.join(tmp, "frontend.log")
        back_path = os.path.join(tmp, "backend.log")
        with open(front_path, "w") as f:
            for record in reversed(frontend_records):
                f.write(json.dumps(record) + "\n")
        with open(back_path, "w") as f:
            for record in backend_records[::2] + backend_records[1::2]:
                f.write(json.dumps(record) + "\n")

        lines, data = run_aggregator(front_path, back_path)
        assert len(lines) == 14, f"Independent run must output exactly 14 lines, found {len(lines)}."
        verify_output_data(data, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
