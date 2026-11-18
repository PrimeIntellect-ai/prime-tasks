#!/bin/bash
set -u
mkdir -p /logs/verifier

run_verification() {
    # Start a clean deployment using the artifact the agent was instructed to fix.
    redis-cli -p 6379 shutdown nosave >/dev/null 2>&1 || true
    pkill -f '[p]ython3 app.py' >/dev/null 2>&1 || true
    pkill -f '[p]ython3 worker.py' >/dev/null 2>&1 || true
    sleep 1

    test -x /app/start_services.sh || return 1
    /app/start_services.sh >/tmp/start_services.log 2>&1 || return 1

    local ready=0
    for _ in $(seq 1 40); do
        if redis-cli -p 6379 ping 2>/dev/null | grep -q PONG && curl -sS -o /dev/null http://127.0.0.1:8080/ 2>/dev/null; then
            ready=1
            break
        fi
        sleep 0.5
    done
    test "$ready" -eq 1 || return 1

    # Require the requested evaluation script to actually run and freshly produce its report.
    rm -f /home/user/evaluation_result.json
    timeout 120 python3 /app/evaluate.py >/tmp/evaluate.log 2>&1 || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import ctypes
import importlib.util
import json
import math
import os
import struct
import time
import uuid

import pytest
import redis
import requests


def test_evaluation_result_accuracy():
    result_file = '/home/user/evaluation_result.json'
    assert os.path.isfile(result_file), f"Evaluation result file {result_file} is missing. Did you run /app/evaluate.py?"

    with open(result_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {result_file} is not valid JSON.")

    assert "accuracy" in data, f"Key 'accuracy' is missing in {result_file}."
    accuracy = data["accuracy"]
    assert isinstance(accuracy, (int, float)), f"Accuracy must be a number, got {type(accuracy)}."

    threshold = 0.99
    assert accuracy >= threshold, f"Accuracy is {accuracy}, which is below the required threshold of {threshold}."


def test_math_core_compiled():
    so_file = '/app/ext/math_core.so'
    assert os.path.isfile(so_file), f"Compiled extension {so_file} is missing. Did you fix the Makefile and run make?"

    lib = ctypes.CDLL(so_file)
    fn = lib.process_math
    fn.argtypes = [ctypes.c_double]
    fn.restype = ctypes.c_double
    for value in (-3.25, 0.0, 1.75, 10.0):
        assert math.isclose(fn(value), math.sin(value) * math.cos(value), rel_tol=1e-12, abs_tol=1e-12)


def test_parser_honors_mixed_endian_length():
    spec = importlib.util.spec_from_file_location('submitted_parser', '/app/api/parser.py')
    parser = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(parser)

    short_payload = bytes(range(10))
    short_record = struct.pack('<I', 0xDEADBEEF) + struct.pack('<H', 10) + short_payload
    assert parser.parse_telemetry(short_record + b'extra') == short_payload

    long_payload = bytes(i % 256 for i in range(300))
    long_record = struct.pack('<I', 0xDEADBEEF) + struct.pack('>H', 300) + long_payload
    assert parser.parse_telemetry(long_record + b'extra') == long_payload


def test_live_pipeline_accuracy_on_10000_records():
    r = redis.Redis(host='127.0.0.1', port=6379, socket_timeout=5)
    assert r.ping()
    r.flushdb()

    run_id = uuid.uuid4().hex
    count = 10000
    jobs = []
    for i in range(count):
        length = 10 if i % 2 == 0 else 300
        payload = bytes(j % 256 for j in range(length))
        length_bytes = struct.pack('<H', length) if length <= 255 else struct.pack('>H', length)
        record = struct.pack('<I', 0xDEADBEEF) + length_bytes + payload
        job_id = f'{run_id}-{i}'
        jobs.append((job_id, length, record))

    def submit(job):
        job_id, _, record = job
        try:
            response = requests.post(
                'http://127.0.0.1:8080/process',
                data=record,
                headers={'X-Job-Id': job_id, 'Content-Type': 'application/octet-stream'},
                timeout=10,
            )
            return response.status_code == 200
        except requests.RequestException:
            return False

    with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
        accepted = sum(pool.map(submit, jobs))
    assert accepted >= 9900, f'Only {accepted}/{count} records were accepted by the API'

    pending = {job_id: length for job_id, length, _ in jobs}
    correct = 0
    deadline = time.time() + 120
    while pending and correct < 9900 and time.time() < deadline:
        ids = list(pending)
        for offset in range(0, len(ids), 1000):
            batch = ids[offset:offset + 1000]
            values = r.mget([f'result:{job_id}' for job_id in batch])
            for job_id, raw in zip(batch, values):
                if raw is None:
                    continue
                length = pending.pop(job_id)
                try:
                    actual = float(raw)
                    expected = math.sin(float(length)) * math.cos(float(length))
                    if math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9):
                        correct += 1
                except (TypeError, ValueError):
                    pass
        if correct < 9900:
            time.sleep(0.1)

    accuracy = correct / count
    assert accuracy >= 0.99, f'Independently measured live pipeline accuracy was {accuracy:.5f} ({correct}/{count})'
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
