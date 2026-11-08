#!/bin/bash
mkdir -p /logs/verifier

PROJECT=/home/user/aggregate_service
HIER=/home/user/data/hierarchy.csv
VALUES=/home/user/data/values.csv
BACKUP_DIR=/tmp/aggregate_verifier_backup
RUN_PID=""
BACKED_UP=0

stop_listener() {
python3 <<'PY'
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) < 10:
                    continue
                local = fields[1]
                state = fields[3]
                try:
                    port = int(local.rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if port == 8080 and state == "0A":
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass

pids = set()
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
                pids.add(int(name))
                break
    except OSError:
        continue

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

time.sleep(0.5)
for pid in pids:
    try:
        os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
PY
}

cleanup() {
    stop_listener >/dev/null 2>&1 || true
    if [ -n "$RUN_PID" ]; then
        kill "$RUN_PID" >/dev/null 2>&1 || true
        wait "$RUN_PID" >/dev/null 2>&1 || true
    fi
    if [ "$BACKED_UP" = 1 ]; then
        cp "$BACKUP_DIR/hierarchy.csv" "$HIER" >/dev/null 2>&1 || true
        cp "$BACKUP_DIR/values.csv" "$VALUES" >/dev/null 2>&1 || true
        cd "$PROJECT" >/dev/null 2>&1 && nohup cargo run --quiet >/tmp/aggregate_service_restored.log 2>&1 &
    fi
}

run_verification() {
    test -f "$PROJECT/Cargo.toml" || return 1
    test -d "$PROJECT/src" || return 1

    cargo metadata --manifest-path "$PROJECT/Cargo.toml" --no-deps --format-version 1 > /tmp/aggregate_metadata.json || return 1
    python3 <<'PY' || return 1
import json
from pathlib import Path

project = Path("/home/user/aggregate_service").resolve()
with open("/tmp/aggregate_metadata.json") as f:
    metadata = json.load(f)

packages = [p for p in metadata.get("packages", [])
            if Path(p["manifest_path"]).resolve() == project / "Cargo.toml"]
assert packages, "Cargo metadata contains no package for aggregate_service"
assert any(
    "bin" in target.get("kind", [])
    and target.get("src_path", "").endswith(".rs")
    for package in packages
    for target in package.get("targets", [])
), "aggregate_service must contain a Rust binary target"
PY

    cargo build --manifest-path "$PROJECT/Cargo.toml" || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer analyst_token_99"}

EXPECTED_VALUES = {
    1: 450,
    2: 100,
    3: 250,
    4: 25,
    5: 25,
    6: 150
}

def test_missing_auth():
    try:
        response = requests.get(f"{BASE_URL}/aggregate/1", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code in [401, 403], f"Expected 401 or 403 for missing auth, got {response.status_code}"

@pytest.mark.parametrize("node_id, expected_sum", EXPECTED_VALUES.items())
def test_aggregate_endpoint(node_id, expected_sum):
    try:
        response = requests.get(f"{BASE_URL}/aggregate/{node_id}", headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code == 200, f"Expected 200 OK for node {node_id}, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "node" in data, f"Missing 'node' in response JSON: {data}"
    assert "total_value" in data, f"Missing 'total_value' in response JSON: {data}"

    assert data["node"] == node_id, f"Expected node {node_id}, got {data['node']}"
    assert data["total_value"] == expected_sum, f"Expected total_value {expected_sum} for node {node_id}, got {data['total_value']}"

def test_invalid_auth():
    try:
        response = requests.get(f"{BASE_URL}/aggregate/1", headers={"Authorization": "Bearer invalid_token"}, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")

    assert response.status_code in [401, 403], f"Expected 401 or 403 for invalid auth, got {response.status_code}"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR" || return 1
    cp "$HIER" "$BACKUP_DIR/hierarchy.csv" || return 1
    cp "$VALUES" "$BACKUP_DIR/values.csv" || return 1
    BACKED_UP=1

    stop_listener || return 1

    python3 <<'PY' || return 1
import secrets

nodes = secrets.SystemRandom().sample(range(1000, 9000), 18)
rng = secrets.SystemRandom()
values = {node: rng.randint(7, 500) for node in nodes}

# Keep two roots and attach every later node to an earlier node, producing a forest
# with multiple levels while avoiding cycles.
edges = []
for index in range(2, len(nodes)):
    parent = rng.choice(nodes[:index])
    edges.append((parent, nodes[index]))

with open("/home/user/data/hierarchy.csv", "w") as f:
    f.write("parent_id,child_id\n")
    for parent, child in edges:
        f.write(f"{parent},{child}\n")

with open("/home/user/data/values.csv", "w") as f:
    f.write("node_id,value\n")
    for node, value in values.items():
        f.write(f"{node},{value}\n")
PY

    cd "$PROJECT" || return 1
    cargo run --quiet >/tmp/aggregate_service_dynamic.log 2>&1 &
    RUN_PID=$!
    cd - >/dev/null || return 1

    python3 <<'PY' || return 1
import csv
import time
import requests

with open("/home/user/data/values.csv", newline="") as f:
    node = next(csv.DictReader(f))["node_id"]

url = f"http://127.0.0.1:8080/aggregate/{node}"
deadline = time.time() + 10
last_error = None
while time.time() < deadline:
    try:
        response = requests.get(url, headers={"Authorization": "Bearer analyst_token_99"}, timeout=0.5)
        if response.status_code == 200:
            raise SystemExit(0)
        last_error = f"HTTP {response.status_code}: {response.text}"
    except requests.RequestException as exc:
        last_error = str(exc)
    time.sleep(0.1)
raise AssertionError(f"Rust service did not become ready: {last_error}")
PY

    cat <<'DYNAMIC_EOF' > /tmp/test_dynamic_state.py
import csv
from collections import defaultdict

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer analyst_token_99"}

values = {}
with open("/home/user/data/values.csv", newline="") as f:
    for row in csv.DictReader(f):
        values[int(row["node_id"])] = int(row["value"])

children = defaultdict(list)
with open("/home/user/data/hierarchy.csv", newline="") as f:
    for row in csv.DictReader(f):
        children[int(row["parent_id"])].append(int(row["child_id"]))

def expected_total(node):
    total = 0
    stack = [node]
    seen = set()
    while stack:
        current = stack.pop()
        assert current not in seen, "generated hierarchy unexpectedly contains a cycle"
        seen.add(current)
        total += values.get(current, 0)
        stack.extend(children[current])
    return total

@pytest.mark.parametrize("node_id", list(values))
def test_generated_aggregate(node_id):
    response = requests.get(
        f"{BASE_URL}/aggregate/{node_id}",
        headers=AUTH_HEADER,
        timeout=2,
    )
    assert response.status_code == 200, response.text
    assert response.json() == {
        "node": node_id,
        "total_value": expected_total(node_id),
    }
DYNAMIC_EOF

    python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short || return 1
    return 0
}

if run_verification; then
    RESULT=1
else
    RESULT=0
fi

cleanup
echo "$RESULT" > /logs/verifier/reward.txt
