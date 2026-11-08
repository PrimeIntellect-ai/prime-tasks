#!/bin/bash
mkdir -p /logs/verifier

cleanup() {
    if [ -n "${INGEST_PID:-}" ]; then kill "$INGEST_PID" 2>/dev/null || true; fi
    if [ -n "${WORKER_PID:-}" ]; then kill "$WORKER_PID" 2>/dev/null || true; fi
    pkill -f '/app/ingest_service.py' 2>/dev/null || true
    pkill -f '/app/worker_service.py' 2>/dev/null || true
}
trap cleanup EXIT

redis-cli shutdown nosave >/dev/null 2>&1 || true
pkill -f '/app/ingest_service.py' 2>/dev/null || true
pkill -f '/app/worker_service.py' 2>/dev/null || true
if command -v fuser >/dev/null 2>&1; then
    fuser -k 8000/tcp >/dev/null 2>&1 || true
fi
sleep 1

status=0
[ -f /app/ingest_service.py ] || status=1
[ -f /app/worker_service.py ] || status=1
[ -f /app/test_flow.py ] || status=1
python3 -m py_compile /app/ingest_service.py /app/worker_service.py /app/test_flow.py || status=1
redis-server --daemonize yes || status=1

if [ "$status" -eq 0 ]; then
    python3 /app/ingest_service.py >/tmp/ingest_service.log 2>&1 &
    INGEST_PID=$!
    python3 /app/worker_service.py >/tmp/worker_service.log 2>&1 &
    WORKER_PID=$!
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import os
import socket
import subprocess
import time
from decimal import Decimal

import redis


def wait_for_services(r):
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        try:
            assert r.ping()
            with socket.create_connection(("127.0.0.1", 8000), timeout=1):
                pass
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    assert False, f"Redis or the ingest service did not become ready: {last_error}"


def send_payload(index):
    payload = {"id": f"legacy-€-{index}" if index % 10 == 0 else str(index), "delta": 1e-12}
    encoding = "windows-1252" if index % 10 == 0 else "utf-8"
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode(encoding)
    last_error = None
    for _ in range(5):
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=3) as sock:
                sock.sendall(data)
            return
        except OSError as exc:
            last_error = exc
            time.sleep(0.05)
    raise AssertionError(f"Could not send telemetry payload {index}: {last_error}")


def wait_for_count(r, expected, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        count = int(r.get("processed_count") or 0)
        if count >= expected:
            return count
        time.sleep(0.1)
    return int(r.get("processed_count") or 0)


def test_repaired_pipeline_and_final_result_accuracy():
    r = redis.Redis(host="localhost", port=6379, db=0)
    wait_for_services(r)

    # Exercise actual Windows-1252 fallback, concurrent updates, and deltas too
    # small to survive ordinary binary-float addition to this starting value.
    request_count = 800
    initial = Decimal("1000000000000")
    delta = Decimal("0.000000000001")
    r.flushall()
    r.set("global_accumulator", str(initial))
    r.set("processed_count", "0")

    with concurrent.futures.ThreadPoolExecutor(max_workers=100) as pool:
        list(pool.map(send_payload, range(request_count)))

    count = wait_for_count(r, request_count)
    assert count == request_count, f"Only {count} of {request_count} validation payloads were processed"
    assert r.llen("sensor_queue") == 0, "Validation telemetry remains unprocessed"
    actual_precise = Decimal(r.get("global_accumulator").decode("utf-8"))
    expected_precise = initial + delta * request_count
    assert actual_precise == expected_precise, (
        f"Precision/concurrency validation produced {actual_precise}, expected {expected_precise}"
    )

    # Run the integration artifact required by the instruction against the
    # submitted services, rather than trusting a pre-created result file.
    result_path = "/home/user/final_result.txt"
    try:
        os.remove(result_path)
    except FileNotFoundError:
        pass
    started_ns = time.time_ns()
    completed = subprocess.run(
        ["python3", "/app/test_flow.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    assert completed.returncode == 0, f"test_flow.py failed:\n{completed.stdout}"
    assert os.path.isfile(result_path), f"Result file {result_path} not found. Did you run the test_flow.py script?"
    assert os.stat(result_path).st_mtime_ns >= started_ns, "The result file was not freshly produced by test_flow.py"
    final_count = int(r.get("processed_count") or 0)
    assert final_count == 15000, f"Only {final_count} of 15000 integration payloads were processed"
    assert r.llen("sensor_queue") == 0, "Integration telemetry remains unprocessed"

    with open(result_path, "r") as f:
        content = f.read().strip()

    try:
        actual = Decimal(content)
    except Exception as e:
        assert False, f"Could not parse the content of {result_path} ('{content}') as a Decimal: {e}"

    expected = Decimal("42000.0")
    error = abs(actual - expected)
    threshold = Decimal("1e-8")

    assert error <= threshold, (
        f"Absolute error {error} exceeds the maximum allowed threshold of {threshold}. "
        f"Actual value: {actual}, Expected value: {expected}. "
        "Check your concurrency logic and floating-point precision handling."
    )
TEST_EOF

if [ "$status" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
