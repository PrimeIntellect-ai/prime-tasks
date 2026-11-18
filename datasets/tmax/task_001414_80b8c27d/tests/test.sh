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
import os
import random
import re
import shutil
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

import pytest
import requests

API_URL = "http://127.0.0.1:9090"
AUTH_HEADER = {"Authorization": "Bearer DBRE-SEC-991"}
VIDEO = "/app/backup_topology.mp4"


def extract_edges_from_video():
    frame_dir = tempfile.mkdtemp(prefix="verifier_frames_")
    try:
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-i", VIDEO, "-vf", "fps=1", f"{frame_dir}/frame_%03d.png"],
            check=True,
        )
        edges = set()
        for frame in sorted(Path(frame_dir).glob("frame_*.png")):
            text = subprocess.run(
                ["tesseract", str(frame), "stdout", "--psm", "6"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
            ).stdout
            for line in text.splitlines():
                match = re.search(r"REPLICATE\s*:\s*([A-Za-z0-9_.-]+)\s*-\s*>\s*([A-Za-z0-9_.-]+)", line, re.I)
                if match:
                    edges.add((match.group(1), match.group(2)))
        assert edges, "Verifier could not extract any replication edges from the supplied video"
        return edges
    finally:
        shutil.rmtree(frame_dir, ignore_errors=True)


EDGES = extract_edges_from_video()
NODES = sorted({node for edge in EDGES for node in edge})
OUT_NEIGHBORS = defaultdict(set)
for source, target in EDGES:
    OUT_NEIGHBORS[source].add(target)
CENTRALITY = {
    node: (len(OUT_NEIGHBORS[node]) / (len(NODES) - 1) if len(NODES) > 1 else 0.0)
    for node in NODES
}


def expected_critical(limit=10, offset=0, minimum=0.0):
    ordered = sorted(
        ((node, value) for node, value in CENTRALITY.items() if value >= minimum),
        key=lambda item: (-item[1], item[0]),
    )
    return ordered[offset:offset + limit]


def expected_chain(start):
    reached = set()
    pending = list(OUT_NEIGHBORS[start])
    while pending:
        node = pending.pop()
        if node in reached:
            continue
        reached.add(node)
        pending.extend(OUT_NEIGHBORS[node] - reached)
    return sorted(reached)


def assert_critical_response(params, expected):
    resp = requests.get(f"{API_URL}/critical_nodes", headers=AUTH_HEADER, params=params, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"
    data = resp.json()
    assert isinstance(data, list), "Expected a JSON array"
    assert len(data) == len(expected), f"Expected {len(expected)} items, got {len(data)}"
    for item, (node, value) in zip(data, expected):
        assert isinstance(item, dict), f"Expected an object, got {item!r}"
        assert item.get("node") == node, f"Expected node {node}, got {item.get('node')}"
        assert isinstance(item.get("centrality"), (int, float)), f"Invalid centrality for {node}"
        assert abs(item["centrality"] - value) < 1e-5, f"Expected centrality {value}, got {item['centrality']}"


def test_api_pid_file():
    pid_file = "/home/user/api.pid"
    assert os.path.exists(pid_file), f"PID file not found at {pid_file}"
    with open(pid_file, "r") as f:
        pid = f.read().strip()
    assert pid.isdigit(), f"PID file does not contain a valid integer: {pid}"

    pid_number = int(pid)
    os.kill(pid_number, 0)
    socket_inodes = set()
    with open("/proc/net/tcp", "r") as tcp:
        for line in tcp.readlines()[1:]:
            fields = line.split()
            if fields[1] == "0100007F:2382" and fields[3] == "0A":
                socket_inodes.add(fields[9])
    assert socket_inodes, "No process is listening on 127.0.0.1:9090"

    owned = set()
    fd_dir = f"/proc/{pid_number}/fd"
    assert os.path.isdir(fd_dir), f"PID {pid_number} is not a running process"
    for fd in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, fd))
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            owned.add(match.group(1))
    assert socket_inodes & owned, f"PID {pid_number} does not own the API listening socket"


def test_auth_required():
    resp = requests.get(f"{API_URL}/critical_nodes", timeout=5)
    assert resp.status_code in (401, 403), f"Expected 401 or 403 for missing auth, got {resp.status_code}"

    bad_auth = {"Authorization": "Bearer BAD-TOKEN"}
    resp = requests.get(f"{API_URL}/critical_nodes", headers=bad_auth, timeout=5)
    assert resp.status_code in (401, 403), f"Expected 401 or 403 for bad auth, got {resp.status_code}"

    sample = NODES[0]
    resp = requests.get(f"{API_URL}/backup_chain/{sample}", timeout=5)
    assert resp.status_code in (401, 403), f"Expected backup_chain to require auth, got {resp.status_code}"
    resp = requests.get(f"{API_URL}/backup_chain/{sample}", headers=bad_auth, timeout=5)
    assert resp.status_code in (401, 403), f"Expected backup_chain to reject bad auth, got {resp.status_code}"


def test_critical_nodes():
    params = {"limit": 2, "offset": 1, "min_centrality": 0.1}
    resp = requests.get(f"{API_URL}/critical_nodes", headers=AUTH_HEADER, params=params, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"

    data = resp.json()
    assert isinstance(data, list), "Expected a JSON array"
    assert len(data) == 2, f"Expected 2 items, got {len(data)}"
    assert data[0]["node"] == "db-analytics-1", f"Expected db-analytics-1, got {data[0]['node']}"
    assert abs(data[0]["centrality"] - 0.2) < 1e-5, f"Expected centrality ~0.2, got {data[0]['centrality']}"
    assert data[1]["node"] == "db-replica-1", f"Expected db-replica-1, got {data[1]['node']}"
    assert abs(data[1]["centrality"] - 0.2) < 1e-5, f"Expected centrality ~0.2, got {data[1]['centrality']}"


def test_dynamic_filtering_sorting_and_pagination():
    assert_critical_response({}, expected_critical())

    values = sorted(set(CENTRALITY.values()))
    thresholds = [0.0, max(values) + 0.01]
    thresholds.extend(values)
    thresholds.extend(value + 1e-6 for value in values)

    rng = random.SystemRandom()
    for _ in range(16):
        limit = rng.randint(0, len(NODES) + 3)
        offset = rng.randint(0, len(NODES) + 2)
        minimum = rng.choice(thresholds)
        params = {"limit": limit, "offset": offset, "min_centrality": minimum}
        assert_critical_response(params, expected_critical(limit, offset, minimum))


def test_backup_chain():
    resp = requests.get(f"{API_URL}/backup_chain/db-primary", headers=AUTH_HEADER, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"

    data = resp.json()
    assert isinstance(data, list), "Expected a JSON array"
    expected_chain_value = ["db-analytics-1", "db-archive", "db-replica-1", "db-replica-2", "db-reporting"]
    assert data == expected_chain_value, f"Expected {expected_chain_value}, got {data}"


@pytest.mark.parametrize("node", NODES)
def test_all_backup_chains(node):
    resp = requests.get(f"{API_URL}/backup_chain/{node}", headers=AUTH_HEADER, timeout=5)
    assert resp.status_code == 200, f"Expected 200 for {node}, got {resp.status_code}. Body: {resp.text}"
    data = resp.json()
    assert isinstance(data, list), "Expected a JSON array"
    expected = expected_chain(node)
    assert data == expected, f"For {node}, expected {expected}, got {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
