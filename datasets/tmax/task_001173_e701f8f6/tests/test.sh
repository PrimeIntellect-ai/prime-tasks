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
mkdir -p /logs/verifier

if (
set -e

# Stop any agent-supplied listener, then test the requested artifact itself.
python3 - <<'PY'
import os
import signal
import time

PORTS = {8080, 9001, 9002}

def listener_inodes():
    result = set()
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == '0A':
                        port = int(fields[1].rsplit(':', 1)[1], 16)
                        if port in PORTS:
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result

inodes = listener_inodes()
for entry in os.listdir('/proc'):
    if not entry.isdigit():
        continue
    fd_dir = f'/proc/{entry}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(entry), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except (FileNotFoundError, PermissionError):
        pass

time.sleep(0.5)
PY

# Replace the predictable build-time graph with a fresh graph of the same size
# and schema. The official services will expose this graph to the submission.
python3 - <<'PY'
import json
import secrets

rng = secrets.SystemRandom()
types = ['Dataset', 'Paper', 'Author']
nodes = [{'id': i, 'type': rng.choice(types)} for i in range(1, 101)]
edges = set()
while len(edges) < 150:
    u = rng.randint(1, 100)
    v = rng.randint(1, 100)
    if u != v:
        edges.add((min(u, v), max(u, v)))
with open('/app/services/ground_truth.json', 'w') as f:
    json.dump({'nodes': nodes, 'edges': [list(e) for e in sorted(edges)]}, f)
PY

/app/services/start_services.sh >/tmp/verifier_services.log 2>&1
python3 - <<'PY'
import socket
import time
import urllib.request

end = time.time() + 10
while time.time() < end:
    try:
        with urllib.request.urlopen('http://127.0.0.1:9001/metadata', timeout=0.5) as r:
            if r.status == 200:
                break
    except Exception:
        time.sleep(0.1)
else:
    raise AssertionError('metadata service did not start')

end = time.time() + 10
while time.time() < end:
    try:
        with socket.create_connection(('127.0.0.1', 9002), timeout=0.5):
            break
    except OSError:
        time.sleep(0.1)
else:
    raise AssertionError('topology service did not start')
PY

# Require a compiled C++ artifact rather than a script or unrelated server.
test -f /home/user/graph_server
test -x /home/user/graph_server
python3 - <<'PY'
p = '/home/user/graph_server'
with open(p, 'rb') as f:
    data = f.read()
assert data[:4] == b'\x7fELF', 'graph_server is not an ELF executable'
assert any(marker in data for marker in (b'libstdc++.so', b'GLIBCXX_', b'CXXABI_')), \
    'graph_server does not appear to be a C++ executable'
PY

/home/user/graph_server >/tmp/graph_server.stdout 2>/tmp/graph_server.stderr &
SERVER_PID=$!
export SERVER_PID
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

python3 - <<'PY'
import os
import time
import urllib.request

end = time.time() + 10
while time.time() < end:
    if not os.path.exists(f'/proc/{os.environ["SERVER_PID"]}'):
        raise AssertionError('graph_server exited before serving requests')
    try:
        urllib.request.urlopen('http://127.0.0.1:8080/', timeout=0.5)
        break
    except urllib.error.HTTPError:
        break
    except Exception:
        time.sleep(0.1)
else:
    raise AssertionError('graph_server did not listen on port 8080')
PY

# Confirm that the launched artifact itself owns the listening socket.
python3 - <<'PY'
import os
pid = int(os.environ['SERVER_PID'])
inodes = set()
for path in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(path) as f:
            next(f)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[3] == '0A' and int(fields[1].rsplit(':', 1)[1], 16) == 8080:
                    inodes.add(fields[9])
    except FileNotFoundError:
        pass
assert inodes, 'no listener found on port 8080'
owned = False
for fd in os.listdir(f'/proc/{pid}/fd'):
    try:
        target = os.readlink(f'/proc/{pid}/fd/{fd}')
    except OSError:
        continue
    if target.startswith('socket:[') and target[8:-1] in inodes:
        owned = True
        break
assert owned, 'the launched graph_server process is not the serving process'
assert os.path.samefile(f'/proc/{pid}/exe', '/home/user/graph_server'), \
    'the serving process is not /home/user/graph_server'
PY

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest
import requests
from collections import defaultdict

GROUND_TRUTH_PATH = "/app/services/ground_truth.json"
BASE_URL = "http://127.0.0.1:8080"

@pytest.fixture(scope="module")
def graph_data():
    assert os.path.isfile(GROUND_TRUTH_PATH), f"Ground truth file missing at {GROUND_TRUTH_PATH}"
    with open(GROUND_TRUTH_PATH, "r") as f:
        data = json.load(f)

    nodes = {node["id"]: node["type"] for node in data["nodes"]}
    adj = defaultdict(set)
    for edge in data["edges"]:
        if isinstance(edge, list):
            u, v = edge[0], edge[1]
        else:
            u, v = edge["source"], edge["target"]
        adj[u].add(v)
        adj[v].add(u)

    visited = set()
    component_sizes = {}
    for node in nodes:
        if node not in visited:
            comp = set()
            stack = [node]
            while stack:
                curr = stack.pop()
                if curr not in comp:
                    comp.add(curr)
                    stack.extend(adj[curr] - comp)
            for n in comp:
                component_sizes[n] = len(comp)
            visited.update(comp)

    return {"nodes": nodes, "adj": adj, "component_sizes": component_sizes}

def test_server_running():
    try:
        requests.get(f"{BASE_URL}/", timeout=2)
    except requests.exceptions.RequestException:
        pytest.fail(f"Could not connect to the C++ server at {BASE_URL}. Is it running?")

def test_degree_endpoint(graph_data):
    for node_id in graph_data["nodes"]:
        expected_degree = len(graph_data["adj"][node_id])
        url = f"{BASE_URL}/analytics/degree?node={node_id}"
        try:
            resp = requests.get(url, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Request to {url} failed: {e}")
        assert resp.status_code == 200, f"Expected status 200 for {url}, got {resp.status_code}"
        data = resp.json()
        assert "node" in data and data["node"] == node_id, f"Invalid node ID in response: {data}"
        assert "degree" in data and data["degree"] == expected_degree, f"Expected degree {expected_degree} for node {node_id}, got {data.get('degree')}"

def test_component_size_endpoint(graph_data):
    for node_id in graph_data["nodes"]:
        expected_size = graph_data["component_sizes"][node_id]
        url = f"{BASE_URL}/analytics/component_size?node={node_id}"
        try:
            resp = requests.get(url, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Request to {url} failed: {e}")
        assert resp.status_code == 200, f"Expected status 200 for {url}, got {resp.status_code}"
        data = resp.json()
        assert "node" in data and data["node"] == node_id, f"Invalid node ID in response: {data}"
        assert "component_size" in data and data["component_size"] == expected_size, f"Expected component size {expected_size} for node {node_id}, got {data.get('component_size')}"

def test_query_endpoint(graph_data):
    for node_id in graph_data["nodes"]:
        for target_type in ["Dataset", "Paper", "Author"]:
            expected_results = sorted(
                n for n in graph_data["adj"][node_id]
                if graph_data["nodes"][n] == target_type
            )
            query_str = f"MATCH (a)-[]-(b) WHERE a.id = {node_id} AND b.type = '{target_type}' RETURN b.id"
            try:
                resp = requests.post(f"{BASE_URL}/query", json={"query": query_str}, timeout=2)
            except requests.exceptions.RequestException as e:
                pytest.fail(f"POST request to {BASE_URL}/query failed: {e}")
            assert resp.status_code == 200, f"Expected status 200 for /query, got {resp.status_code}"
            data = resp.json()
            assert "results" in data, f"Missing 'results' key in response: {data}"
            assert data["results"] == expected_results, f"Expected results {expected_results} for query '{query_str}', got {data['results']}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
