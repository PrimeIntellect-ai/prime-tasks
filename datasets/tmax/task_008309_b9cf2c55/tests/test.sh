#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import pytest

DB_PATH = '/home/user/audit.db'
SCRIPT_PATH = '/home/user/find_cycles.py'
OUTPUT_PATH = '/home/user/violators.json'


def get_expected_violators():
    """Derive the expected violators directly from the database."""
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file {DB_PATH} is missing.")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT document FROM logs")
    rows = cursor.fetchall()
    conn.close()

    graph = {}
    for (doc_str,) in rows:
        try:
            doc = json.loads(doc_str)
            if doc.get("type") == "approval":
                details = doc.get("details", {})
                req = details.get("requester")
                app = details.get("approver")
                if req and app:
                    if req not in graph:
                        graph[req] = []
                    graph[req].append(app)
                    if app not in graph:
                        graph[app] = []
        except Exception:
            pass

    # Find Strongly Connected Components (Tarjan's algorithm)
    index_counter = [0]
    stack = []
    lowlink = {}
    index = {}
    cyclic_users = []

    def strongconnect(node):
        index[node] = index_counter[0]
        lowlink[node] = index_counter[0]
        index_counter[0] += 1
        stack.append(node)

        for w in graph.get(node, []):
            if w not in index:
                strongconnect(w)
                lowlink[node] = min(lowlink[node], lowlink[w])
            elif w in stack:
                lowlink[node] = min(lowlink[node], index[w])

        if lowlink[node] == index[node]:
            scc = []
            while True:
                w = stack.pop()
                scc.append(w)
                if w == node:
                    break
            # A cycle exists if SCC has > 1 node, or 1 node with a self-loop
            if len(scc) > 1 or (node in graph.get(node, [])):
                cyclic_users.extend(scc)

    for v in graph:
        if v not in index:
            strongconnect(v)

    return sorted(list(set(cyclic_users)))


def run_submission():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script {SCRIPT_PATH} timed out.")
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_and_check_output(expected):
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")
    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    assert data == expected, f"Expected violators {expected}, but got {data}"


def test_script_exists():
    """Test that the python script was created."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_script_executes_on_original_database():
    """Run the submitted artifact rather than accepting a pre-created output."""
    run_submission()


def test_output_exists():
    """Test that the output JSON file was created."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_output_content():
    """Test that the output JSON file contains the correct violators."""
    expected = get_expected_violators()

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON.")

    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    assert data == expected, f"Expected violators {expected}, but got {data}"


def test_script_handles_unseen_database():
    """Exercise extraction and cycle detection on randomized, unseen data."""
    fd, backup_path = tempfile.mkstemp(prefix='audit-backup-', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    old_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, 'rb') as f:
            old_output = f.read()

    token = secrets.token_hex(8)
    a, b, c = [f"cycle3_{token}_{x}" for x in ('a', 'b', 'c')]
    d, e = [f"cycle2_{token}_{x}" for x in ('d', 'e')]
    x, y, z = [f"acyclic_{token}_{n}" for n in ('x', 'y', 'z')]
    events = [
        {"type": "login", "user": a},
        {"type": "approval", "details": {"requester": a, "approver": b}},
        {"type": "approval", "details": {"requester": b, "approver": c}},
        {"type": "approval", "details": {"requester": c, "approver": a}},
        {"type": "approval", "details": {"requester": d, "approver": e}},
        {"type": "approval", "details": {"requester": e, "approver": d}},
        {"type": "approval", "details": {"requester": x, "approver": y}},
        {"type": "approval", "details": {"requester": y, "approver": z}},
        {"type": "approval", "details": {"requester": z}},
        {"type": "logout", "user": b},
    ]

    try:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        conn = sqlite3.connect(DB_PATH)
        conn.execute('CREATE TABLE logs (document TEXT)')
        conn.executemany(
            'INSERT INTO logs (document) VALUES (?)',
            [(json.dumps(event),) for event in events] + [('not valid json',)],
        )
        conn.commit()
        conn.close()

        expected = get_expected_violators()
        assert expected == sorted([a, b, c, d, e])
        run_submission()
        load_and_check_output(expected)
    finally:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        if old_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, 'wb') as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
