#!/bin/bash
set -e
mkdir -p /logs/verifier

ok=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import pytest

def test_violations_json_correct():
    violations_path = "/home/user/violations.json"
    assert os.path.exists(violations_path), f"File {violations_path} does not exist."
    assert os.path.isfile(violations_path), f"{violations_path} is not a file."

    graph_path = "/home/user/graph.json"
    assert os.path.exists(graph_path), f"File {graph_path} is missing."
    with open(graph_path, 'r') as f:
        graph_data = json.load(f)

    user_roles = {}
    role_resources = {}
    for edge in graph_data.get("edges", []):
        if edge.get("relation") == "HAS_ROLE":
            user_roles.setdefault(edge["source"], set()).add(edge["target"])
        elif edge.get("relation") == "CAN_ACCESS":
            role_resources.setdefault(edge["source"], set()).add(edge["target"])

    valid_access = set()
    for user, roles in user_roles.items():
        for role in roles:
            for resource in role_resources.get(role, set()):
                valid_access.add((user, resource))

    db_path = "/home/user/audit.db"
    assert os.path.exists(db_path), f"File {db_path} is missing."

    reported_access = set()
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT user_id, resource_id FROM reported_access")
        for row in cursor.fetchall():
            reported_access.add((row[0], row[1]))
    finally:
        conn.close()

    violations = reported_access - valid_access
    expected_violations = [
        {"user_id": user, "resource_id": resource}
        for user, resource in violations
    ]
    expected_violations.sort(key=lambda x: (x["user_id"], x["resource_id"]))

    try:
        with open(violations_path, 'r') as f:
            actual_violations = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{violations_path} does not contain valid JSON.")

    assert isinstance(actual_violations, list), f"Expected a JSON array in {violations_path}."
    assert actual_violations == expected_violations, (
        f"Violations mismatch. Expected: {expected_violations}, Got: {actual_violations}"
    )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || ok=0

if [ "$ok" -eq 1 ]; then
    if [ ! -f /home/user/audit.go ]; then
        echo "Missing Go source file /home/user/audit.go" >&2
        ok=0
    elif ! (cd /home/user && timeout 120s go build -o /tmp/audit_submission ./audit.go); then
        echo "audit.go did not compile successfully" >&2
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
python3 << 'DYNAMIC_EOF' || ok=0
import json
import os
import sqlite3
import subprocess
import uuid
from pathlib import Path

home = Path('/home/user')
graph_path = home / 'graph.json'
db_path = home / 'audit.db'
out_path = home / 'violations.json'
paths = [graph_path, db_path, out_path]
backups = {p: p.read_bytes() if p.exists() else None for p in paths}

suffix = uuid.uuid4().hex
u1, u2, u3 = [f'U_{x}_{suffix}' for x in ('one', 'two', 'three')]
r1, r2 = [f'ROLE_{x}_{suffix}' for x in ('one', 'two')]
a, b = [f'RES_{x}_{suffix}' for x in ('one', 'two')]

def graph(edges):
    return {
        'nodes': [
            {'id': u1, 'type': 'User'}, {'id': u2, 'type': 'User'},
            {'id': u3, 'type': 'User'}, {'id': r1, 'type': 'Role'},
            {'id': r2, 'type': 'Role'}, {'id': a, 'type': 'Resource'},
            {'id': b, 'type': 'Resource'}
        ],
        'edges': [
            {'source': s, 'target': t, 'relation': rel}
            for s, t, rel in edges
        ]
    }

def install_db(rows):
    for extra in (db_path, Path(str(db_path) + '-wal'), Path(str(db_path) + '-shm')):
        try:
            extra.unlink()
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(db_path)
    try:
        conn.execute('CREATE TABLE reported_access(user_id TEXT, resource_id TEXT)')
        conn.executemany('INSERT INTO reported_access VALUES (?, ?)', rows)
        conn.commit()
    finally:
        conn.close()

def run_case(graph_data, rows, expected):
    graph_path.write_text(json.dumps(graph_data), encoding='utf-8')
    install_db(rows)
    try:
        out_path.unlink()
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ['/tmp/audit_submission'], cwd='/home/user',
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f'program failed: {result.stderr}'
    assert out_path.is_file(), 'program did not create violations.json'
    actual = json.loads(out_path.read_text(encoding='utf-8'))
    expected_json = [
        {'user_id': user, 'resource_id': resource}
        for user, resource in sorted(expected)
    ]
    assert actual == expected_json, f'expected {expected_json}, got {actual}'

try:
    graph1 = graph([
        (u1, r1, 'HAS_ROLE'), (u2, r2, 'HAS_ROLE'),
        (r1, a, 'CAN_ACCESS'), (r2, b, 'CAN_ACCESS')
    ])
    run_case(graph1, [(u1, a), (u1, b), (u3, a)], {(u1, b), (u3, a)})

    rows2 = [(u2, b), (u2, a), (u3, b)]
    run_case(graph1, rows2, {(u2, a), (u3, b)})

    graph2 = graph([
        (u1, r1, 'HAS_ROLE'), (u2, r1, 'HAS_ROLE'),
        (r1, a, 'CAN_ACCESS'), (r2, b, 'CAN_ACCESS')
    ])
    run_case(graph2, rows2, {(u2, b), (u3, b)})
finally:
    for extra in (Path(str(db_path) + '-wal'), Path(str(db_path) + '-shm')):
        try:
            extra.unlink()
        except FileNotFoundError:
            pass
    for path, data in backups.items():
        if data is None:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        else:
            path.write_bytes(data)
DYNAMIC_EOF
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
