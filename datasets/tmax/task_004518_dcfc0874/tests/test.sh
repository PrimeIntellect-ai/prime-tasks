#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import math
import os
import re
import subprocess
import tempfile
import time

import pytest
import redis
import requests

SCRIPT_PATH = "/app/verify_throughput.py"
RESULT_PATH = "/home/user/throughput_result.txt"
API_URL = "http://127.0.0.1:8000/enqueue"


def wait_for_services():
    r = redis.Redis(host="localhost", port=6379, db=0)
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            r.ping()
            response = requests.get("http://127.0.0.1:8000", timeout=1)
            return r
        except (redis.RedisError, requests.RequestException):
            time.sleep(0.2)
    pytest.fail("Redis or the API is not running and accessible")


def clean_redis(r):
    # Let any already-popped task finish before establishing a clean baseline.
    time.sleep(0.2)
    r.flushdb()
    time.sleep(0.2)
    r.flushdb()


def start_monitor():
    output = tempfile.NamedTemporaryFile(prefix="redis-monitor-", delete=False)
    output.close()
    stream = open(output.name, "wb")
    proc = subprocess.Popen(
        ["stdbuf", "-oL", "redis-cli", "MONITOR"],
        stdout=stream,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.2)
    return proc, stream, output.name


def stop_monitor(proc, stream, path):
    time.sleep(0.25)
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)
    stream.close()
    with open(path, "r", errors="replace") as f:
        lines = f.readlines()
    os.unlink(path)
    return lines


def parsed_commands(lines):
    commands = []
    for line in lines:
        match = re.match(r"^(\d+(?:\.\d+)?)\s+.*?((?:\s+\"(?:[^\"\\]|\\.)*\")+)\s*$", line.strip())
        if not match:
            continue
        tokens = re.findall(r'\"((?:[^\"\\]|\\.)*)\"', match.group(2))
        if tokens:
            commands.append((float(match.group(1)), [t.lower() for t in tokens]))
    return commands


def commands_for_key(commands, key):
    key = key.lower()
    return [(ts, tokens) for ts, tokens in commands if key in tokens[1:]]


def test_verify_throughput_script():
    """The required artifact must exist and actually run a 500-request regression."""
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."

    r = wait_for_services()
    clean_redis(r)
    try:
        os.remove(RESULT_PATH)
    except FileNotFoundError:
        pass

    monitor, stream, monitor_path = start_monitor()
    started = time.time()
    try:
        completed = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/app",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("verify_throughput.py did not finish within 20 seconds")
    finally:
        lines = stop_monitor(monitor, stream, monitor_path)
    wall_elapsed = time.time() - started

    assert completed.returncode == 0, (
        "verify_throughput.py failed when executed:\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    commands = parsed_commands(lines)
    queue_commands = commands_for_key(commands, "task_queue")
    pushes = [(ts, tokens) for ts, tokens in queue_commands if tokens[0] in ("lpush", "rpush")]
    assert len(pushes) == 500, (
        "verify_throughput.py must enqueue exactly 500 tasks; "
        f"Redis observed {len(pushes)} queue pushes"
    )

    first_push = min(ts for ts, _ in pushes)
    count_commands = commands_for_key(commands, "processed_count")
    count_mutations_after_start = [
        (ts, tokens) for ts, tokens in count_commands
        if ts >= first_push and tokens[0] not in ("incr", "get")
    ]
    assert not count_mutations_after_start, (
        "processed_count was directly overwritten during the regression instead of "
        f"being incremented by task processing: {count_mutations_after_start[:3]}"
    )

    increments = [(ts, tokens) for ts, tokens in count_commands if ts >= first_push and tokens[0] == "incr"]
    assert len(increments) == 500, (
        "The executed regression did not cause 500 worker completions; "
        f"Redis observed {len(increments)} increments"
    )
    assert r.llen("task_queue") == 0, "verify_throughput.py returned before the queue drained"
    assert int(r.get("processed_count") or 0) == 500, "The executed regression did not process exactly 500 tasks"

    assert os.path.isfile(RESULT_PATH), f"Expected result file {RESULT_PATH} does not exist."
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    try:
        reported = float(content)
    except ValueError:
        pytest.fail(f"Content of {RESULT_PATH} is not a valid float: {content}")
    assert math.isfinite(reported) and reported > 0, "Reported throughput must be a finite positive float"

    observed_elapsed = max(ts for ts, _ in increments) - first_push
    assert observed_elapsed > 0
    observed_throughput = 500.0 / observed_elapsed
    assert observed_throughput * 0.20 <= reported <= observed_throughput * 1.25, (
        f"Reported throughput {reported:.2f} is inconsistent with the executed "
        f"500-task run ({observed_throughput:.2f} tasks/sec observed)"
    )
    assert reported <= 500.0 / max(wall_elapsed - 1.0, 0.001) * 1.5, (
        "Reported throughput is not plausible for the script's measured wall-clock run"
    )


def test_throughput_result_file():
    """Verify that the executed script saved a raw throughput float."""
    assert os.path.isfile(RESULT_PATH), f"Expected result file {RESULT_PATH} does not exist."
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"Content of {RESULT_PATH} is not a valid float: {content}")
    assert math.isfinite(val) and val > 0


def test_system_throughput():
    """Measure actual successful API requests and independently completed tasks."""
    r = wait_for_services()
    clean_redis(r)

    # A randomized baseline prevents a worker from passing by simply assigning 500.
    baseline = int.from_bytes(os.urandom(4), "big") + 1000
    r.set("processed_count", baseline)

    monitor, stream, monitor_path = start_monitor()
    start_time = time.time()

    def send_req(i):
        response = requests.post(
            API_URL,
            json={"id": i, "payload": f"verifier-{i}"},
            timeout=5,
        )
        response.raise_for_status()
        body = response.json()
        assert body.get("status") == "queued"
        return response.status_code

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=100) as executor:
            futures = [executor.submit(send_req, i) for i in range(500)]
            statuses = [future.result() for future in futures]

        deadline = start_time + 15
        while time.time() < deadline:
            processed = int(r.get("processed_count") or 0)
            if processed >= baseline + 500 and r.llen("task_queue") == 0:
                break
            time.sleep(0.05)
    finally:
        lines = stop_monitor(monitor, stream, monitor_path)

    assert len(statuses) == 500 and all(200 <= status < 300 for status in statuses), (
        "All 500 enqueue requests must complete successfully"
    )

    processed = int(r.get("processed_count") or 0)
    completed_count = processed - baseline
    assert completed_count == 500, (
        f"Worker only processed {completed_count}/500 tasks within the 15s timeout. "
        "Deadlock or severe bottleneck still present."
    )
    assert r.llen("task_queue") == 0, "The task queue did not drain"

    commands = parsed_commands(lines)
    queue_commands = commands_for_key(commands, "task_queue")
    pushes = [(ts, tokens) for ts, tokens in queue_commands if tokens[0] in ("lpush", "rpush")]
    assert len(pushes) == 500, f"Redis observed {len(pushes)}/500 successful queue insertions"

    count_commands = commands_for_key(commands, "processed_count")
    illegal_count_mutations = [
        tokens for _, tokens in count_commands if tokens[0] not in ("incr", "get")
    ]
    assert not illegal_count_mutations, (
        "processed_count was overwritten rather than advanced by worker completions: "
        f"{illegal_count_mutations[:3]}"
    )
    increments = [tokens for _, tokens in count_commands if tokens[0] == "incr"]
    assert len(increments) == 500, f"Redis observed {len(increments)}/500 worker completion increments"

    elapsed = time.time() - start_time
    throughput = 500 / elapsed
    threshold = 50.0
    assert throughput >= threshold, (
        f"Throughput was {throughput:.2f} req/sec, which is below the threshold "
        f"of {threshold} req/sec."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
