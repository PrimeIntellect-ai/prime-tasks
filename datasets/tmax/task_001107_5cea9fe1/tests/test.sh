#!/bin/bash
set +e
mkdir -p /logs/verifier
SERVER_PID=""
SCORER_WRAPPED=0

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    if [ "$SCORER_WRAPPED" = "1" ] && [ -f /app/path_scorer.oracle ]; then
        rm -f /app/path_scorer
        mv /app/path_scorer.oracle /app/path_scorer
        chmod +x /app/path_scorer
    fi
}
trap cleanup EXIT

run_all() {
    test -f /home/user/server.go || return 1
    test ! -L /home/user/server.go || return 1

    # Stop whichever process currently owns the required listening port. The
    # submitted source is rebuilt and restarted below against hidden data.
    python3 - <<'PY' || return 1
import os, signal
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if fields[3] == '0A' and int(fields[1].rsplit(':', 1)[1], 16) == 9090:
            inodes.add(fields[9])
for pid in os.listdir('/proc'):
    if not pid.isdigit():
        continue
    try:
        for fd in os.listdir(f'/proc/{pid}/fd'):
            try:
                target = os.readlink(f'/proc/{pid}/fd/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except (OSError, ProcessLookupError, PermissionError):
        pass
PY
    sleep 1

    # Add unpredictable records before rebuilding, so a server which only
    # memorizes the public fixture cannot satisfy the tests.
    python3 - <<'PY' || return 1
import json, sqlite3, uuid
p = uuid.uuid4().hex
label = "Hidden_' OR 1=1 --_" + p
node_ids = [f"{p[:6]}_{suffix}" for suffix in ("z", "aa", "m333", "b22", "q", "ccccc", "d4")]
graph_ids = [f"g_{p[:10]}_{i}{'x' * i}" for i in range(7)]
isolated = f"iso_{p}"
conn = sqlite3.connect('/home/user/dataset.db')
conn.executemany('INSERT INTO nodes(id,label,name) VALUES (?,?,?)',
                 [(nid, label, f"Hidden name {i}") for i, nid in enumerate(node_ids)])
conn.executemany('INSERT INTO nodes(id,label,name) VALUES (?,?,?)',
                 [(nid, 'HiddenGraph_' + p, f"Graph {i}") for i, nid in enumerate(graph_ids)])
conn.execute('INSERT INTO nodes(id,label,name) VALUES (?,?,?)',
             (isolated, 'HiddenIsolated_' + p, 'Isolated'))
edges = [(0,1),(0,2),(1,3),(2,3),(3,4),(4,5),(3,6)]
conn.executemany('INSERT INTO edges(source,target,relation) VALUES (?,?,?)',
                 [(graph_ids[a], graph_ids[b], 'HIDDEN') for a,b in edges])
conn.commit()
conn.close()
with open('/tmp/api_challenge.json', 'w') as f:
    json.dump({'label': label, 'node_ids': node_ids, 'graph_ids': graph_ids,
               'isolated': isolated, 'missing': 'missing_' + p}, f)
PY

    cd /home/user || return 1
    timeout 90s go build -o /tmp/submitted_graph_server /home/user/server.go || return 1

    # Interpose a transparent logger around the required scorer. This verifies
    # that each returned path is actually passed to the proprietary utility.
    mv /app/path_scorer /app/path_scorer.oracle || return 1
    SCORER_WRAPPED=1
    cat > /app/path_scorer <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> /tmp/path_scorer_calls
exec /app/path_scorer.oracle "$@"
SH
    chmod +x /app/path_scorer
    : > /tmp/path_scorer_calls

    /tmp/submitted_graph_server >/tmp/submitted_graph_server.log 2>&1 &
    SERVER_PID=$!
    python3 - <<'PY' || return 1
import time, requests, sys
for _ in range(60):
    try:
        requests.get('http://127.0.0.1:9090/nodes',
                     params={'label':'Author','limit':1,'page':1}, timeout=.5)
        sys.exit(0)
    except requests.RequestException:
        time.sleep(.25)
sys.exit(1)
PY

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
from collections import deque

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"


def get_json(path, params, expected_status=200):
    try:
        response = requests.get(f"{BASE_URL}{path}", params=params, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}: {e}")
    assert response.status_code == expected_status, (
        f"Expected status code {expected_status}, got {response.status_code}. "
        f"Response: {response.text}")
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")


def assert_scorer_called(path):
    expected = " ".join(path)
    with open('/tmp/path_scorer_calls') as f:
        calls = [line.rstrip('\n') for line in f]
    assert expected in calls, f"The scorer was not invoked with path {path}; calls were {calls}"


def oracle_score(path):
    output = subprocess.check_output(['/app/path_scorer.oracle', *path], text=True).strip()
    return float(output)


def test_source_is_compilable_go_and_contains_required_integrations():
    assert os.path.isfile('/home/user/server.go') and not os.path.islink('/home/user/server.go')
    source = open('/home/user/server.go', encoding='utf-8').read()
    assert re.search(r'(?m)^\s*package\s+main\b', source)
    assert 'database/sql' in source
    assert 'sqlite3' in source
    assert '/home/user/dataset.db' in source
    assert '/app/path_scorer' in source
    assert re.search(r'\bexec\.Command(?:Context)?\s*\(', source)
    assert re.search(r'(?is)label\s*=\s*(?:\?|\$1)', source), "nodes label SQL must use a placeholder"


def test_nodes_endpoint():
    params = {"label": "Author", "limit": 1, "page": 2}
    data = get_json('/nodes', params)
    assert data.get("page") == 2, f"Expected page 2, got {data.get('page')}"
    assert data.get("limit") == 1, f"Expected limit 1, got {data.get('limit')}"
    results = data.get("results")
    assert isinstance(results, list), "Expected 'results' to be a list"
    assert len(results) == 1, f"Expected exactly 1 result, got {len(results)}"
    assert results[0].get("id") == "n2", f"Expected result id 'n2', got {results[0].get('id')}"
    assert results[0].get("name") == "Bob", f"Expected result name 'Bob', got {results[0].get('name')}"


def test_shortest_path_endpoint():
    data = get_json('/shortest-path', {"start": "n1", "end": "n4"})
    path = data.get("path")
    assert isinstance(path, list), "Expected 'path' to be a list"
    assert path == ["n1", "n3", "n4"], f"Expected path ['n1', 'n3', 'n4'], got {path}"
    score = data.get("score")
    assert isinstance(score, (float, int)), "Expected 'score' to be a number"
    assert abs(score - 0.6) < 0.001, f"Expected score around 0.6, got {score}"
    assert_scorer_called(path)


def test_shortest_path_not_found():
    data = get_json('/shortest-path', {"start": "n1", "end": "n999"}, 404)
    assert "error" in data, "Expected 'error' key in 404 response"


def test_hidden_label_all_pages_and_exact_filtering():
    challenge = json.load(open('/tmp/api_challenge.json'))
    conn = sqlite3.connect('/home/user/dataset.db')
    expected = [dict(zip(('id','name'), row)) for row in conn.execute(
        'SELECT id,name FROM nodes WHERE label=? ORDER BY id ASC', (challenge['label'],))]
    conn.close()
    assert len(expected) == 7
    for limit in (1, 2, 3, 5, 9):
        max_page = (len(expected) + limit - 1) // limit
        for page in range(1, max_page + 2):
            data = get_json('/nodes', {'label': challenge['label'], 'limit': limit, 'page': page})
            assert data.get('page') == page
            assert data.get('limit') == limit
            assert data.get('results') == expected[(page-1)*limit:page*limit]


def shortest_distance(adjacency, start, end):
    queue = deque([(start, 0)])
    seen = {start}
    while queue:
        node, distance = queue.popleft()
        if node == end:
            return distance
        for nxt in adjacency.get(node, ()):
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, distance + 1))
    return None


def test_hidden_graph_all_ordered_pairs_are_shortest_undirected_and_scored():
    challenge = json.load(open('/tmp/api_challenge.json'))
    graph_ids = challenge['graph_ids']
    conn = sqlite3.connect('/home/user/dataset.db')
    adjacency = {node: set() for node in graph_ids}
    for source, target in conn.execute('SELECT source,target FROM edges'):
        adjacency.setdefault(source, set()).add(target)
        adjacency.setdefault(target, set()).add(source)
    conn.close()

    for start in graph_ids:
        for end in graph_ids:
            data = get_json('/shortest-path', {'start': start, 'end': end})
            path = data.get('path')
            assert isinstance(path, list)
            assert path and path[0] == start and path[-1] == end
            assert len(path) == len(set(path)), f"Path contains a cycle: {path}"
            assert all(b in adjacency.get(a, ()) for a, b in zip(path, path[1:])), path
            assert len(path) - 1 == shortest_distance(adjacency, start, end), path
            score = data.get('score')
            assert isinstance(score, (int, float))
            assert abs(float(score) - oracle_score(path)) < 0.001
            assert_scorer_called(path)


def test_hidden_disconnected_and_missing_nodes_return_404():
    challenge = json.load(open('/tmp/api_challenge.json'))
    for start, end in ((challenge['graph_ids'][0], challenge['isolated']),
                       (challenge['missing'], challenge['graph_ids'][0])):
        data = get_json('/shortest-path', {'start': start, 'end': end}, 404)
        assert 'error' in data
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
}

if run_all 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
