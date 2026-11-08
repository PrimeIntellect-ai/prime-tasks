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
import importlib.metadata
import json
import os
import signal
import subprocess
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
DATA_PATH = "/app/data/backups.json"
PORT_HEX = format(8080, "04X")


@pytest.fixture(scope="module")
def auth_token():
    token_path = "/app/config/auth_token.txt"
    assert os.path.isfile(token_path), f"Auth token file missing: {token_path}"
    with open(token_path, "r") as f:
        return f.read().strip()


@pytest.fixture(scope="module")
def auth_headers(auth_token):
    return {"Authorization": f"Bearer {auth_token}"}


def request(method, path, **kwargs):
    try:
        return requests.request(method, f"{BASE_URL}{path}", timeout=3, **kwargs)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {path}: {e}")


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10:
                local = fields[1]
                state = fields[3]
                if local.rsplit(":", 1)[-1].upper() == PORT_HEX and state == "0A":
                    inodes.add(fields[9])

    found = set()
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
                    found.add(int(name))
                    break
        except OSError:
            continue
    return found


def process_spec(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [x.decode(errors="surrogateescape") for x in f.read().split(b"\0") if x]
    assert argv, f"Could not determine command for listener PID {pid}"
    exe = os.readlink(f"/proc/{pid}/exe")
    cwd = os.readlink(f"/proc/{pid}/cwd")
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    env = os.environ.copy()
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return {"argv": argv, "exe": exe, "cwd": cwd, "env": env}


def stop_listener():
    deadline = time.time() + 5
    while time.time() < deadline:
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.2)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids() and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(), "Could not stop the service listening on port 8080"


def start_service(spec):
    log = open("/home/user/service.log", "ab", buffering=0)
    try:
        subprocess.Popen(
            spec["argv"],
            executable=spec["exe"],
            cwd=spec["cwd"],
            env=spec["env"],
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    finally:
        log.close()

    deadline = time.time() + 12
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(f"{BASE_URL}/health", timeout=0.5)
            if response.status_code == 200:
                return
        except requests.RequestException as e:
            last_error = e
        time.sleep(0.2)
    pytest.fail(f"Service did not restart successfully: {last_error}")


def test_setup_py_fixed():
    setup_path = "/app/backup_graph_lib-1.0.0/setup.py"
    assert os.path.isfile(setup_path), f"File missing: {setup_path}"
    with open(setup_path, "r") as f:
        content = f.read()
    assert "networkkxx" not in content, "The deliberate perturbation 'networkkxx' is still in setup.py"
    assert "networkx" in content, "The dependency 'networkx' is missing in setup.py"


def test_vendored_package_installed():
    assert importlib.metadata.version("backup_graph_lib") == "1.0.0"
    module = importlib.import_module("backup_graph_lib")
    assert module is not None


def test_health_endpoint():
    resp = request("GET", "/health")
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    data = resp.json()
    assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"


def test_auth_required():
    resp = request("GET", "/critical_nodes")
    assert resp.status_code == 401, f"Expected 401 Unauthorized without auth, got {resp.status_code}"

    for method, path, kwargs in (
        ("GET", "/window_top_backups", {}),
        ("POST", "/aggregate", {"json": {"match": {"region": "us-east"}, "sum": "size_mb"}}),
    ):
        unauth = request(method, path, **kwargs)
        assert unauth.status_code == 401, f"Expected 401 for unauthenticated {path}, got {unauth.status_code}"
        bad = request(method, path, headers={"Authorization": "Bearer wrong-token"}, **kwargs)
        assert bad.status_code == 401, f"Expected 401 for invalid token on {path}, got {bad.status_code}"


def test_critical_nodes(auth_headers):
    resp = request("GET", "/critical_nodes", headers=auth_headers)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    data = resp.json()
    assert "critical_nodes" in data, f"Missing 'critical_nodes' in response: {data}"
    nodes = data["critical_nodes"]
    assert len(nodes) == 3, f"Expected exactly 3 nodes, got {len(nodes)}"
    assert nodes[0] == "b1", f"Expected 'b1' as most critical, got {nodes[0]}"
    assert nodes[1] == "b4", f"Expected 'b4' as second most critical, got {nodes[1]}"
    assert nodes[2] in ["b2", "b3", "b5"], f"Expected 3rd node to be one of b2, b3, b5, got {nodes[2]}"


def test_window_top_backups(auth_headers):
    resp = request("GET", "/window_top_backups", headers=auth_headers)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    data = resp.json()
    assert "top_backups" in data, f"Missing 'top_backups' in response: {data}"
    top = data["top_backups"]
    assert "us-east" in top, "Missing 'us-east' in top_backups"
    assert "us-west" in top, "Missing 'us-west' in top_backups"
    assert top["us-east"] == ["b2", "b1"], f"Expected ['b2', 'b1'] for us-east, got {top['us-east']}"
    assert top["us-west"] == ["b5", "b4"], f"Expected ['b5', 'b4'] for us-west, got {top['us-west']}"


def test_aggregate(auth_headers):
    resp = request("POST", "/aggregate", json={"match": {"region": "us-west"}, "sum": "size_mb"}, headers=auth_headers)
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    data = resp.json()
    assert "result" in data, f"Missing 'result' in response: {data}"
    assert data["result"] == 500, f"Expected sum 500 for us-west, got {data['result']}"

    resp2 = request("POST", "/aggregate", json={"match": {"region": "us-east"}, "sum": "size_mb"}, headers=auth_headers)
    assert resp2.status_code == 200, f"Expected 200 OK, got {resp2.status_code}"
    data2 = resp2.json()
    assert data2["result"] == 300, f"Expected sum 300 for us-east, got {data2['result']}"


def test_analysis_uses_current_backup_data(auth_headers):
    suffix = uuid.uuid4().hex[:10]
    ids = [f"node_{suffix}_{i}" for i in range(8)]
    regions = [f"region_{suffix}_a", f"region_{suffix}_b", f"region_{suffix}_c"]
    sizes = [41, 307, 119, 503, 211, 89, 431, 173]
    nodes = [
        {"backup_id": ids[i], "region": regions[i % 3], "size_mb": sizes[i],
         "timestamp": f"2025-01-{i + 1:02d}T00:00:00Z"}
        for i in range(8)
    ]
    edges = []
    for source in ids[3:8]:
        edges.append({"source": source, "target": ids[0]})
    for source in ids[4:8]:
        edges.append({"source": source, "target": ids[1]})
    for source in ids[5:8]:
        edges.append({"source": source, "target": ids[2]})
    dynamic_data = {"nodes": nodes, "edges": edges}

    expected_top = {}
    for region in regions:
        members = [n for n in nodes if n["region"] == region]
        members.sort(key=lambda n: n["size_mb"], reverse=True)
        expected_top[region] = [n["backup_id"] for n in members[:2]]
    expected_sums = {
        region: sum(n["size_mb"] for n in nodes if n["region"] == region)
        for region in regions
    }

    with open(DATA_PATH, "rb") as f:
        original = f.read()
    pids = listener_pids()
    assert pids, "No process is listening on port 8080"
    spec = process_spec(next(iter(pids)))

    try:
        stop_listener()
        with open(DATA_PATH, "w") as f:
            json.dump(dynamic_data, f)
        start_service(spec)

        critical = request("GET", "/critical_nodes", headers=auth_headers)
        assert critical.status_code == 200
        assert critical.json().get("critical_nodes") == ids[:3]

        windowed = request("GET", "/window_top_backups", headers=auth_headers)
        assert windowed.status_code == 200
        assert windowed.json().get("top_backups") == expected_top

        for region, expected in expected_sums.items():
            aggregate = request(
                "POST",
                "/aggregate",
                headers=auth_headers,
                json={"match": {"region": region}, "sum": "size_mb"},
            )
            assert aggregate.status_code == 200
            assert aggregate.json().get("result") == expected
    finally:
        try:
            stop_listener()
        finally:
            with open(DATA_PATH, "wb") as f:
                f.write(original)
            start_service(spec)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
