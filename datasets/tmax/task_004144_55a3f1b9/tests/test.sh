#!/bin/bash
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'PY_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import json
import math
import os
import random
import secrets
import stat
import urllib.error
import urllib.request

URL = "http://127.0.0.1:8080/process"
SOURCE = "/home/user/mol_server.cpp"
BINARY = "/home/user/mol_server"
ORACLE = "/app/mol_oracle"
BACKUP = "/tmp/mol_oracle.verifier_backup"
KEY_FILE = "/tmp/mol_oracle_verifier_key"
LOG_FILE = "/tmp/mol_oracle_verifier_calls"


def require_artifacts():
    assert os.path.isfile(SOURCE), f"Missing required source file: {SOURCE}"
    assert os.path.getsize(SOURCE) > 0, f"Source file is empty: {SOURCE}"
    assert os.path.isfile(BINARY), f"Missing compiled server: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled server is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled server is not an ELF executable"


def post(payload):
    body = json.dumps(payload, separators=(",", ":")).encode()
    request = urllib.request.Request(
        URL, data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status = response.status
            text = response.read().decode()
    except urllib.error.HTTPError as e:
        raise AssertionError(f"Expected HTTP 200, got {e.code}. Response: {e.read().decode(errors='replace')}")
    except Exception as e:
        raise AssertionError(f"Failed to connect to the server or send request: {e}")

    assert status == 200, f"Expected HTTP 200, got {status}. Response: {text}"
    try:
        data = json.loads(text)
    except Exception:
        raise AssertionError(f"Response is not valid JSON. Response text: {text}")
    assert "triangles" in data, f"Missing 'triangles' key in JSON response: {data}"
    assert "oracle_score" in data, f"Missing 'oracle_score' key in JSON response: {data}"
    return data


def check_response(payload, expected_triangles, expected_score):
    data = post(payload)
    assert data["triangles"] == expected_triangles, \
        f"Expected {expected_triangles} triangles, got {data['triangles']}"
    assert isinstance(data["oracle_score"], (int, float)) and not isinstance(data["oracle_score"], bool), \
        f"oracle_score must be numeric, got {data['oracle_score']!r}"
    assert math.isclose(float(data["oracle_score"]), expected_score, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected oracle_score ~{expected_score}, got {data['oracle_score']}"


def triangle_count(n, edges):
    adj = [set() for _ in range(n)]
    for u, v in edges:
        adj[u].add(v)
        adj[v].add(u)
    return sum(1 for i in range(n) for j in range(i + 1, n) for k in range(j + 1, n)
               if j in adj[i] and k in adj[i] and k in adj[j])


def canonical(n, edges):
    normalized = sorted((min(u, v), max(u, v)) for u, v in edges)
    return str(n) + "|" + ",".join(f"{u}-{v}" for u, v in normalized)


def keyed_score(key, n, edges):
    digest = hmac.new(key, canonical(n, edges).encode(), hashlib.sha256).digest()
    return 100.0 + (int.from_bytes(digest[:4], "big") % 900000) / 100.0


def install_instrumented_oracle(key):
    if os.path.exists(BACKUP):
        os.unlink(BACKUP)
    os.replace(ORACLE, BACKUP)
    with open(KEY_FILE, "wb") as f:
        f.write(key)
    os.chmod(KEY_FILE, 0o644)
    with open(LOG_FILE, "w"):
        pass
    os.chmod(LOG_FILE, 0o666)

    wrapper = '''#!/usr/bin/env python3
import hashlib
import hmac

KEY_FILE = "/tmp/mol_oracle_verifier_key"
LOG_FILE = "/tmp/mol_oracle_verifier_calls"
raw = __import__("sys").stdin.read().split()
if len(raw) < 2:
    raise SystemExit(1)
n, m = int(raw[0]), int(raw[1])
if len(raw) < 2 + 2 * m:
    raise SystemExit(1)
edges = []
for i in range(m):
    u, v = int(raw[2 + 2*i]), int(raw[3 + 2*i])
    edges.append((min(u, v), max(u, v)))
edges.sort()
canon = str(n) + "|" + ",".join(str(u) + "-" + str(v) for u, v in edges)
with open(KEY_FILE, "rb") as f:
    key = f.read()
digest = hmac.new(key, canon.encode(), hashlib.sha256).digest()
score = 100.0 + (int.from_bytes(digest[:4], "big") % 900000) / 100.0
with open(LOG_FILE, "a") as f:
    f.write(canon + "\\n")
print("%.2f" % score)
'''
    with open(ORACLE, "w") as f:
        f.write(wrapper)
    os.chmod(ORACLE, 0o755)


def restore_oracle():
    try:
        if os.path.exists(ORACLE):
            os.unlink(ORACLE)
        if os.path.exists(BACKUP):
            os.replace(BACKUP, ORACLE)
    finally:
        for path in (KEY_FILE, LOG_FILE):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def run():
    require_artifacts()

    # Preserve all original fixed assertions against the shipped oracle.
    check_response({"nodes": 4, "edges": [[0,1], [1,2], [2,3], [3,0], [0,2]]}, 2, 13.9)
    check_response({"nodes": 3, "edges": [[0,1], [1,2]]}, 0, 3.0)
    k5 = [[i, j] for i in range(5) for j in range(i + 1, 5)]
    check_response({"nodes": 5, "edges": k5}, 10, 47.0)
    disconnected = [[0,1], [1,2], [2,0], [3,4], [4,5], [5,3]]
    check_response({"nodes": 6, "edges": disconnected}, 2, 15.4)

    # Replace the oracle only during hidden tests. Its unpredictable keyed output
    # and call log prove that the server executes /app/mol_oracle for each graph.
    key = secrets.token_bytes(32)
    install_instrumented_oracle(key)
    try:
        rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
        cases = []
        for idx in range(10):
            n = rng.randint(4, 12)
            probability = rng.uniform(0.16, 0.72)
            edges = [[i, j] for i in range(n) for j in range(i + 1, n)
                     if rng.random() < probability]
            if not edges:
                edges = [[0, 1]]
            rng.shuffle(edges)
            cases.append((n, edges))

        expected_calls = []
        for n, edges in cases:
            expected_calls.append(canonical(n, edges))
            check_response(
                {"nodes": n, "edges": edges},
                triangle_count(n, edges),
                keyed_score(key, n, edges),
            )

        with open(LOG_FILE) as f:
            calls = [line.rstrip("\n") for line in f]
        for graph in expected_calls:
            assert graph in calls, f"No /app/mol_oracle invocation recorded for graph {graph}"
        assert len(calls) >= len(expected_calls), \
            f"Expected at least {len(expected_calls)} oracle executions, recorded {len(calls)}"
    finally:
        restore_oracle()


if __name__ == "__main__":
    run()
PY_EOF

if python3 /tmp/test_final_state.py; then
    echo "1" > /logs/verifier/reward.txt
else
    # Recover the shipped oracle if Python was interrupted during replacement.
    if [ -e /tmp/mol_oracle.verifier_backup ]; then
        rm -f /app/mol_oracle
        mv /tmp/mol_oracle.verifier_backup /app/mol_oracle
    fi
    rm -f /tmp/mol_oracle_verifier_key /tmp/mol_oracle_verifier_calls
    echo "0" > /logs/verifier/reward.txt
fi
