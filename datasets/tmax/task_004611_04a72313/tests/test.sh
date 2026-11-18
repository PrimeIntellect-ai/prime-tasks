#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "pymongo:pymongo"; do
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
import os
import signal
import socket
import subprocess
import time
import uuid
from collections import Counter

import pytest
import requests
from pymongo import MongoClient

API_URL = "http://127.0.0.1:8080/deadlock-analysis"
AUTH_TOKEN = "Omega-92-Delta"
EXPECTED_TARGET_USER = "U-7734"
EXPECTED_DEADLOCKED_USER = "U-1022"
EXPECTED_RESOURCES = ["RES-A", "RES-B"]

EXPECTED_CSV_ROWS = [
    ("TX01", "U-1111", "RES-X", "GRANTED", "100"),
    ("TX02", "U-7734", "RES-A", "GRANTED", "105"),
    ("TX03", "U-1022", "RES-B", "GRANTED", "106"),
    ("TX04", "U-7734", "RES-B", "REQUESTED", "110"),
    ("TX05", "U-1022", "RES-A", "REQUESTED", "112"),
    ("TX06", "U-2222", "RES-C", "GRANTED", "115"),
]


def get_response(token=None):
    headers = {} if token is None else {"Authorization": f"Bearer {token}"}
    try:
        return requests.get(API_URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {API_URL}: {e}")


def assert_result(data, target, other, resources):
    assert "target_user" in data, "Missing 'target_user' in response JSON"
    assert data["target_user"] == target, f"Expected target_user '{target}', got '{data['target_user']}'"
    assert "deadlocked_with_user" in data, "Missing 'deadlocked_with_user' in response JSON"
    assert data["deadlocked_with_user"] == other, f"Expected deadlocked_with_user '{other}', got '{data['deadlocked_with_user']}'"
    assert "resources_involved" in data, "Missing 'resources_involved' in response JSON"
    assert isinstance(data["resources_involved"], list), "'resources_involved' must be a list"
    assert data["resources_involved"] == resources, f"Expected resources_involved {resources} (sorted), got {data['resources_involved']}"


def listener_pid(port):
    inodes = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    cols = line.split()
                    if int(cols[1].rsplit(":", 1)[1], 16) == port and cols[3] == "0A":
                        inodes.add(cols[9])
        except FileNotFoundError:
            pass
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    return int(name)
        except (FileNotFoundError, PermissionError):
            continue
    raise AssertionError(f"Could not identify the process listening on port {port}")


def restart_api():
    pid = listener_pid(8080)
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        command = [part.decode() for part in f.read().split(b"\0") if part]
    cwd = os.readlink(f"/proc/{pid}/cwd")
    with open(f"/proc/{pid}/environ", "rb") as f:
        env_items = [item for item in f.read().split(b"\0") if b"=" in item]
    env = os.environ.copy()
    env.update({item.split(b"=", 1)[0].decode(): item.split(b"=", 1)[1].decode() for item in env_items})
    assert command, "The API listener has no executable command"

    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.1)
    else:
        os.kill(pid, signal.SIGKILL)

    proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 20
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"API command exited during restart with status {proc.returncode}: {command}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.5):
                return
        except OSError:
            time.sleep(0.2)
    pytest.fail("API did not return on 127.0.0.1:8080 after restart")


def derive_cycle(rows, target):
    grants = {(r["user_id"], r["resource_id"]) for r in rows if r["lock_type"] == "GRANTED"}
    requests = {(r["user_id"], r["resource_id"]) for r in rows if r["lock_type"] == "REQUESTED"}
    users = {r["user_id"] for r in rows if r["user_id"] != target}
    resources = {r["resource_id"] for r in rows}
    matches = []
    for other in users:
        for held_by_target in resources:
            for held_by_other in resources:
                if held_by_target == held_by_other:
                    continue
                if ((target, held_by_target) in grants and
                    (target, held_by_other) in requests and
                    (other, held_by_other) in grants and
                    (other, held_by_target) in requests):
                    matches.append((other, sorted([held_by_target, held_by_other])))
    assert len(matches) == 1, f"Verifier fixture should contain one cycle, found {matches}"
    return matches[0]


def test_api_unauthorized():
    response = get_response()
    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}"


def test_api_invalid_token():
    response = get_response("Invalid-Token-123")
    assert response.status_code == 401, f"Expected 401 Unauthorized with invalid token, got {response.status_code}"


def test_api_authorized_and_response():
    response = get_response(AUTH_TOKEN)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert_result(data, EXPECTED_TARGET_USER, EXPECTED_DEADLOCKED_USER, EXPECTED_RESOURCES)


def test_mongodb_ingestion_and_real_aggregation():
    try:
        client = MongoClient("mongodb://127.0.0.1:27017", serverSelectionTimeoutMS=3000)
        client.admin.command("ping")
    except Exception as e:
        pytest.fail(f"A local MongoDB server is not available on port 27017: {e}")

    db = client["deadlock_db"]
    assert "locks" in db.list_collection_names(), "MongoDB collection deadlock_db.locks does not exist"
    original = list(db.locks.find({}, {"_id": 0}))
    normalized = Counter(
        (str(r.get("tx_id")), str(r.get("user_id")), str(r.get("resource_id")),
         str(r.get("lock_type")), str(r.get("timestamp")))
        for r in original
    )
    assert normalized == Counter(EXPECTED_CSV_ROWS), "deadlock_db.locks does not contain exactly the CSV records"

    suffix = uuid.uuid4().hex[:10].upper()
    other = f"U-{suffix}"
    resource_a = f"DYN-A-{suffix}"
    resource_b = f"DYN-Z-{suffix}"
    fixture = [
        {"tx_id": "V01", "user_id": EXPECTED_TARGET_USER, "resource_id": resource_a, "lock_type": "GRANTED", "timestamp": 200},
        {"tx_id": "V02", "user_id": other, "resource_id": resource_b, "lock_type": "GRANTED", "timestamp": 201},
        {"tx_id": "V03", "user_id": EXPECTED_TARGET_USER, "resource_id": resource_b, "lock_type": "REQUESTED", "timestamp": 202},
        {"tx_id": "V04", "user_id": other, "resource_id": resource_a, "lock_type": "REQUESTED", "timestamp": 203},
        {"tx_id": "V05", "user_id": f"NOISE-{suffix}", "resource_id": f"NOISE-RES-{suffix}", "lock_type": "GRANTED", "timestamp": 204},
    ]
    expected_other, expected_resources = derive_cycle(fixture, EXPECTED_TARGET_USER)

    db.command("profile", 0)
    if "system.profile" in db.list_collection_names():
        db["system.profile"].drop()
    db.command("profile", 2)
    db.locks.delete_many({})
    db.locks.insert_many(fixture)

    restart_api()
    response = get_response(AUTH_TOKEN)
    assert response.status_code == 200, f"Expected 200 after database fixture change, got {response.status_code}: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON after database fixture change: {response.text}")
    assert_result(data, EXPECTED_TARGET_USER, expected_other, expected_resources)

    profiles = list(db["system.profile"].find({
        "ns": "deadlock_db.locks",
        "command.aggregate": "locks"
    }))
    assert profiles, "No MongoDB aggregate command against deadlock_db.locks was observed while the API restarted/served its result"
    assert any(isinstance(p.get("command", {}).get("pipeline"), list) and p["command"]["pipeline"] for p in profiles), \
        "The observed aggregate command did not contain a non-empty aggregation pipeline"
    db.command("profile", 0)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
