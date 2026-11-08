#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys

import pytest

DB_PATH = '/home/user/events.db'
SCRIPT_PATH = '/home/user/etl_process.py'
OUTPUT_PATH = '/home/user/output.json'


@pytest.fixture(scope='session', autouse=True)
def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f'Script file missing at {SCRIPT_PATH}'

    # Remove artifacts that could have been prepared without running the script.
    conn = sqlite3.connect(DB_PATH)
    conn.execute('DROP INDEX IF EXISTS idx_user_date')
    conn.commit()
    conn.close()
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, '5'],
        cwd='/home/user',
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'etl_process.py failed for user 5\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    yield


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f'Script file missing at {SCRIPT_PATH}'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file'


def test_index_exists():
    assert os.path.exists(DB_PATH), f'Database file missing at {DB_PATH}'
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_user_date';")
    index = cursor.fetchone()
    assert index is not None, "Index 'idx_user_date' does not exist in the database."

    cursor.execute('PRAGMA index_info(idx_user_date)')
    columns = [row[2] for row in cursor.fetchall()]
    conn.close()
    assert columns == ['user_id', 'record_date'], (
        f"Index 'idx_user_date' must index (user_id, record_date), found {columns}"
    )


def test_output_json_exists_and_format():
    assert os.path.exists(OUTPUT_PATH), f'Output file missing at {OUTPUT_PATH}'
    assert os.path.isfile(OUTPUT_PATH), f'{OUTPUT_PATH} is not a file'

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {OUTPUT_PATH} does not contain valid JSON')

    assert isinstance(data, list), 'Output JSON must be a list of dictionaries'

    expected_data = [
        {'record_date': '2023-10-01', 'rolling_sum': 1.0},
        {'record_date': '2023-10-02', 'rolling_sum': 3.0},
        {'record_date': '2023-10-03', 'rolling_sum': 6.0},
        {'record_date': '2023-10-04', 'rolling_sum': 10.0},
        {'record_date': '2023-10-05', 'rolling_sum': 15.0},
        {'record_date': '2023-10-06', 'rolling_sum': 21.0},
        {'record_date': '2023-10-07', 'rolling_sum': 28.0},
        {'record_date': '2023-10-08', 'rolling_sum': 35.0},
        {'record_date': '2023-10-09', 'rolling_sum': 42.0},
        {'record_date': '2023-10-10', 'rolling_sum': 49.0}
    ]

    assert len(data) == len(expected_data), f'Expected {len(expected_data)} records, found {len(data)}'

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f'Record at index {i} is not a dictionary'
        assert 'record_date' in actual, f"Record at index {i} missing 'record_date'"
        assert 'rolling_sum' in actual, f"Record at index {i} missing 'rolling_sum'"
        assert actual['record_date'] == expected['record_date'], \
            f"Record {i}: Expected date {expected['record_date']}, got {actual['record_date']}"
        assert abs(float(actual['rolling_sum']) - expected['rolling_sum']) < 1e-5, \
            f"Record {i}: Expected rolling_sum {expected['rolling_sum']}, got {actual['rolling_sum']}"


def _resolve_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return assignments.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _resolve_string(node.left, assignments)
        right = _resolve_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    return None


def test_sql_uses_required_index_parameter_and_window():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            value = _resolve_string(node.value, assignments)
            if value is not None:
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        assignments[target.id] = value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            value = _resolve_string(node.value, assignments)
            if value is not None:
                assignments[node.target.id] = value

    found_index = False
    found_parameterized_window_query = False

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr != 'execute' or not node.args:
            continue
        sql = _resolve_string(node.args[0], assignments)
        if sql is None:
            continue
        normalized = sql.replace('"', '').replace('`', '').replace('[', '').replace(']', '')

        if re.search(
            r'CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+idx_user_date\s+'
            r'ON\s+daily_metrics\s*\(\s*user_id\s*,\s*record_date\s*\)',
            normalized,
            re.IGNORECASE | re.DOTALL,
        ):
            found_index = True

        has_window = re.search(
            r'SUM\s*\(\s*(?:\w+\.)?metric_value\s*\)\s+OVER\s*\('
            r'.*?ORDER\s+BY\s+(?:\w+\.)?record_date(?:\s+ASC)?'
            r'.*?ROWS\s+BETWEEN\s+6\s+PRECEDING\s+AND\s+CURRENT\s+ROW\s*\)',
            normalized,
            re.IGNORECASE | re.DOTALL,
        )
        has_user_placeholder = re.search(
            r'(?:\w+\.)?user_id\s*=\s*(?:\?|:\w+|@\w+|\$\w+)',
            normalized,
            re.IGNORECASE,
        )
        supplies_parameters = len(node.args) >= 2 or any(
            keyword.arg in {'parameters', 'params'} for keyword in node.keywords
        )
        if has_window and has_user_placeholder and supplies_parameters:
            found_parameterized_window_query = True

    assert found_index, (
        "The script must execute CREATE INDEX IF NOT EXISTS idx_user_date "
        "ON daily_metrics(user_id, record_date)"
    )
    assert found_parameterized_window_query, (
        'The SELECT must be parameterized by user_id and use '
        'SUM(metric_value) OVER (... ORDER BY record_date '
        'ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)'
    )


def test_runtime_for_unseen_user_with_derived_answer():
    rng = secrets.SystemRandom()
    conn = sqlite3.connect(DB_PATH)
    existing = {row[0] for row in conn.execute('SELECT DISTINCT user_id FROM daily_metrics')}
    user_id = rng.randrange(100000, 1000000000)
    while user_id in existing:
        user_id = rng.randrange(100000, 1000000000)
    noise_user = user_id + 1
    while noise_user in existing:
        noise_user += 1

    dates = [f'2041-07-{day:02d}' for day in range(1, 13)]
    values = [rng.randrange(-25000, 50000) / 100.0 for _ in dates]
    rows = list(zip([user_id] * len(dates), dates, values))
    # Insert out of date order so the implementation must order by record_date.
    rng.shuffle(rows)
    conn.executemany(
        'INSERT INTO daily_metrics (user_id, record_date, metric_value) VALUES (?, ?, ?)',
        rows,
    )
    conn.executemany(
        'INSERT INTO daily_metrics (user_id, record_date, metric_value) VALUES (?, ?, ?)',
        [(noise_user, date, 100000.0 + i) for i, date in enumerate(dates)],
    )
    conn.commit()

    ordered = list(conn.execute(
        'SELECT record_date, metric_value FROM daily_metrics '
        'WHERE user_id = ? ORDER BY record_date ASC',
        (user_id,),
    ))
    expected = []
    for i, (record_date, _) in enumerate(ordered):
        rolling = sum(float(row[1]) for row in ordered[max(0, i - 6):i + 1])
        expected.append({'record_date': record_date, 'rolling_sum': round(rolling, 2)})
    conn.close()

    try:
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH, str(user_id)],
            cwd='/home/user',
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f'etl_process.py failed for generated user {user_id}\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        assert os.path.isfile(OUTPUT_PATH), 'Script did not create output.json'
        with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
            actual = json.load(f)

        assert isinstance(actual, list)
        assert len(actual) == len(expected)
        for i, (got, wanted) in enumerate(zip(actual, expected)):
            assert isinstance(got, dict), f'Record {i} is not a dictionary'
            assert set(got) == {'record_date', 'rolling_sum'}, f'Record {i} has incorrect keys'
            assert got['record_date'] == wanted['record_date']
            assert isinstance(got['rolling_sum'], (int, float)) and not isinstance(got['rolling_sum'], bool)
            assert abs(float(got['rolling_sum']) - wanted['rolling_sum']) < 1e-5, (
                f"Record {i}: expected {wanted['rolling_sum']}, got {got['rolling_sum']}"
            )
    finally:
        cleanup = sqlite3.connect(DB_PATH)
        cleanup.execute('DELETE FROM daily_metrics WHERE user_id IN (?, ?)', (user_id, noise_user))
        cleanup.commit()
        cleanup.close()


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
