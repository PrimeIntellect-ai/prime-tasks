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
import importlib
import json
import os
import secrets
import signal
import subprocess
import sys
import time

import pytest
import requests

PACKAGE_DIR = "/app/vendor/db-backup-api"
METADATA_PATH = "/home/user/data/backup_metadata.json"
DEPENDENCIES_PATH = "/home/user/data/db_dependencies.json"
URL = "http://127.0.0.1:8080/prioritize-backups"


def expected_result(metadata, dependencies):
    valid_dbs = {db["db_name"]: db for db in metadata if db.get("tier") != 3}
    in_degrees = {db_name: 0 for db_name in valid_dbs}
    for edge in dependencies:
        target = edge.get("target")
        if target in in_degrees:
            in_degrees[target] += 1

    scores = {}
    for db_name, db_info in valid_dbs.items():
        size_gb = db_info.get("size_gb", 1)
        scores[db_name] = (in_degrees[db_name] + 1) * (1000 / size_gb)

    sorted_dbs = sorted(scores.keys(), key=lambda name: scores[name], reverse=True)
    return sorted_dbs[:5]


def query_and_assert(expected):
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the API at {URL}. Is the service running? Error: {exc}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    assert isinstance(data, dict), f"Expected a JSON object, got: {data}"
    assert "priority_backups" in data, (
        f"Key 'priority_backups' missing from response. Actual response: {data}"
    )
    assert set(data.keys()) == {"priority_backups"}, (
        f"Response must contain only 'priority_backups'. Actual response: {data}"
    )
    actual_top_5 = data["priority_backups"]
    assert isinstance(actual_top_5, list), f"priority_backups must be a list, got {actual_top_5}"
    assert actual_top_5 == expected, (
        f"Expected priority_backups to be {expected}, but got {actual_top_5}"
    )


def stop_existing_listener():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as handle:
                lines = handle.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                port = int(fields[1].split(":")[1], 16)
                if port == 8080:
                    socket_inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                pids.add(int(entry))
                break

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            requests.get(URL, timeout=0.2)
        except requests.exceptions.RequestException:
            return
        time.sleep(0.1)

    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


def start_from_launch_script():
    launch_path = os.path.join(PACKAGE_DIR, "launch.sh")
    assert os.path.isfile(launch_path), f"Missing {launch_path}"
    assert os.access(launch_path, os.X_OK), f"{launch_path} is not executable"

    stop_existing_listener()
    process = subprocess.Popen(
        [launch_path],
        cwd=PACKAGE_DIR,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(URL, timeout=0.5)
            if response.status_code == 200:
                return process
        except requests.exceptions.RequestException as exc:
            last_error = exc
        time.sleep(0.2)
    pytest.fail(f"launch.sh did not start the API on 127.0.0.1:8080: {last_error}")


def make_dynamic_case(prefix, sizes, incoming_counts):
    names = [f"{prefix}_db_{i}" for i in range(len(sizes))]
    excluded = f"{prefix}_tier3"
    metadata = [
        {"db_name": name, "size_gb": size, "tier": 1 if i % 2 == 0 else 2}
        for i, (name, size) in enumerate(zip(names, sizes))
    ]
    metadata.append({"db_name": excluded, "size_gb": 1, "tier": 3})

    dependencies = []
    for target, count in zip(names, incoming_counts):
        for edge_number in range(count):
            dependencies.append({
                "source": f"{prefix}_source_{target}_{edge_number}",
                "target": target,
            })

    # Tier-3 databases must not appear, but edges originating from them still
    # contribute to the in-degree of a remaining target.
    dependencies.append({"source": excluded, "target": names[0]})
    dependencies.append({"source": names[0], "target": excluded})
    return metadata, dependencies


def test_api_prioritize_backups():
    assert os.path.exists(METADATA_PATH), f"Missing {METADATA_PATH}"
    assert os.path.exists(DEPENDENCIES_PATH), f"Missing {DEPENDENCIES_PATH}"

    sys.path.insert(0, PACKAGE_DIR)
    try:
        config = importlib.import_module("config")
    finally:
        sys.path.pop(0)
    assert config.METADATA_PATH == METADATA_PATH, (
        f"config.METADATA_PATH must be {METADATA_PATH}, got {config.METADATA_PATH}"
    )
    assert config.GRAPH_PATH == DEPENDENCIES_PATH, (
        f"config.GRAPH_PATH must be {DEPENDENCIES_PATH}, got {config.GRAPH_PATH}"
    )

    with open(METADATA_PATH, "rb") as handle:
        original_metadata_bytes = handle.read()
    with open(DEPENDENCIES_PATH, "rb") as handle:
        original_dependencies_bytes = handle.read()

    process = start_from_launch_script()
    try:
        metadata = json.loads(original_metadata_bytes)
        dependencies = json.loads(original_dependencies_bytes)
        query_and_assert(expected_result(metadata, dependencies))

        token = secrets.token_hex(8)
        cases = [
            make_dynamic_case(token + "a", [91, 17, 240, 33, 8, 150, 61], [1, 0, 8, 2, 0, 5, 3]),
            make_dynamic_case(token + "b", [13, 77, 29, 310, 46, 9, 125, 58], [0, 7, 1, 12, 3, 0, 5, 2]),
        ]
        for dynamic_metadata, dynamic_dependencies in cases:
            with open(METADATA_PATH, "w") as handle:
                json.dump(dynamic_metadata, handle)
            with open(DEPENDENCIES_PATH, "w") as handle:
                json.dump(dynamic_dependencies, handle)
            query_and_assert(expected_result(dynamic_metadata, dynamic_dependencies))
    finally:
        with open(METADATA_PATH, "wb") as handle:
            handle.write(original_metadata_bytes)
        with open(DEPENDENCIES_PATH, "wb") as handle:
            handle.write(original_dependencies_bytes)

    # The service launched by launch.sh must remain available after fixture restoration.
    assert process.poll() is None or requests.get(URL, timeout=2).status_code == 200
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
