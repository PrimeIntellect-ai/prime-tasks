#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import signal
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8123"
ENDPOINT = "/api/v1/posterior"
AUTH_HEADER = {"Authorization": "Bearer bayes_rule_2024"}
PORT = 8123


def get_response(record_id, headers=AUTH_HEADER):
    try:
        return requests.get(
            f"{BASE_URL}{ENDPOINT}?id={record_id}",
            headers=headers,
            timeout=2,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")


def assert_success(record_id, expected):
    resp = get_response(record_id)
    assert resp.status_code == 200, (
        f"Expected 200 OK for id={record_id}, got {resp.status_code}. "
        f"Response: {resp.text}"
    )
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert "id" in data, "Response JSON missing 'id' key"
    assert data["id"] == record_id, f"Expected id={record_id}, got {data['id']}"
    assert "posterior_mean" in data, "Response JSON missing 'posterior_mean' key"
    assert math.isclose(data["posterior_mean"], expected, rel_tol=1e-5), (
        f"Expected posterior_mean ~ {expected}, got {data['posterior_mean']}"
    )


def listener_pid(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except OSError:
            continue
    return None


def read_process(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        command = [part.decode(errors="surrogateescape") for part in f.read().split(b"\0") if part]
    assert command, "Could not determine the API server command"

    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    with open(f"/proc/{pid}/environ", "rb") as f:
        for item in f.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return command, cwd, env


def stop_listener(port):
    deadline = time.time() + 5
    while time.time() < deadline:
        pid = listener_pid(port)
        if pid is None:
            return
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            continue
        for _ in range(10):
            time.sleep(0.1)
            if listener_pid(port) != pid:
                break
        else:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    assert listener_pid(port) is None, f"Could not stop the existing server on port {port}"


def wait_for_server(process):
    deadline = time.time() + 12
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"Restarted API server exited with status {process.returncode}")
        try:
            requests.get(f"{BASE_URL}{ENDPOINT}?id=0", headers=AUTH_HEADER, timeout=0.3)
            return
        except requests.exceptions.RequestException:
            time.sleep(0.15)
    pytest.fail("Restarted API server did not begin listening on the required port")


def test_api_success_id_1():
    assert_success(1, 0.2)


def test_api_success_id_2():
    assert_success(2, 0.1)


def test_api_unauthorized():
    resp1 = get_response(1, {"Authorization": "Bearer wrong_token"})
    resp2 = get_response(1, {})
    assert resp1.status_code == 401, f"Expected 401 Unauthorized for bad token, got {resp1.status_code}"
    assert resp2.status_code == 401, f"Expected 401 Unauthorized for missing token, got {resp2.status_code}"


def test_api_not_found():
    resp = get_response(999)
    assert resp.status_code == 404, f"Expected 404 Not Found for non-existent ID, got {resp.status_code}"


def test_dynamic_etl_and_inference_after_restart():
    pid = listener_pid(PORT)
    assert pid is not None, "Could not identify the API process listening on port 8123"
    command, cwd, env = read_process(pid)
    stop_listener(PORT)

    nonce = secrets.randbelow(800000) + 100000
    ids = [1, 2, nonce, nonce + 1]
    priors = {
        "A": {"alpha": secrets.randbelow(8) + 2, "beta": secrets.randbelow(9) + 3},
        "B": {"alpha": secrets.randbelow(7) + 3, "beta": secrets.randbelow(8) + 4},
        "C": {"alpha": secrets.randbelow(9) + 1, "beta": secrets.randbelow(9) + 2},
    }
    rows = [
        (ids[0], 37, secrets.randbelow(25) + 1, "B"),
        (ids[1], 61, secrets.randbelow(35) + 2, "A"),
        (ids[2], 43, secrets.randbelow(30) + 1, "C"),
        (ids[3], 79, secrets.randbelow(45) + 2, "B"),
    ]

    with open("/home/user/data/records.csv", "w") as f:
        f.write("id,trials,successes,source_id\n")
        for record_id, trials, successes, source_id in rows:
            f.write(f"{record_id},{trials},{successes},{source_id}\n")
    with open("/home/user/data/reference.json", "w") as f:
        json.dump(priors, f)

    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_server(process)

    for record_id, trials, successes, source_id in rows:
        prior = priors[source_id]
        expected = (prior["alpha"] + successes) / (
            prior["alpha"] + prior["beta"] + trials
        )
        assert_success(record_id, expected)

    missing = nonce + 1000001
    resp = get_response(missing)
    assert resp.status_code == 404, f"Expected 404 Not Found for non-existent ID, got {resp.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
