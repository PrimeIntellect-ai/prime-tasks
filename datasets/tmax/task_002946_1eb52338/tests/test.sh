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
set +e
mkdir -p /logs/verifier

APP=/app/graph_engine_rs
NODES=/home/user/data/nodes.csv
EDGES=/home/user/data/edges.csv
BIN="$APP/target/release/graph_engine_rs"
BACKUP_DIR=$(mktemp -d)
cp "$NODES" "$BACKUP_DIR/nodes.csv"
cp "$EDGES" "$BACKUP_DIR/edges.csv"

kill_port_8080() {
python3 <<'PY'
import os, signal, time
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[3] == '0A' and int(fields[1].rsplit(':', 1)[1], 16) == 8080:
                    inodes.add(fields[9])
    except OSError:
        pass
pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
                break
    except OSError:
        pass
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(0.4)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
}

wait_for_server() {
    local pid="$1"
    local attempts="${2:-100}"
    for ((i=0; i<attempts; i++)); do
        kill -0 "$pid" 2>/dev/null || return 1
        if curl -fsS --max-time 1 'http://127.0.0.1:8080/centrality?node=__verifier_probe__' >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

check_process_and_bind() {
    local pid="$1"
    python3 - "$pid" "$NODES" "$EDGES" <<'PY'
import os, sys
pid, nodes, edges = sys.argv[1:]
with open(f'/proc/{pid}/cmdline', 'rb') as f:
    argv = [x.decode() for x in f.read().split(b'\0') if x]
assert len(argv) == 3, argv
assert os.path.realpath(argv[1]) == os.path.realpath(nodes), argv
assert os.path.realpath(argv[2]) == os.path.realpath(edges), argv
found = False
with open('/proc/net/tcp') as f:
    next(f)
    for line in f:
        fields = line.split()
        host, port = fields[1].split(':')
        if fields[3] == '0A' and int(port, 16) == 8080 and host == '00000000':
            found = True
assert found, 'port 8080 is not listening on exactly IPv4 0.0.0.0'
PY
}

cat > /tmp/test_original_state.py <<'PY'
import requests
import pytest

def test_shortest_path():
    try:
        resp = requests.get("http://127.0.0.1:8080/shortest_path?from=u1&to=u4", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at 127.0.0.1:8080: {e}")
    assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert "path" in data, f"Response missing 'path' key. Got: {data}"
    path = data["path"]
    assert isinstance(path, list), f"Expected 'path' to be a list, got {type(path)}"
    assert len(path) == 3, f"Expected shortest path of length 3, got {len(path)}: {path}"
    assert path[0] == "u1", f"Path must start with 'u1', got {path[0]}"
    assert path[-1] == "u4", f"Path must end with 'u4', got {path[-1]}"
    assert path[1] in ["u2", "u3"], f"Invalid intermediate node in path: {path[1]}. Must be 'u2' or 'u3'."

def test_centrality():
    try:
        resp = requests.get("http://127.0.0.1:8080/centrality?node=u1", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at 127.0.0.1:8080: {e}")
    assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert "out_degree" in data, f"Response missing 'out_degree' key. Got: {data}"
    assert data["out_degree"] == 2, f"Expected out_degree 2 for node 'u1', got {data['out_degree']}"
PY

verify() (
    set -e
    test -f "$APP/Cargo.toml"
    test -f "$APP/src/graph.rs"
    test -f "$APP/src/main.rs"

    cd "$APP"
    cargo metadata --format-version 1 --no-deps > /tmp/graph_metadata.json
    python3 <<'PY'
import json, os
m = json.load(open('/tmp/graph_metadata.json'))
packages = [p for p in m['packages'] if p['name'] == 'graph_engine_rs']
assert len(packages) == 1
p = packages[0]
assert os.path.realpath(p['manifest_path']) == '/app/graph_engine_rs/Cargo.toml'
deps = {d['name'] for d in p['dependencies']}
assert {'serde', 'serde_json', 'tokio', 'axum', 'csv'} <= deps, deps
PY
    cargo build --release
    test -x "$BIN"

    kill_port_8080
    "$BIN" "$NODES" "$EDGES" >/tmp/graph_original.log 2>&1 &
    pid=$!
    wait_for_server "$pid" 100
    check_process_and_bind "$pid"
    python3 -m pytest /tmp/test_original_state.py -x --tb=short
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    kill_port_8080

    python3 <<'PY'
import csv, secrets, random
nodes_path = '/home/user/data/nodes.csv'
edges_path = '/home/user/data/edges.csv'
token = secrets.token_hex(8)
n = 30000
ids = [f'{token}_{i}' for i in range(n)]
rng = random.Random(int(token, 16))
edges = [(ids[i], ids[i + 1]) for i in range(n - 1)]
seen = set(edges)
while len(edges) < 45000:
    a = rng.randrange(0, n - 2)
    b = rng.randrange(a + 1, min(n, a + 800))
    e = (ids[a], ids[b])
    if e not in seen:
        seen.add(e)
        edges.append(e)
with open(nodes_path, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['id', 'name'])
    for i, node in enumerate(ids):
        w.writerow([node, f'name_{i}'])
with open(edges_path, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['source', 'target'])
    w.writerows(edges)
with open('/tmp/generated_token', 'w') as f:
    f.write(token)
PY

    "$BIN" "$NODES" "$EDGES" >/tmp/graph_generated.log 2>&1 &
    pid=$!
    # An O(E) implementation starts quickly here; the defective O(V*E) construction does not.
    wait_for_server "$pid" 120
    check_process_and_bind "$pid"

    python3 <<'PY'
import csv
from collections import defaultdict, deque
import requests

token = open('/tmp/generated_token').read().strip()
nodes = []
with open('/home/user/data/nodes.csv', newline='') as f:
    for row in csv.DictReader(f):
        nodes.append(row['id'])
adj = defaultdict(list)
with open('/home/user/data/edges.csv', newline='') as f:
    for row in csv.DictReader(f):
        adj[row['source']].append(row['target'])

def expected_path(start, end):
    q = deque([start])
    parent = {start: start}
    while q:
        cur = q.popleft()
        if cur == end:
            out = [cur]
            while cur != start:
                cur = parent[cur]
                out.append(cur)
            return list(reversed(out))
        for nxt in adj.get(cur, []):
            if nxt not in parent:
                parent[nxt] = cur
                q.append(nxt)
    return []

for i in [0, 1, 17, 499, 5000, 15000, 29998, 29999]:
    node = nodes[i]
    r = requests.get('http://127.0.0.1:8080/centrality', params={'node': node}, timeout=4)
    assert r.status_code == 200, r.text
    body = r.json()
    assert isinstance(body.get('out_degree'), int), body
    assert body['out_degree'] == len(adj.get(node, [])), (node, body, len(adj.get(node, [])))
r = requests.get('http://127.0.0.1:8080/centrality', params={'node': token + '_missing'}, timeout=4)
assert r.status_code == 200 and r.json().get('out_degree') == 0, r.text

pairs = [
    (nodes[0], nodes[500]),
    (nodes[123], nodes[1800]),
    (nodes[7000], nodes[7600]),
    (nodes[29999], nodes[10]),
    (nodes[4242], nodes[4242]),
    (token + '_missing', nodes[0]),
]
for start, end in pairs:
    expected = expected_path(start, end)
    r = requests.get('http://127.0.0.1:8080/shortest_path', params={'from': start, 'to': end}, timeout=6)
    assert r.status_code == 200, r.text
    body = r.json()
    assert isinstance(body.get('path'), list), body
    assert body['path'] == expected, (start, end, body['path'], expected)
PY

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
)

if verify; then
    result=1
else
    result=0
fi

kill_port_8080
cp "$BACKUP_DIR/nodes.csv" "$NODES"
cp "$BACKUP_DIR/edges.csv" "$EDGES"
rm -rf "$BACKUP_DIR"

# Restore the required final state and verify that the submitted binary still serves the specified files.
if [ -x "$BIN" ]; then
    nohup "$BIN" "$NODES" "$EDGES" >/tmp/graph_engine_final.log 2>&1 &
    final_pid=$!
    if ! wait_for_server "$final_pid" 100 || ! check_process_and_bind "$final_pid"; then
        result=0
    elif ! python3 -m pytest /tmp/test_original_state.py -x --tb=short >/tmp/final_pytest.log 2>&1; then
        result=0
    fi
else
    result=0
fi

echo "$result" > /logs/verifier/reward.txt
exit 0
