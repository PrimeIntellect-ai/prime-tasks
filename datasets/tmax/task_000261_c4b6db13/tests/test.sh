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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import random
import shutil
import signal
import stat
import string
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:8080/api/targets"
TOKEN = "LAB-TKN-8891A"
SOURCE = "/home/user/dataset_server.c"
BINARY = "/home/user/dataset_server"
DYNAMIC_DIR = "/home/user/dataset/.verifier_dynamic"


def kill_port_8080():
    """Kill any process already listening on TCP port 8080."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        local = fields[1]
                        state = fields[3]
                        if local.rsplit(":", 1)[-1].upper() == "1F90" and state == "0A":
                            inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def start_submitted_server():
    kill_port_8080()
    proc = subprocess.Popen(
        [BINARY],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 7
    last_error = None
    while time.time() < deadline:
        try:
            requests.get(URL, timeout=0.4)
            return proc
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"Submitted executable did not start a server promptly: {last_error}")


def assert_authorized_response(expected):
    response = requests.get(
        URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=5
    )
    assert response.status_code == 200, (
        f"Expected HTTP 200 for valid auth, but got {response.status_code}. "
        f"Response: {response.text}"
    )
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, (
        f"Expected Content-Type to contain application/json, got {content_type}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Failed to parse response body as JSON. Response text: {response.text}")
    assert isinstance(data, list), (
        f"Expected response JSON to be a list, got {type(data).__name__}"
    )
    assert len(data) == len(expected), (
        f"Expected exactly {len(expected)} objects in the JSON array, got {len(data)}: {data}"
    )
    for obj in expected:
        assert obj in data, f"Expected object {obj} not found in response data: {data}"
    return data


def test_submitted_program_and_server_behavior():
    # The requested artifacts must really exist and be ordinary files, and the
    # executable must be a compiled ELF rather than a script or another server.
    assert os.path.exists(SOURCE), f"Missing required source file {SOURCE}"
    assert not os.path.islink(SOURCE), f"{SOURCE} must not be a symlink"
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"{SOURCE} must be a regular file"
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty"

    assert os.path.exists(BINARY), f"Missing required executable {BINARY}"
    assert not os.path.islink(BINARY), f"{BINARY} must not be a symlink"
    binary_stat = os.stat(BINARY)
    assert stat.S_ISREG(binary_stat.st_mode), f"{BINARY} must be a regular file"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable"

    # First retain all original checks against the original dataset.
    shutil.rmtree(DYNAMIC_DIR, ignore_errors=True)
    start_submitted_server()

    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")
    assert response.status_code == 401, (
        f"Expected HTTP 401 for missing auth, but got {response.status_code}. "
        f"Response: {response.text}"
    )

    baseline = [
        {"id": 101, "is_research_target": True, "name": "sample_A"},
        {"id": 103, "is_research_target": True, "name": "sample_C"},
    ]
    baseline_data = assert_authorized_response(baseline)
    assert len(baseline_data) == 2, (
        f"Expected exactly 2 objects in the JSON array, got {len(baseline_data)}"
    )

    # Add unpredictable compressed JSON-lines data below a deep directory. This
    # forces the submitted artifact to traverse, decompress, parse, and filter,
    # rather than returning the two known objects as constants.
    alphabet = string.ascii_letters + string.digits
    nonce = "".join(random.SystemRandom().choice(alphabet) for _ in range(18))
    id1 = random.SystemRandom().randint(200000, 600000)
    id2 = random.SystemRandom().randint(600001, 999999)
    target1 = {
        "id": id1,
        "is_research_target": True,
        "name": f"dynamic_{nonce}_one",
        "payload": nonce[::-1],
    }
    target2 = {
        "name": f"dynamic_{nonce}_two",
        "payload": {"nonce": nonce},
        "is_research_target": True,
        "id": id2,
    }
    excluded_false = {
        "id": id1 + 1,
        "metadata": {"is_research_target": True},
        "is_research_target": False,
        "name": f"exclude_{nonce}",
    }
    excluded_string = {
        "id": id2 + 1,
        "is_research_target": "true",
        "name": f"exclude_string_{nonce}",
    }

    deep = os.path.join(DYNAMIC_DIR, "one", "two", "three")
    os.makedirs(deep, exist_ok=True)
    with gzip.open(os.path.join(deep, f"records_{nonce}.json.gz"), "wt", encoding="utf-8") as f:
        for obj in (target1, excluded_false, target2, excluded_string):
            f.write(json.dumps(obj, separators=(",", ":")) + "\n")

    # These contain target-looking data but have suffixes that must be ignored.
    with open(os.path.join(deep, "plain.json"), "w", encoding="utf-8") as f:
        json.dump({"id": -1, "is_research_target": True, "name": nonce}, f)
    with gzip.open(os.path.join(deep, "backup.json.gz.bak"), "wt", encoding="utf-8") as f:
        f.write(json.dumps({"id": -2, "is_research_target": True, "name": nonce}) + "\n")

    # Add another recursive loop; startup must still complete within the timeout.
    os.symlink(DYNAMIC_DIR, os.path.join(deep, "loop_to_dynamic_root"))

    start_submitted_server()

    wrong = requests.get(
        URL, headers={"Authorization": f"Bearer {TOKEN}-{nonce}"}, timeout=5
    )
    assert wrong.status_code == 401, (
        f"Expected HTTP 401 for incorrect auth, got {wrong.status_code}: {wrong.text}"
    )

    expected = baseline + [target1, target2]
    data = assert_authorized_response(expected)
    assert excluded_false not in data
    assert excluded_string not in data
    assert all(item.get("id") not in (-1, -2) for item in data)

    other = requests.get(
        "http://127.0.0.1:8080/not-the-api",
        headers={"Authorization": f"Bearer {TOKEN}"},
        timeout=5,
    )
    assert other.status_code != 200, "Server must expose only GET /api/targets"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
