#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import sqlite3
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/process_bom.sh')
DB = Path('/home/user/bom.db')
PLAN = Path('/home/user/query_plan.txt')
OUTPUT = Path('/home/user/top_parts.json')
RAW = Path('/home/user/raw_parts.csv')
GENERATED = (DB, PLAN, OUTPUT)
ORIGINAL_RAW = RAW.read_bytes()


def run_script_clean():
    for path in GENERATED:
        if path.exists() or path.is_symlink():
            path.unlink()
    subprocess.run([str(SCRIPT)], cwd='/home/user', check=True, timeout=30)
    for path in GENERATED:
        assert path.exists(), f'{path} was not created by process_bom.sh'
        assert path.is_file(), f'{path} is not a regular file'


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert SCRIPT.exists(), f'Script {SCRIPT} does not exist.'
    assert SCRIPT.is_file(), f'{SCRIPT} is not a file.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'
    run_script_clean()
    yield


def read_csv(path=RAW):
    rows = []
    with path.open(newline='') as f:
        for row in csv.reader(f):
            assert len(row) == 4
            rows.append((int(row[0]), None if row[1] == '' else int(row[1]), row[2], float(row[3])))
    return rows


def expected_from_rows(rows):
    by_parent = {}
    for part_id, parent_id, name, cost in rows:
        by_parent.setdefault(parent_id, []).append((part_id, parent_id, name, cost))

    levels = {}
    frontier = [(row, 0) for row in by_parent.get(None, [])]
    seen = set()
    while frontier:
        row, depth = frontier.pop(0)
        part_id = row[0]
        if part_id in seen:
            continue
        seen.add(part_id)
        levels.setdefault(depth, []).append(row)
        for child in by_parent.get(part_id, []):
            frontier.append((child, depth + 1))

    result = []
    for depth in sorted(levels):
        ranked = sorted(levels[depth], key=lambda r: (-r[3], r[0]))
        for rank, row in enumerate(ranked, 1):
            if rank <= 2:
                result.append({
                    'id': row[0], 'name': row[2], 'depth': depth,
                    'cost': row[3], 'cost_rank': rank,
                })
    return result


def load_json():
    try:
        with OUTPUT.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {OUTPUT} does not contain valid JSON: {exc}')


def user_index_names(conn):
    names = []
    for (name,) in conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='parts'"):
        if name.startswith('sqlite_autoindex'):
            continue
        quoted = name.replace('"', '""')
        columns = conn.execute(f'PRAGMA index_info("{quoted}")').fetchall()
        if columns and columns[0][2] == 'parent_id':
            names.append(name)
    return names


def assert_plan_uses_real_index(conn):
    assert PLAN.exists(), f'Query plan file {PLAN} does not exist.'
    content = PLAN.read_text()
    upper = content.upper()
    assert 'USING INDEX' in upper or 'USING COVERING INDEX' in upper, \
        "The query plan does not indicate that an index was used (missing 'USING INDEX')."
    names = user_index_names(conn)
    assert names, "No index on 'parent_id' found for the 'parts' table."
    assert any(name.lower() in content.lower() for name in names), \
        'The saved query plan does not name an actual parent_id index from bom.db.'
    assert 'QUERY PLAN' in upper and ('SCAN' in upper or 'SEARCH' in upper), \
        'query_plan.txt is not recognizable EXPLAIN QUERY PLAN output.'


def assert_exact_output(expected):
    data = load_json()
    assert isinstance(data, list), 'JSON output should be a list of objects.'
    assert len(data) == len(expected), f'Expected {len(expected)} records, but got {len(data)}.'
    for i, (actual_row, expected_row) in enumerate(zip(data, expected)):
        assert isinstance(actual_row, dict), f'Row {i} is not an object.'
        assert set(actual_row) == {'id', 'name', 'depth', 'cost', 'cost_rank'}, \
            f'Row {i} must have exactly the selected column names.'
        actual_normalized = {k.lower(): v for k, v in actual_row.items()}
        for key, exp_val in expected_row.items():
            assert key in actual_normalized, f"Row {i} is missing key '{key}'"
            if isinstance(exp_val, float):
                assert abs(float(actual_normalized[key]) - exp_val) < 1e-5, \
                    f"Row {i} key '{key}' mismatch: expected {exp_val}, got {actual_normalized[key]}"
            else:
                assert actual_normalized[key] == exp_val, \
                    f"Row {i} key '{key}' mismatch: expected {exp_val}, got {actual_normalized[key]}"


def test_script_exists_and_executable():
    assert SCRIPT.exists(), f'Script {SCRIPT} does not exist.'
    assert SCRIPT.is_file(), f'{SCRIPT} is not a file.'
    assert os.access(SCRIPT, os.X_OK), f'Script {SCRIPT} is not executable.'


def test_script_uses_sqlite_recursive_cte_and_window_function():
    sources = [SCRIPT]
    sources.extend(p for p in Path('/home/user').glob('*.sql') if p.is_file())
    text = '\n'.join(p.read_text(errors='replace') for p in sources)
    assert re.search(r'\bsqlite3\b', text, re.I), 'process_bom.sh must use the sqlite3 command-line tool.'
    assert re.search(r'\bWITH\s+RECURSIVE\b', text, re.I | re.S), 'No recursive CTE was found.'
    assert re.search(r'\b(ROW_NUMBER|RANK|DENSE_RANK)\s*\(', text, re.I), 'No ranking window function was found.'
    assert re.search(r'\bOVER\s*\(', text, re.I), 'The ranking function is not used as a window function.'
    assert re.search(r'\bEXPLAIN\s+QUERY\s+PLAN\b', text, re.I), 'No EXPLAIN QUERY PLAN statement was found.'


def test_db_table_schema_and_imported_rows():
    assert DB.exists(), f'Database {DB} does not exist.'
    with sqlite3.connect(DB) as conn:
        table = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='parts'").fetchone()
        assert table is not None, "Table 'parts' does not exist in the database."
        schema = conn.execute('PRAGMA table_info(parts)').fetchall()
        observed = [(r[1], r[2].upper(), r[5]) for r in schema]
        assert observed == [
            ('id', 'INTEGER', 1), ('parent_id', 'INTEGER', 0),
            ('name', 'TEXT', 0), ('cost', 'REAL', 0),
        ], f'Unexpected parts schema: {observed}'
        actual = conn.execute('SELECT id, parent_id, name, cost FROM parts ORDER BY id').fetchall()
    expected = sorted(read_csv(), key=lambda r: r[0])
    assert actual == expected, 'The parts table does not exactly contain the imported CSV rows.'


def test_index_exists():
    assert DB.exists(), f'Database {DB} does not exist.'
    with sqlite3.connect(DB) as conn:
        assert user_index_names(conn), "No index on 'parent_id' found for the 'parts' table."


def test_query_plan_uses_index():
    with sqlite3.connect(DB) as conn:
        assert_plan_uses_real_index(conn)


def test_json_output_correct():
    expected = [
        {'id': 1, 'name': 'Engine', 'depth': 0, 'cost': 5000.0, 'cost_rank': 1},
        {'id': 7, 'name': 'Chassis', 'depth': 0, 'cost': 2000.0, 'cost_rank': 2},
        {'id': 8, 'name': 'Frame', 'depth': 1, 'cost': 1500.0, 'cost_rank': 1},
        {'id': 9, 'name': 'Suspension', 'depth': 1, 'cost': 400.0, 'cost_rank': 2},
        {'id': 10, 'name': 'Shock Absorber', 'depth': 2, 'cost': 120.0, 'cost_rank': 1},
        {'id': 6, 'name': 'Connecting Rod', 'depth': 2, 'cost': 80.0, 'cost_rank': 2},
    ]
    assert_exact_output(expected)


def test_reprocesses_changed_bom_with_recursive_depth_and_tie_breaking():
    alternate = b'''101,,Root A,100.0
102,,Root B,100.0
103,,Root C,50.0
201,101,Child A1,20.0
202,101,Child A2,20.0
203,102,Child B1,30.0
301,202,Deep A,9.0
302,203,Deep B,9.0
303,201,Deep C,7.0
'''
    rows = []
    try:
        RAW.write_bytes(alternate)
        rows = read_csv()
        run_script_clean()
        expected = expected_from_rows(rows)
        assert_exact_output(expected)
        with sqlite3.connect(DB) as conn:
            imported = conn.execute('SELECT id, parent_id, name, cost FROM parts ORDER BY id').fetchall()
            assert imported == sorted(rows, key=lambda r: r[0]), 'Changed CSV was not re-imported.'
            assert_plan_uses_real_index(conn)
    finally:
        RAW.write_bytes(ORIGINAL_RAW)
        run_script_clean()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
