#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import time

import pytest

LOG_FILE = "/home/user/observability/logs/access.log"
OUT_FILE = "/home/user/observability/metrics/summary.json"
COLLECTOR = "/home/user/observability/collector.sh"
KEYS = ["status_2xx", "status_3xx", "status_4xx", "status_5xx", "total_bytes"]


def run_collector():
    return subprocess.run(
        ["bash", COLLECTOR],
        env={"PWD": "/tmp"},
        cwd="/tmp",
        capture_output=True,
        text=True,
    )


def read_output():
    assert os.path.exists(OUT_FILE), f"Output file {OUT_FILE} was not created. Ensure you are using absolute paths."
    with open(OUT_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON")


def assert_metrics(data, expected):
    for key in KEYS:
        assert data.get(key) == expected[key], f"{key} mismatch: {data.get(key)} != {expected[key]}"


def generate_log_file(num_lines=500_000):
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

    line_200 = '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.1" 200 1024\n'
    line_301 = '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.1" 301 0\n'
    line_404 = '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.1" 404 512\n'
    line_500 = '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.1" 500 256\n'

    pattern = (line_200 * 7) + line_301 + line_404 + line_500
    with open(LOG_FILE, "w") as f:
        for _ in range(num_lines // 10):
            f.write(pattern)

    return {
        "status_2xx": (num_lines // 10) * 7,
        "status_3xx": num_lines // 10,
        "status_4xx": num_lines // 10,
        "status_5xx": num_lines // 10,
        "total_bytes": (num_lines // 10) * (7 * 1024 + 512 + 256),
    }


def generate_random_log(num_lines):
    rng = secrets.SystemRandom()
    statuses = [200, 201, 204, 299, 301, 302, 307, 399, 400, 404, 429, 499, 500, 502, 503, 599]
    expected = {key: 0 for key in KEYS}
    lines = []

    # Include every status block, then fill the rest unpredictably.
    selected = [200, 301, 404, 500]
    selected.extend(rng.choice(statuses) for _ in range(num_lines - len(selected)))
    rng.shuffle(selected)

    for index, status in enumerate(selected):
        byte_count = rng.randrange(0, 200_000)
        expected[f"status_{status // 100}xx"] += 1
        expected["total_bytes"] += byte_count
        token = secrets.token_hex(5)
        lines.append(
            f'10.{index % 251}.{(index * 7) % 251}.{(index * 13) % 251} - - '
            f'[10/Oct/2000:13:55:36 -0700] "GET /item/{token} HTTP/1.1" '
            f'{status} {byte_count}\n'
        )

    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "w") as f:
        f.writelines(lines)
    return expected


def test_collector_performance_and_correctness():
    expected = generate_log_file(500_000)

    if os.path.exists(OUT_FILE):
        os.remove(OUT_FILE)

    start_time = time.time()
    result = run_collector()
    end_time = time.time()

    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    duration = end_time - start_time
    assert duration <= 1.5, f"Execution time {duration:.2f}s exceeded threshold of 1.5s. Optimize your script (e.g. using awk)."
    assert_metrics(read_output(), expected)


def test_randomized_log_contents():
    rng = secrets.SystemRandom()
    for _ in range(3):
        expected = generate_random_log(rng.randrange(1200, 5000))
        if os.path.exists(OUT_FILE):
            os.remove(OUT_FILE)

        result = run_collector()
        assert result.returncode == 0, f"Script failed on randomized log with error: {result.stderr}"
        assert_metrics(read_output(), expected)


def test_empty_log_file():
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "w") as f:
        f.write("")

    if os.path.exists(OUT_FILE):
        os.remove(OUT_FILE)

    result = run_collector()
    assert result.returncode == 0, f"Script failed on empty log with error: {result.stderr}"
    data = read_output()
    for key in KEYS:
        assert data.get(key) == 0, f"{key} should be 0 for empty log, got {data.get(key)}"


def test_missing_log_file():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    if os.path.exists(OUT_FILE):
        os.remove(OUT_FILE)

    result = run_collector()
    assert result.returncode == 0, f"Script failed when log was missing with error: {result.stderr}"
    data = read_output()
    for key in KEYS:
        assert data.get(key) == 0, f"{key} should be 0 for missing log, got {data.get(key)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
