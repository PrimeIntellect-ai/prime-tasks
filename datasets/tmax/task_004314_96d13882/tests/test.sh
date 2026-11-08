#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime as dt
import os
import secrets
import signal
import subprocess
import time

import pytest
import requests

PORT = 8194
BASE_URL = f"http://127.0.0.1:{PORT}"
CSV_PATH = "/app/logs/etl_dump.csv"


def get_json(user_id, timeout=5):
    url = f"{BASE_URL}/api/user_latency"
    try:
        response = requests.get(url, params={"user_id": user_id}, timeout=timeout)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}. Is the server running? Error: {e}")

    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got invalid JSON: {response.text}")


def test_01_api_user_a():
    data = get_json("A")
    expected_data = [
        {"timestamp": "2023-10-01 10:00:00", "max_latency": 120.0},
        {"timestamp": "2023-10-01 10:10:00", "max_latency": 120.0},
        {"timestamp": "2023-10-01 10:20:00", "max_latency": 120.0},
        {"timestamp": "2023-10-01 10:30:00", "max_latency": 150.0},
    ]
    assert data == expected_data, (
        f"Data for user A did not match expected.\nExpected: {expected_data}\nGot: {data}"
    )


def test_02_api_user_b():
    data = get_json("B")
    expected_data = [
        {"timestamp": "2023-10-01 10:00:00", "max_latency": 200.0},
        {"timestamp": "2023-10-01 10:10:00", "max_latency": 210.0},
    ]
    assert data == expected_data, (
        f"Data for user B did not match expected.\nExpected: {expected_data}\nGot: {data}"
    )


def listening_socket_inodes(port):
    wanted = f"{port:04X}"
    found = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and local.rsplit(":", 1)[1].upper() == wanted:
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def listener_pid(port):
    inodes = listening_socket_inodes(port)
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(name)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    raise AssertionError(f"Could not identify the process listening on port {port}")


def capture_and_restart_server(port):
    pid = listener_pid(port)
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="surrogateescape") for part in f.read().split(b"\0") if part]
    assert argv, "The listening server process has an empty command line"

    executable = os.readlink(f"/proc/{pid}/exe")
    cwd = os.readlink(f"/proc/{pid}/cwd")
    with open(f"/proc/{pid}/environ", "rb") as f:
        env_parts = [part for part in f.read().split(b"\0") if b"=" in part]
    env = {
        key.decode(errors="surrogateescape"): value.decode(errors="surrogateescape")
        for key, value in (part.split(b"=", 1) for part in env_parts)
    }

    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.05)
    else:
        os.kill(pid, signal.SIGKILL)

    process = subprocess.Popen(
        argv,
        executable=executable,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 12
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Restarted server exited with status {process.returncode}")
        try:
            requests.get(BASE_URL + "/api/user_latency", params={"user_id": "__ready__"}, timeout=0.5)
            return process
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Restarted server did not become ready: {last_error}")


def derive_expected(csv_path, user_id, interval_minutes=10):
    exact_rows = set()
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            exact_rows.add((row["timestamp"], row["user_id"], row["latency"]))

    buckets = {}
    for timestamp, uid, latency in exact_rows:
        if uid != user_id:
            continue
        parsed = dt.datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
        bucket = parsed.replace(
            minute=(parsed.minute // interval_minutes) * interval_minutes,
            second=0,
            microsecond=0,
        )
        value = float(latency)
        buckets[bucket] = max(value, buckets.get(bucket, value))

    assert buckets
    current = min(buckets)
    end = max(buckets)
    previous = None
    result = []
    while current <= end:
        if current in buckets:
            previous = buckets[current]
        if previous is not None:
            result.append({
                "timestamp": current.strftime("%Y-%m-%d %H:%M:%S"),
                "max_latency": previous,
            })
        current += dt.timedelta(minutes=interval_minutes)
    return result


def test_03_pipeline_handles_unseen_user_and_derived_data():
    original = open(CSV_PATH, "rb").read()
    user_id = "probe_" + secrets.token_hex(8)
    base_value = 300 + secrets.randbelow(300)
    rows = [
        ("2024-07-16 14:02:00", user_id, float(base_value)),
        ("2024-07-16 14:05:00", user_id, float(base_value + 19)),
        ("2024-07-16 14:05:00", user_id, float(base_value + 19)),
        ("2024-07-16 14:23:00", user_id, float(base_value + 7)),
        ("2024-07-16 14:45:00", user_id, float(base_value + 31)),
    ]

    process = None
    try:
        with open(CSV_PATH, "a", newline="") as f:
            writer = csv.writer(f)
            writer.writerows(rows)
        expected = derive_expected(CSV_PATH, user_id)
        process = capture_and_restart_server(PORT)
        actual = get_json(user_id)
        assert actual == expected, (
            "API did not process the dynamically added user through the general "
            f"deduplication/resampling pipeline.\nExpected: {expected}\nGot: {actual}"
        )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
