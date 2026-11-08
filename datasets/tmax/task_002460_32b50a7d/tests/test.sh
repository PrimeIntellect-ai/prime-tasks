#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import secrets
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/ingest"
PROJECT = "/home/user/sensor_service"


def wait_for_service():
    for _ in range(10):
        try:
            requests.get("http://127.0.0.1:8080/", timeout=1)
            return
        except requests.exceptions.RequestException:
            time.sleep(1)
    pytest.fail("Failed to connect to the service at 127.0.0.1:8080")


def listener_processes():
    inodes = set()
    try:
        with open("/proc/net/tcp") as f:
            next(f)
            for line in f:
                fields = line.split()
                local, state = fields[1], fields[3]
                address, port = local.split(":")
                if address.upper() == "0100007F" and int(port, 16) == 8080 and state == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.append((pid, os.path.realpath(f"/proc/{pid}/exe")))
                    break
        except OSError:
            continue
    return found


def test_release_rust_artifact_is_serving():
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Missing Rust Cargo.toml"
    src = os.path.join(PROJECT, "src")
    assert os.path.isdir(src) and any(name.endswith(".rs") for _, _, files in os.walk(src) for name in files), "Missing Rust source"

    processes = listener_processes()
    assert processes, "No process is listening specifically on 127.0.0.1:8080"
    prefix = os.path.realpath(os.path.join(PROJECT, "target", "release")) + os.sep
    release_exes = [exe for _, exe in processes if exe.startswith(prefix) and os.sep + "deps" + os.sep not in exe]
    assert release_exes, f"The listener is not a release artifact from {PROJECT}: {processes}"
    with open(release_exes[0], "rb") as f:
        assert f.read(4) == b"\x7fELF", "Serving release artifact is not an ELF executable"


def post_and_check(payload, expected):
    try:
        response = requests.post(URL, data=payload, headers={"Content-Type": "text/plain"}, timeout=10)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the Rust service at 127.0.0.1:8080. Is it running?")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    assert response.headers.get("Content-Type", "").lower().startswith("application/json"), response.headers.get("Content-Type")
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")

    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    assert len(data) == len(expected), f"Expected {len(expected)} records, got {len(data)}"
    for i, wanted in enumerate(expected):
        actual = data[i]
        assert actual["time"] == wanted["time"], f"Mismatch in time at index {i}. Expected {wanted['time']}, got {actual.get('time')}"
        assert isinstance(actual.get("avg_temp"), (int, float)), f"avg_temp at index {i} is not numeric"
        assert abs(actual["avg_temp"] - wanted["avg_temp"]) < 0.01, f"Mismatch in avg_temp at index {i}. Expected {wanted['avg_temp']}, got {actual.get('avg_temp')}"


def test_original_ingest_endpoint():
    payload = """[2023-10-14T08:30:00Z] SENSOR_1 msg_id=a1 temp=24.5
[2023-10-14T08:30:00Z] SENSOR_2 msg_id=a2 temp=24.1
[2023-10-14T08:30:00Z] SENSOR_2 msg_id=a2 temp=30.0
[2023-10-14T08:30:01Z] SENSOR_3 msg_id=a3 temp=26.8
[2023-10-14T08:30:03Z] SENSOR_4 msg_id=a4 temp=26.1"""
    expected = [
        {"time": "2023-10-14T08:30:00Z", "avg_temp": 24.3},
        {"time": "2023-10-14T08:30:01Z", "avg_temp": 24.3},
        {"time": "2023-10-14T08:30:02Z", "avg_temp": 24.3},
        {"time": "2023-10-14T08:30:03Z", "avg_temp": 26.1},
    ]
    post_and_check(payload, expected)


def accepted(value):
    result = subprocess.run(
        ["/app/sensor_filter_x64", format(value, ".1f")],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=2,
    )
    return result.returncode == 0


def iso(second):
    return second.strftime("%Y-%m-%dT%H:%M:%SZ")


def derive_expected(records):
    seen = set()
    buckets = {}
    for timestamp, sensor, msg_id, temp in records:
        if msg_id in seen:
            continue
        seen.add(msg_id)
        if not accepted(temp):
            continue
        buckets.setdefault(timestamp, []).append(temp)

    assert buckets, "Generated test case unexpectedly has no valid readings"
    first, last = min(buckets), max(buckets)
    output = []
    current = None
    point = first
    while point <= last:
        if point in buckets:
            values = buckets[point]
            current = sum(values) / len(values)
        output.append({"time": iso(point), "avg_temp": current})
        point += datetime.timedelta(seconds=1)
    return output


def test_runtime_generated_payloads():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    valid_values = [v / 10.0 for v in range(-250, 451) if accepted(v / 10.0)]
    anomalous_values = [v / 10.0 for v in range(-250, 451) if not accepted(v / 10.0)]
    assert valid_values and anomalous_values

    for case in range(4):
        base = datetime.datetime(2024 + rng.randrange(2), rng.randrange(1, 13), rng.randrange(1, 25), rng.randrange(0, 20), rng.randrange(0, 50), rng.randrange(0, 30))
        first_id = secrets.token_hex(8)
        last_id = secrets.token_hex(8)
        records = [
            (base, "1", first_id, rng.choice(valid_values)),
            (base + datetime.timedelta(seconds=7), "2", last_id, rng.choice(valid_values)),
        ]

        offsets = [0, 0, 2, 2, 3, 5, 7]
        for index, offset in enumerate(offsets):
            temp_pool = valid_values if index % 2 == 0 else anomalous_values
            records.append((base + datetime.timedelta(seconds=offset), str(10 + index), secrets.token_hex(8), rng.choice(temp_pool)))

        duplicate_source = records[2]
        records.append((base + datetime.timedelta(seconds=1), "99", duplicate_source[2], rng.choice(valid_values)))
        records.append((base + datetime.timedelta(seconds=6), "98", first_id, rng.choice(anomalous_values)))

        middle = records[2:]
        rng.shuffle(middle)
        records = records[:2] + middle
        expected = derive_expected(records)
        payload = "\n".join(
            f"[{iso(timestamp)}] SENSOR_{sensor} msg_id={msg_id} temp={temp:.1f}"
            for timestamp, sensor, msg_id, temp in records
        )
        post_and_check(payload, expected)


def setup_module():
    wait_for_service()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
