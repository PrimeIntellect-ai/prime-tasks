#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import signal
import string
import subprocess
import time
import urllib.error
import urllib.request

import pytest

API_URL = "http://127.0.0.1:3000/compute"
ORACLE = "/app/oracle/reference_worker.py"
WORKER = "/app/worker/math_worker"


def oracle_value(value):
    result = subprocess.run(
        ["python3", ORACLE, value],
        capture_output=True,
        text=True,
        check=True,
        timeout=2,
    )
    return result.stdout.strip()


def post_compute(value, timeout=5):
    data = json.dumps({"input": value}).encode("utf-8")
    request = urllib.request.Request(
        API_URL, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        return body, json.loads(body)


def contains_exact_result(value, expected):
    if isinstance(value, bool):
        return False
    if isinstance(value, (str, int)):
        return str(value) == expected
    if isinstance(value, list):
        return any(contains_exact_result(item, expected) for item in value)
    if isinstance(value, dict):
        return any(contains_exact_result(item, expected) for item in value.values())
    return False


def worker_pids():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            executable = os.path.realpath(f"/proc/{entry}/exe")
            if os.path.samefile(executable, WORKER):
                found.append(int(entry))
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return found


def test_config_files_updated():
    env_path = "/app/api/.env"
    assert os.path.isfile(env_path), f"{env_path} does not exist."
    with open(env_path, "r") as f:
        env_content = f.read()
        assert "REDIS_PORT=6379" in env_content, "REDIS_PORT not updated to 6379 in /app/api/.env"
        assert "REDIS_CHANNEL=math_jobs" in env_content, "REDIS_CHANNEL not updated to math_jobs in /app/api/.env"

    config_path = "/app/worker/config.ini"
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, "r") as f:
        config_content = f.read()
        assert "queue_channel=math_jobs" in config_content, "queue_channel not updated to math_jobs in /app/worker/config.ini"


def test_fuzz_equivalence():
    assert os.path.isfile(WORKER), f"Compiled worker {WORKER} does not exist."
    assert os.access(WORKER, os.X_OK), f"Compiled worker {WORKER} is not executable."
    assert os.path.isfile(ORACLE), f"Oracle script {ORACLE} does not exist."

    random.seed(42)
    charset = string.ascii_letters + string.digits
    for _ in range(1000):
        length = random.randint(1, 1024)
        test_input = "".join(random.choices(charset, k=length))
        try:
            expected_output = oracle_value(test_input)
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Oracle failed on input {test_input}: {exc.stderr}")

        try:
            result = subprocess.run(
                [WORKER, test_input],
                capture_output=True,
                text=True,
                check=True,
                timeout=2,
            )
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Agent binary crashed or failed on input {test_input}: {exc.stderr}")
        assert result.stdout.strip() == expected_output, (
            f"Mismatch on input: {test_input[:50]}...\n"
            f"Expected: {expected_output}\nGot: {result.stdout.strip()}"
        )


def test_end_to_end_flow():
    test_input = "testE2Eflow123"
    expected_output = oracle_value(test_input)

    for attempt in range(5):
        try:
            body, parsed = post_compute(test_input)
            assert expected_output in body, (
                f"Expected result {expected_output} not found in API response: {body}"
            )
            assert contains_exact_result(parsed, expected_output), (
                f"API response did not contain the exact result as a JSON value: {body}"
            )
            return
        except urllib.error.URLError as exc:
            if attempt == 4:
                pytest.fail(f"Failed to connect to API at {API_URL} or API returned error: {exc}")
            time.sleep(1)


def test_randomized_flow_uses_redis_queue_and_worker():
    ping = subprocess.run(
        ["redis-cli", "-p", "6379", "PING"],
        capture_output=True,
        text=True,
        check=True,
        timeout=2,
    )
    assert ping.stdout.strip() == "PONG", "Redis is not available on port 6379"

    pids = worker_pids()
    assert pids, "No running /app/worker/math_worker service process was found"

    monitor = subprocess.Popen(
        ["stdbuf", "-oL", "redis-cli", "-p", "6379", "MONITOR"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        time.sleep(0.4)
        for _ in range(8):
            test_input = "verify-" + secrets.token_hex(18)
            expected = oracle_value(test_input)
            body, parsed = post_compute(test_input, timeout=6)
            assert contains_exact_result(parsed, expected), (
                f"Expected exact result {expected} for {test_input}, got: {body}"
            )
    finally:
        monitor.terminate()
        try:
            monitor_output, monitor_error = monitor.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            monitor.kill()
            monitor_output, monitor_error = monitor.communicate(timeout=2)

    lowered = monitor_output.lower()
    assert "math_jobs" in lowered, (
        "No Redis command involving the math_jobs queue was observed during API requests"
    )
    assert re.search(r'\"?(publish|rpush|lpush|xadd)\"?\s+\"?math_jobs\b', lowered), (
        "The API requests did not enqueue or publish work to math_jobs"
    )

    numsub = subprocess.run(
        ["redis-cli", "-p", "6379", "--raw", "PUBSUB", "NUMSUB", "math_jobs"],
        capture_output=True,
        text=True,
        check=True,
        timeout=2,
    ).stdout.splitlines()
    subscriber_present = bool(numsub) and numsub[-1].strip().isdigit() and int(numsub[-1]) > 0

    client_list = subprocess.run(
        ["redis-cli", "-p", "6379", "--raw", "CLIENT", "LIST"],
        capture_output=True,
        text=True,
        check=True,
        timeout=2,
    ).stdout.lower()
    blocked_consumer = any(
        f"cmd={command}" in client_list
        for command in (
            "subscribe", "psubscribe", "ssubscribe", "brpop", "blpop",
            "brpoplpush", "blmove", "xread", "xreadgroup"
        )
    )
    monitored_consumer = bool(re.search(
        r'\"?(subscribe|psubscribe|ssubscribe|brpop|blpop|rpop|lpop|xread|xreadgroup)\"?[^\n]*math_jobs',
        lowered,
    ))
    assert subscriber_present or blocked_consumer or monitored_consumer, (
        "No Redis queue consumer was found for the math_jobs work observed during the requests"
    )


def test_zz_api_result_depends_on_running_worker():
    pids = worker_pids()
    assert pids, "No running worker process is available for the dependency check"
    for pid in pids:
        os.kill(pid, signal.SIGSTOP)

    try:
        test_input = "paused-worker-" + secrets.token_hex(24)
        expected = oracle_value(test_input)
        incorrectly_succeeded = False
        try:
            body, parsed = post_compute(test_input, timeout=2)
            incorrectly_succeeded = contains_exact_result(parsed, expected)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, OSError):
            pass
        assert not incorrectly_succeeded, (
            "The API returned the correct fresh result while every math_worker process was paused; "
            "the end-to-end path is bypassing the worker"
        )
    finally:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
