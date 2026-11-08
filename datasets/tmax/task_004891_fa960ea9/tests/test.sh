#!/bin/bash
set -e
mkdir -p /logs/verifier

ORACLE_BACKUP="/tmp/matrix_oracle.verifier-backup"
rm -f "$ORACLE_BACKUP"
mv /app/matrix_oracle "$ORACLE_BACKUP"
mkdir -p /tmp/oracle_spy
chmod 777 /tmp/oracle_spy
: > /tmp/oracle_spy/calls.jsonl
chmod 666 /tmp/oracle_spy/calls.jsonl

cat << 'ORACLE_EOF' > /app/matrix_oracle
#!/usr/bin/env python3
import csv
import json
import os
import sys

if len(sys.argv) != 2:
    sys.exit(2)

with open(sys.argv[1], newline='') as f:
    matrix = [[float(x) for x in row] for row in csv.reader(f)]

# Return matrix-dependent values which cannot be predicted by a constant server.
nonce = int.from_bytes(os.urandom(8), 'big') / float(2**64)
output = [
    sum((j + 1) * value for j, value in enumerate(row)) + nonce * (i + 1)
    for i, row in enumerate(matrix)
]
record = {"matrix": matrix, "output": output}
with open('/tmp/oracle_spy/calls.jsonl', 'a') as f:
    f.write(json.dumps(record) + '\n')
print(','.join(format(x, '.17g') for x in output))
ORACLE_EOF
chmod 755 /app/matrix_oracle

restore_oracle() {
    rm -f /app/matrix_oracle
    if [ -f "$ORACLE_BACKUP" ]; then
        mv "$ORACLE_BACKUP" /app/matrix_oracle
    fi
}
trap restore_oracle EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import threading
import time

import numpy as np
import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
ENDPOINT = f"{BASE_URL}/extract"
AUTH_HEADER = {"Authorization": "Bearer graph-token-999"}
CALL_LOG = "/tmp/oracle_spy/calls.jsonl"


def test_missing_auth_rejected():
    """Verify that requests without the correct authorization header are rejected."""
    payload = {"num_nodes": 4, "edges": [[0, 1], [2, 3]]}
    try:
        response = requests.post(ENDPOINT, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the server on 127.0.0.1:8000. Is the service running?")

    assert response.status_code in [401, 403], (
        f"Expected 401 or 403 for missing auth, but got {response.status_code}."
    )


def test_wrong_auth_rejected():
    payload = {"num_nodes": 4, "edges": [[0, 1], [2, 3]]}
    response = requests.post(
        ENDPOINT,
        json=payload,
        headers={"Authorization": "Bearer graph-token-998"},
        timeout=5,
    )
    assert response.status_code in [401, 403]


def test_extract_endpoint_success():
    """Retain the original disconnected-graph API assertions."""
    payload = {"num_nodes": 4, "edges": [[0, 1], [2, 3]]}
    try:
        response = requests.post(ENDPOINT, json=payload, headers=AUTH_HEADER, timeout=30)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the server on 127.0.0.1:8000. Is the service running?")

    assert response.status_code == 200, (
        f"Expected status code 200, but got {response.status_code}. Response: {response.text}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but got: {response.text}")

    assert "embedding" in data, "Response JSON missing 'embedding' key."
    assert "tv_distance" in data, "Response JSON missing 'tv_distance' key."

    embedding = data["embedding"]
    tv_distance = data["tv_distance"]

    assert isinstance(embedding, list), f"Expected 'embedding' to be a list, got {type(embedding)}."
    assert len(embedding) == 4, f"Expected 'embedding' to have 4 elements, got {len(embedding)}."
    assert all(isinstance(x, (int, float)) for x in embedding), "All elements in 'embedding' must be numbers."
    assert isinstance(tv_distance, (int, float)), f"Expected 'tv_distance' to be a float, got {type(tv_distance)}."


def listener_pid():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].endswith(':1F40') and fields[3] == '0A':
                        inodes.add(fields[9])
        except OSError:
            pass
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
                    return int(name)
        except OSError:
            continue
    return None


def descendants(root):
    ppid = {}
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open(f'/proc/{name}/status') as f:
                for line in f:
                    if line.startswith('PPid:'):
                        ppid[int(name)] = int(line.split()[1])
                        break
        except OSError:
            pass
    found = set()
    frontier = {root}
    while frontier:
        children = {pid for pid, parent in ppid.items() if parent in frontier and pid not in found}
        found.update(children)
        frontier = children
    return found


def normalized_adjacency(n, edges):
    a = np.zeros((n, n), dtype=float)
    for u, v in edges:
        a[u, v] = 1.0
        a[v, u] = 1.0
    degree = a.sum(axis=1)
    inv = np.zeros(n)
    inv[degree > 0] = 1.0 / np.sqrt(degree[degree > 0])
    return inv[:, None] * a * inv[None, :]


def transition_matrix(n, edges):
    a = np.zeros((n, n), dtype=float)
    for u, v in edges:
        a[u, v] = 1.0
        a[v, u] = 1.0
    return a / a.sum(axis=1)[:, None]


def test_real_random_walk_matrix_oracle_tv_and_parallelism():
    n = 6
    edges = [[0, 1], [1, 2], [2, 0], [2, 3], [3, 4], [4, 5], [5, 3]]
    payload = {"num_nodes": n, "edges": edges}

    open(CALL_LOG, 'w').close()
    pid = listener_pid()
    assert pid is not None, "Could not identify the process listening on 127.0.0.1:8000"

    result = {}
    def make_request():
        try:
            result['response'] = requests.post(
                ENDPOINT, json=payload, headers=AUTH_HEADER, timeout=60
            )
        except BaseException as exc:
            result['error'] = exc

    thread = threading.Thread(target=make_request)
    thread.start()
    max_children = 0
    while thread.is_alive():
        max_children = max(max_children, len(descendants(pid)))
        time.sleep(0.002)
    thread.join()

    assert 'error' not in result, f"Request failed: {result.get('error')}"
    response = result['response']
    assert response.status_code == 200, response.text
    data = response.json()
    assert set(('embedding', 'tv_distance')).issubset(data)
    assert len(data['embedding']) == n
    assert all(isinstance(x, (int, float)) and math.isfinite(x) for x in data['embedding'])
    assert isinstance(data['tv_distance'], (int, float)) and math.isfinite(data['tv_distance'])
    assert max_children >= 4, (
        "Did not observe at least four child processes while the random-walk request was running"
    )

    with open(CALL_LOG) as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert calls, "The service did not execute /app/matrix_oracle"

    matching = [
        call for call in calls
        if len(call.get('output', [])) == n
        and np.allclose(data['embedding'], call['output'], rtol=1e-9, atol=1e-9)
    ]
    assert matching, "The returned embedding was not parsed from the instrumented oracle output"
    matrix = np.asarray(matching[-1]['matrix'], dtype=float)
    assert matrix.shape == (n, n)
    assert np.isfinite(matrix).all()
    assert np.allclose(matrix, matrix.T, atol=1e-8), "Regularized undirected adjacency is not symmetric"

    base = normalized_adjacency(n, edges)
    delta = matrix - base
    assert delta.min() >= -1e-7, "Regularization removed weight from the normalized adjacency"
    units = delta / 0.01
    assert np.allclose(units, np.rint(units), atol=2e-4), (
        "Synthetic edge weights are not accumulated in increments of 0.01"
    )
    units = np.rint(units)
    assert abs(units.sum() - 10000) <= 1, (
        "The matrix does not contain exactly 5000 undirected synthetic walk edges"
    )

    # For uniform random starts, the expected undirected start/end count after
    # ten steps is T/N * (P^10 + (P^10)^T). The generous stochastic tolerance
    # avoids rejecting normal Monte Carlo variation while detecting fabricated
    # matrices and walks of the wrong length.
    p = transition_matrix(n, edges)
    p10 = np.linalg.matrix_power(p, 10)
    expected_units = (5000.0 / n) * (p10 + p10.T)
    tolerance = 8.0 * np.sqrt(expected_units + 1.0) + 25.0
    assert np.all(np.abs(units - expected_units) <= tolerance), (
        "Synthetic edges do not match 5000 length-10 random walks from uniform random starts"
    )

    endpoint_distribution = np.full(n, 1.0 / n).dot(p10)
    expected_tv = 0.5 * np.abs(endpoint_distribution - 1.0 / n).sum()
    assert abs(float(data['tv_distance']) - expected_tv) < 0.05, (
        "tv_distance is inconsistent with the endpoint distribution of the simulated walks"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
