#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

DETECTOR = "/home/user/detector.py"
ENDPOINT = "http://127.0.0.1:8080/ingest"


def send_payload(data):
    req = urllib.request.Request(ENDPOINT, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return None


def send_request(filepath):
    with open(filepath, "rb") as f:
        return send_payload(f.read())


def expected_exit(records):
    if len(records) < 3:
        feature_a = 0.0
    else:
        rolling = [
            sum(float(records[j]["latency"]) for j in range(i, i + 3)) / 3.0
            for i in range(len(records) - 2)
        ]
        feature_a = max(rolling)

    feature_b = sum(float(row["cpu_load"]) for row in records) / len(records)
    distance = math.hypot(feature_a - 50.0, feature_b - 0.4)
    return 1 if distance > 15.0 else 0


def run_detector(records):
    fd, path = tempfile.mkstemp(prefix="detector-input-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(records, f)
        result = subprocess.run(
            ["python3", DETECTOR, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        return result.returncode, result.stdout, result.stderr
    finally:
        if os.path.exists(path):
            os.unlink(path)


def make_records(latencies, cpu_loads):
    if not isinstance(cpu_loads, list):
        cpu_loads = [cpu_loads] * len(latencies)
    return [
        {
            "timestamp": 1700000000 + i * 5,
            "latency": latency,
            "cpu_load": cpu,
        }
        for i, (latency, cpu) in enumerate(zip(latencies, cpu_loads))
    ]


def test_detector_script_exists():
    assert os.path.isfile(DETECTOR), "The script /home/user/detector.py is missing."


def test_clean_corpus():
    clean_files = glob.glob("/app/data/clean/*.json")
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_clean = []
    for filepath in clean_files:
        status = send_request(filepath)
        if status != 200:
            failed_clean.append((os.path.basename(filepath), status))

    if failed_clean:
        details = ", ".join([f"{name} (HTTP {status})" for name, status in failed_clean])
        pytest.fail(f"{len(failed_clean)} of {len(clean_files)} clean files were modified/rejected or failed to process: {details}")


def test_evil_corpus():
    evil_files = glob.glob("/app/data/evil/*.json")
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_evil = []
    for filepath in evil_files:
        status = send_request(filepath)
        if status != 406:
            failed_evil.append((os.path.basename(filepath), status))

    if failed_evil:
        details = ", ".join([f"{name} (HTTP {status})" for name, status in failed_evil])
        pytest.fail(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed detection or failed to process: {details}")


def test_detector_algorithm_on_generated_inputs():
    cases = [
        make_records([999.0], 0.4),
        make_records([-500.0, 500.0], 0.4),
        make_records([100.0, 0.0, 50.0], 0.4),
        make_records([20.0, 20.0, 20.0, 80.0, 20.0], 0.4),
        make_records([30.0, 30.0, 30.0, 90.0, 30.0], 0.4),
        make_records([50.0, 50.0, 50.0, 80.0], 0.4),
        make_records([65.0, 65.0, 65.0], 0.4),
        make_records([65.001, 65.001, 65.001], 0.4),
        make_records([35.0, 35.0, 35.0], 0.4),
        make_records([34.999, 34.999, 34.999], 0.4),
        make_records([50.0, 50.0, 50.0], [30.0, -29.2, 0.4]),
        make_records([50.0, 50.0, 50.0], 16.0),
    ]

    rng = random.SystemRandom()
    for _ in range(16):
        count = rng.randint(1, 9)
        records = []
        for i in range(count):
            records.append({
                "timestamp": 1800000000 + i * rng.randint(1, 12),
                "latency": round(rng.uniform(-10.0, 110.0), 6),
                "cpu_load": round(rng.uniform(-2.0, 20.0), 6),
            })
        cases.append(records)

    expectations = [expected_exit(records) for records in cases]
    assert 0 in expectations and 1 in expectations

    for index, (records, expected) in enumerate(zip(cases, expectations)):
        actual, stdout, stderr = run_detector(records)
        assert actual == expected, (
            f"Generated case {index} returned {actual}, expected {expected}. "
            f"stdout={stdout!r}, stderr={stderr!r}, records={records!r}"
        )


def test_generated_inputs_through_nginx_pipeline():
    rng = random.SystemRandom()
    cases = [
        make_records([rng.uniform(47.0, 53.0)] * 3, 0.4),
        make_records([rng.uniform(72.0, 88.0)] * 3, 0.4),
        make_records([100.0, 0.0, 50.0, 49.0], [0.2, 0.4, 0.6, 0.4]),
        make_records([50.0, 50.0, 50.0], rng.uniform(16.0, 25.0)),
        make_records([rng.uniform(-1000.0, 1000.0)], 0.4),
    ]

    for index, records in enumerate(cases):
        expected_status = 406 if expected_exit(records) == 1 else 200
        payload = json.dumps(records).encode("utf-8")
        status = send_payload(payload)
        assert status == expected_status, (
            f"Pipeline case {index} returned HTTP {status}, expected {expected_status}; "
            f"records={records!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
