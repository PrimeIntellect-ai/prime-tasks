#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import sqlite3
import subprocess

DB_PATH = '/home/user/graph_backup.db'
RESULTS_PATH = '/home/user/results.json'
SCRIPT_PATH = '/home/user/extract.py'

ORIGINAL_EXPECTED = [
    {"source_name": "auth_service", "source_status": "active"},
    {"source_name": "background_worker", "source_status": "active"},
    {"source_name": "web_api", "source_status": "active"}
]


def read_results():
    assert os.path.exists(RESULTS_PATH), f"Results JSON missing at {RESULTS_PATH}"
    try:
        with open(RESULTS_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{RESULTS_PATH} is not valid JSON: {exc}")
    assert isinstance(data, list), "JSON root must be a list."
    for item in data:
        assert isinstance(item, dict), "Every JSON item must be a dictionary."
        assert set(item) == {"source_name", "source_status"}, \
            f"Each item must have exactly source_name and source_status: {item}"
    assert data == sorted(data, key=lambda x: x["source_name"]), \
        "Results are not alphabetically sorted by source_name."
    assert len({(x["source_name"], x["source_status"]) for x in data}) == len(data), \
        "Results contain duplicate entries."
    return data


def index_columns():
    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type='index' AND name='idx_edges_target'"
        ).fetchone()
        assert row is not None, "Index 'idx_edges_target' was not created."
        assert row[1] == 'edges', \
            f"Index 'idx_edges_target' is on the wrong table: {row[1]} instead of edges."
        return [r[2] for r in conn.execute("PRAGMA index_info('idx_edges_target')")]
    finally:
        conn.close()


def run_script(*args):
    return subprocess.run(
        ['python3', SCRIPT_PATH, *args],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10
    )


def expected_for(relation, target_type):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            """
            SELECT DISTINCT s.name, s.status
            FROM nodes AS s
            JOIN edges AS e ON s.id = e.source_id
            JOIN nodes AS t ON t.id = e.target_id
            WHERE e.relation = ? AND t.node_type = ?
            ORDER BY s.name
            """,
            (relation, target_type)
        ).fetchall()
    finally:
        conn.close()
    return [{"source_name": name, "source_status": status} for name, status in rows]


def test_index_created():
    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"
    assert index_columns() == ['target_id'], \
        "Index 'idx_edges_target' must index exactly the target_id column."


def test_extract_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing at {SCRIPT_PATH}"


def test_results_json():
    data = read_results()
    assert len(data) == len(ORIGINAL_EXPECTED), \
        f"Expected {len(ORIGINAL_EXPECTED)} items, got {len(data)}."
    assert data == ORIGINAL_EXPECTED, \
        f"JSON output does not match expected results. Expected: {ORIGINAL_EXPECTED}, Got: {data}"


def test_script_contains_parameterized_join_query():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    strings = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            try:
                literal = ast.literal_eval(value)
            except Exception:
                continue
            if not isinstance(literal, str):
                continue
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    strings[target.id] = literal

    valid = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr != 'execute' or len(node.args) < 2:
            continue
        sql = None
        if isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
            sql = node.args[0].value
        elif isinstance(node.args[0], ast.Name):
            sql = strings.get(node.args[0].id)
        if not sql:
            continue
        normalized = sql.lower()
        has_placeholder = re.search(r'\?|:[A-Za-z_][A-Za-z0-9_]*', sql) is not None
        if ('select' in normalized and 'edges' in normalized and
                normalized.count('nodes') >= 2 and has_placeholder):
            valid = True
            break

    assert valid, \
        "No parameterized SELECT joining source nodes, edges, and target nodes was found."


def test_script_arguments_and_behavior_on_derived_inputs(tmp_path):
    backup = tmp_path / 'graph_backup.db'
    shutil.copy2(DB_PATH, backup)

    def restore_database():
        for suffix in ('-wal', '-shm'):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup, DB_PATH)

    try:
        for bad_args in [(), ('only_relation',), ('a', 'b', 'extra')]:
            proc = run_script(*bad_args)
            assert proc.returncode != 0, \
                f"Script must reject invocation with {len(bad_args)} argument(s)."

        conn = sqlite3.connect(DB_PATH)
        try:
            conn.executemany('INSERT INTO nodes VALUES (?, ?, ?, ?)', [
                (101, 'dynamic_alpha', 'service', 'active'),
                (102, 'dynamic_zeta', 'worker', 'degraded'),
                (103, 'quoted_source', 'service', 'inactive'),
                (201, 'dynamic_target', 'type_dynamic', 'active'),
                (202, 'wrong_type_target', 'other_type', 'active'),
                (203, 'quoted_target', "type_'quoted", 'active')
            ])
            conn.executemany('INSERT INTO edges VALUES (?, ?, ?)', [
                (101, 201, 'rel_dynamic'),
                (101, 201, 'rel_dynamic'),
                (102, 201, 'rel_dynamic'),
                (103, 202, 'rel_dynamic'),
                (103, 201, 'wrong_relation'),
                (103, 203, "rel_' OR 1=1 --")
            ])
            conn.commit()
        finally:
            conn.close()

        cases = [
            ('rel_dynamic', 'type_dynamic'),
            ("rel_' OR 1=1 --", "type_'quoted"),
            ("rel_dynamic' OR 1=1 --", 'type_dynamic'),
            ('wrong_relation', 'type_dynamic')
        ]
        for relation, target_type in cases:
            expected = expected_for(relation, target_type)
            proc = run_script(relation, target_type)
            assert proc.returncode == 0, \
                f"Script failed for {relation!r}, {target_type!r}: {proc.stderr}"
            assert read_results() == expected, \
                f"Wrong output for relation={relation!r}, target type={target_type!r}."
    finally:
        restore_database()

    proc = run_script('depends_on', 'storage')
    assert proc.returncode == 0, f"Required invocation failed: {proc.stderr}"
    assert read_results() == ORIGINAL_EXPECTED, \
        "Required depends_on/storage execution did not produce the exact expected JSON."
    assert index_columns() == ['target_id'], \
        "The required target_id index was not preserved after script execution."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
