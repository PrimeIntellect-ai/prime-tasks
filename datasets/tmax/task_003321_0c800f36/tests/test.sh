#!/bin/bash
set -u
mkdir -p /logs/verifier

SCORE=0
SERVER_PGID=""
BACKUP_DIR="$(mktemp -d)"
cp -a /app/network.csv "$BACKUP_DIR/network.csv" 2>/dev/null || true
cp -a /app/target_node.png "$BACKUP_DIR/target_node.png" 2>/dev/null || true

cleanup() {
    if [ -n "$SERVER_PGID" ]; then
        kill -- -"$SERVER_PGID" 2>/dev/null || true
        sleep 1
        kill -9 -- -"$SERVER_PGID" 2>/dev/null || true
    fi
    [ -f "$BACKUP_DIR/network.csv" ] && cp -a "$BACKUP_DIR/network.csv" /app/network.csv 2>/dev/null || true
    [ -f "$BACKUP_DIR/target_node.png" ] && cp -a "$BACKUP_DIR/target_node.png" /app/target_node.png 2>/dev/null || true
    rm -rf "$BACKUP_DIR"
    echo "$SCORE" > /logs/verifier/reward.txt
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_original_state.py
import requests
import pytest

BASE_URL = "http://127.0.0.1:8080"

def get(depth):
    try:
        response = requests.get(f"{BASE_URL}/reachable?depth={depth}", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

def test_reachable_depth_0():
    data = get(0)
    assert data == ["N-8392"], f"Expected ['N-8392'], got {data}"

def test_reachable_depth_1():
    data = get(1)
    assert data == ["N-1000", "N-8392"], f"Expected ['N-1000', 'N-8392'], got {data}"

def test_reachable_depth_2():
    data = get(2)
    assert data == ["N-1000", "N-2000", "N-3000", "N-8392"], f"Expected ['N-1000', 'N-2000', 'N-3000', 'N-8392'], got {data}"

def test_reachable_depth_3():
    data = get(3)
    assert data == ["N-1000", "N-2000", "N-3000", "N-4000", "N-8392"], f"Expected ['N-1000', 'N-2000', 'N-3000', 'N-4000', 'N-8392'], got {data}"
TEST_EOF

python3 -m pytest /tmp/test_original_state.py -x --tb=short >/tmp/original-tests.log 2>&1 || exit 0

# Require an actual buildable Rust project, rather than accepting an arbitrary
# process that happened to be listening on the expected port.
[ -f /app/graph_service/Cargo.toml ] || exit 0
find /app/graph_service -type f -name '*.rs' -print -quit | grep -q . || exit 0
timeout 180 cargo build --manifest-path /app/graph_service/Cargo.toml >/tmp/cargo-build.log 2>&1 || exit 0

# Stop the submitted instance so it can be restarted against fresh, unpredictable
# input files. Locate the listener through /proc instead of relying on extra tools.
python3 << 'PY'
import os, signal, time

def listeners():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[3] == '0A' and fields[1].rsplit(':', 1)[-1].upper() == '1F90':
                inodes.add(fields[9])
    pids = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            for fd in os.listdir(f'/proc/{entry}/fd'):
                try:
                    link = os.readlink(f'/proc/{entry}/fd/{fd}')
                except OSError:
                    continue
                if link.startswith('socket:[') and link[8:-1] in inodes:
                    pids.add(int(entry))
        except OSError:
            pass
    return pids

for sig in (signal.SIGTERM, signal.SIGKILL):
    pids = listeners()
    if not pids:
        break
    for pid in pids:
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass
    time.sleep(1)
PY

# Generate a new target and graph using verifier-time randomness. The expected
# answers are subsequently derived from these files by an independent traversal.
python3 << 'PY'
import csv, json, secrets

used = set()
def node():
    while True:
        value = f"N-{secrets.randbelow(9000) + 1000}"
        if value not in used and value != 'N-8392':
            used.add(value)
            return value

target = node()
nodes = [target] + [node() for _ in range(13)]
chain_len = 6 + secrets.randbelow(4)
edges = [(nodes[i], nodes[i + 1]) for i in range(chain_len)]
edges += [
    (nodes[0], nodes[chain_len + 1]),
    (nodes[chain_len + 1], nodes[3]),
    (nodes[2], nodes[chain_len + 2]),
    (nodes[chain_len + 2], nodes[chain_len + 3]),
    (nodes[4], nodes[1]),
    (nodes[-1], target),
]
with open('/app/network.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['src', 'dst'])
    w.writerows(edges)
with open('/tmp/mutated_case.json', 'w') as f:
    json.dump({'target': target, 'depths': list(range(chain_len + 3))}, f)
PY

TARGET="$(python3 -c 'import json; print(json.load(open("/tmp/mutated_case.json"))["target"])')"
convert -size 260x70 xc:white -font DejaVu-Sans -pointsize 30 -fill black -draw "text 25,46 '$TARGET'" /app/target_node.png >/tmp/convert.log 2>&1 || exit 0

cd /app/graph_service || exit 0
setsid cargo run --quiet >/tmp/graph-service.log 2>&1 &
SERVER_PGID=$!
cd / || exit 0

READY=0
for _ in $(seq 1 60); do
    if curl -fsS --max-time 1 'http://127.0.0.1:8080/reachable?depth=0' >/dev/null 2>&1; then
        READY=1
        break
    fi
    if ! kill -0 "$SERVER_PGID" 2>/dev/null; then
        break
    fi
    sleep 0.5
done
[ "$READY" -eq 1 ] || exit 0

cat << 'TEST_EOF' > /tmp/test_mutated_state.py
import csv
import json
from collections import defaultdict

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
case = json.load(open('/tmp/mutated_case.json'))
target = case['target']
graph = defaultdict(list)
with open('/app/network.csv', newline='') as f:
    for row in csv.DictReader(f):
        graph[row['src']].append(row['dst'])

def expected(depth):
    seen = {target}
    frontier = {target}
    for _ in range(depth):
        nxt = {dst for src in frontier for dst in graph.get(src, ()) if dst not in seen}
        seen.update(nxt)
        frontier = nxt
    return sorted(seen)

@pytest.mark.parametrize('depth', case['depths'])
def test_fresh_graph(depth):
    try:
        response = requests.get(f"{BASE_URL}/reachable?depth={depth}", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to restarted service: {e}")
    assert response.status_code == 200, response.text
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert isinstance(data, list)
    assert all(isinstance(item, str) for item in data)
    assert data == sorted(data)
    assert data == expected(depth)
TEST_EOF

python3 -m pytest /tmp/test_mutated_state.py -x --tb=short >/tmp/mutated-tests.log 2>&1 || exit 0
SCORE=1
exit 0
