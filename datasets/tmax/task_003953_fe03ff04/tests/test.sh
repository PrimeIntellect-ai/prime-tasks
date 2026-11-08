#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/verifier-sqlite-logs

SQLITE_BIN="$(command -v sqlite3)"
REAL_SQLITE="${SQLITE_BIN}.real-verifier"

mv "$SQLITE_BIN" "$REAL_SQLITE"
cat > "$SQLITE_BIN" <<'WRAPPER_EOF'
#!/bin/bash
set -e
logdir="${VERIFIER_SQLITE_LOGDIR:?}"
real="${VERIFIER_REAL_SQLITE:?}"
invocation="$(mktemp "$logdir/invocation.XXXXXX")"
trace="${invocation}.trace"
printf '%s\n' "$@" > "${invocation}.args"
exec "$real" -cmd ".trace $trace" "$@"
WRAPPER_EOF
chmod 755 "$SQLITE_BIN"

restore_sqlite() {
    rm -f "$SQLITE_BIN"
    mv "$REAL_SQLITE" "$SQLITE_BIN"
}
trap restore_sqlite EXIT

export VERIFIER_SQLITE_LOGDIR=/tmp/verifier-sqlite-logs
export VERIFIER_REAL_SQLITE="$REAL_SQLITE"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
from collections import Counter

import pytest

SCRIPT_PATH = '/home/user/analyze.sh'
REPORT_PATH = '/home/user/report.json'
DB_PATH = '/home/user/workflow.db'
LOG_DIR = '/tmp/verifier-sqlite-logs'

BASELINE_ROWS = [
    (1, None, 100),
    (2, 1, 500),
    (3, 1, 700),
    (4, 2, 150),
    (5, 2, 300),
    (6, 3, 800),
    (7, 3, 200),
    (8, 6, 900),
]

EXPECTED_BASELINE = [
    {"id": 1, "parent_id": None, "cost": 100, "depth": 0, "cost_rank": 1},
    {"id": 3, "parent_id": 1, "cost": 700, "depth": 1, "cost_rank": 1},
    {"id": 2, "parent_id": 1, "cost": 500, "depth": 1, "cost_rank": 2},
    {"id": 6, "parent_id": 3, "cost": 800, "depth": 2, "cost_rank": 1},
    {"id": 5, "parent_id": 2, "cost": 300, "depth": 2, "cost_rank": 2},
    {"id": 7, "parent_id": 3, "cost": 200, "depth": 2, "cost_rank": 3},
    {"id": 4, "parent_id": 2, "cost": 150, "depth": 2, "cost_rank": 4},
    {"id": 8, "parent_id": 6, "cost": 900, "depth": 3, "cost_rank": 1},
]

DYNAMIC_ROWS = [
    (1, None, 42),
    (11, 1, 900),
    (4, 1, 900),
    (25, 1, -3),
    (7, 11, 100),
    (13, 4, 800),
    (99, 4, 800),
    (6, 13, 1200),
    (500, None, 9999),
]


def create_database(rows):
    for suffix in ('', '-wal', '-shm', '-journal'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    con = sqlite3.connect(DB_PATH)
    try:
        con.executescript('''
            CREATE TABLE nodes (
                id INTEGER PRIMARY KEY,
                parent_id INTEGER,
                cost INTEGER,
                FOREIGN KEY(parent_id) REFERENCES nodes(id)
            );
            CREATE INDEX idx_parent_id ON nodes(parent_id);
        ''')
        con.executemany('INSERT INTO nodes(id, parent_id, cost) VALUES (?, ?, ?)', rows)
        con.commit()
    finally:
        con.close()
    os.chmod(DB_PATH, 0o666)


def clear_run_artifacts():
    for name in os.listdir(LOG_DIR):
        os.remove(os.path.join(LOG_DIR, name))
    try:
        os.remove(REPORT_PATH)
    except FileNotFoundError:
        pass


def read_report():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")
    assert isinstance(data, list), "JSON output should be a list of objects."
    return data


def check_executed_sql():
    invocations = sorted(
        os.path.join(LOG_DIR, name)
        for name in os.listdir(LOG_DIR)
        if name.startswith('invocation.') and not name.endswith(('.args', '.trace'))
    )
    assert len(invocations) == 1, (
        f"Expected exactly one sqlite3 invocation, observed {len(invocations)}."
    )
    trace_path = invocations[0] + '.trace'
    assert os.path.exists(trace_path), "The sqlite3 invocation produced no SQL trace."
    with open(trace_path, 'r', errors='replace') as f:
        sql = f.read()

    reindex_statements = re.findall(r'(?im)^\s*REINDEX\s*([^;\n]*)\s*;', sql)
    assert reindex_statements, "No executed REINDEX statement was observed."
    normalized_targets = {
        re.sub(r'[\s\"`\[\]]', '', target).lower()
        for target in reindex_statements
    }
    assert normalized_targets.intersection({'', 'idx_parent_id', 'main.idx_parent_id', 'nodes', 'main.nodes'}), (
        "REINDEX did not rebuild all indices used by the supplied database."
    )

    assert re.search(r'\bWITH\s+RECURSIVE\b', sql, re.I), (
        "No executed recursive CTE was observed."
    )
    assert re.search(r'\b(?:RANK|DENSE_RANK|ROW_NUMBER)\s*\(\s*\)\s*OVER\s*\(', sql, re.I), (
        "No executed ranking window function was observed."
    )
    assert re.search(r'\bPARTITION\s+BY\b[^;]*\bdepth\b', sql, re.I | re.S), (
        "The executed window function did not partition by depth."
    )
    assert re.search(r'\bORDER\s+BY\b[^;]*\bcost\b\s+DESC\b', sql, re.I | re.S), (
        "The executed query did not rank costs in descending order."
    )


def run_script(rows):
    create_database(rows)
    clear_run_artifacts()
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"analyze.sh exited with {result.returncode}. stderr: {result.stderr}"
    )
    check_executed_sql()
    return read_report()


def derive_expected(rows):
    by_parent = {}
    values = {}
    for node_id, parent_id, cost in rows:
        values[node_id] = (parent_id, cost)
        by_parent.setdefault(parent_id, []).append(node_id)

    found = []
    stack = [(1, 0)]
    seen = set()
    while stack:
        node_id, depth = stack.pop()
        if node_id in seen or node_id not in values:
            continue
        seen.add(node_id)
        parent_id, cost = values[node_id]
        found.append((node_id, parent_id, cost, depth))
        for child in by_parent.get(node_id, []):
            stack.append((child, depth + 1))

    costs_by_depth = {}
    for _, _, cost, depth in found:
        costs_by_depth.setdefault(depth, []).append(cost)

    expected = []
    for node_id, parent_id, cost, depth in found:
        rank = 1 + sum(other > cost for other in costs_by_depth[depth])
        expected.append({
            'id': node_id,
            'parent_id': parent_id,
            'cost': cost,
            'depth': depth,
            'cost_rank': rank,
        })
    return expected


def canonical(row):
    return (row['id'], row['parent_id'], row['cost'], row['depth'], row['cost_rank'])


def test_analyze_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_report_json_exists_valid_and_has_original_content():
    data = run_script(BASELINE_ROWS)
    assert len(data) == len(EXPECTED_BASELINE), (
        f"Expected {len(EXPECTED_BASELINE)} rows, got {len(data)}."
    )
    for i, (actual, expected) in enumerate(zip(data, EXPECTED_BASELINE)):
        assert actual.get('id') == expected['id'], f"Row {i}: Expected id {expected['id']}, got {actual.get('id')}"
        assert actual.get('parent_id') == expected['parent_id'], f"Row {i}: Expected parent_id {expected['parent_id']}, got {actual.get('parent_id')}"
        assert actual.get('cost') == expected['cost'], f"Row {i}: Expected cost {expected['cost']}, got {actual.get('cost')}"
        assert actual.get('depth') == expected['depth'], f"Row {i}: Expected depth {expected['depth']}, got {actual.get('depth')}"
        assert actual.get('cost_rank') == expected['cost_rank'], f"Row {i}: Expected cost_rank {expected['cost_rank']}, got {actual.get('cost_rank')}"


def test_script_computes_report_from_changed_database():
    data = run_script(DYNAMIC_ROWS)
    expected = derive_expected(DYNAMIC_ROWS)
    required_keys = {'id', 'parent_id', 'cost', 'depth', 'cost_rank'}
    assert all(isinstance(row, dict) and set(row) == required_keys for row in data), (
        "Every output object must contain exactly the required keys."
    )
    assert Counter(canonical(row) for row in data) == Counter(canonical(row) for row in expected)
    ordering = [(row['depth'], row['cost_rank']) for row in data]
    assert ordering == sorted(ordering), (
        "Results are not ordered by depth ascending, then cost_rank ascending."
    )
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e

restore_sqlite
trap - EXIT

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
