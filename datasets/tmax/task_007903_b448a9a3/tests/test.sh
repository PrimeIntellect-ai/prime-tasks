#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

DB_PATH = pathlib.Path('/home/user/company_data.db')
SCRIPT_PATH = pathlib.Path('/home/user/process_org.py')
OUTPUT_PATH = pathlib.Path('/home/user/org_metrics.json')

EXPECTED_EVENTS = [
    (1, 1, None, 100000, 'active', '2023-01-01 10:00:00'),
    (2, 1, None, 150000, 'active', '2023-06-01 10:00:00'),
    (3, 2, 1, 90000, 'active', '2023-02-01 10:00:00'),
    (4, 2, 1, 110000, 'active', '2023-07-01 10:00:00'),
    (5, 3, 1, 80000, 'active', '2023-03-01 10:00:00'),
    (6, 3, 1, 80000, 'terminated', '2023-08-01 10:00:00'),
    (7, 3, 1, 120000, 'active', '2023-10-01 10:00:00'),
    (8, 4, 2, 60000, 'active', '2023-04-01 10:00:00'),
    (9, 4, 2, 70000, 'active', '2023-09-01 10:00:00'),
    (10, 5, 3, 50000, 'active', '2023-05-01 10:00:00'),
    (11, 5, 3, 50000, 'terminated', '2023-11-01 10:00:00'),
    (12, 6, 2, 65000, 'active', '2023-05-15 10:00:00'),
]
EXPECTED_CURRENT = [
    (1, None, 100000),
    (2, 1, 90000),
    (3, 1, 80000),
    (4, 2, 60000),
]


def assert_original_database_is_pristine():
    assert DB_PATH.exists() and DB_PATH.is_file(), f'Database file {DB_PATH} is missing.'
    conn = sqlite3.connect(DB_PATH)
    try:
        objects = conn.execute(
            "SELECT type, name FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_autoindex_%' ORDER BY type, name"
        ).fetchall()
        assert objects == [
            ('table', 'current_employees'),
            ('table', 'employee_events'),
            ('table', 'sqlite_sequence'),
        ], f'The original database schema was modified: {objects!r}'

        event_columns = conn.execute('PRAGMA table_info(employee_events)').fetchall()
        assert [(r[1], r[2], r[3], r[5]) for r in event_columns] == [
            ('event_id', 'INTEGER', 0, 1),
            ('emp_id', 'INTEGER', 0, 0),
            ('manager_id', 'INTEGER', 0, 0),
            ('salary', 'INTEGER', 0, 0),
            ('status', 'VARCHAR(20)', 0, 0),
            ('event_timestamp', 'DATETIME', 0, 0),
        ]
        current_columns = conn.execute('PRAGMA table_info(current_employees)').fetchall()
        assert [(r[1], r[2], r[3], r[5]) for r in current_columns] == [
            ('emp_id', 'INTEGER', 0, 1),
            ('manager_id', 'INTEGER', 0, 0),
            ('salary', 'INTEGER', 0, 0),
        ]
        assert conn.execute(
            'SELECT event_id, emp_id, manager_id, salary, status, event_timestamp '
            'FROM employee_events ORDER BY event_id'
        ).fetchall() == EXPECTED_EVENTS, 'employee_events was modified.'
        assert conn.execute(
            'SELECT emp_id, manager_id, salary FROM current_employees ORDER BY emp_id'
        ).fetchall() == EXPECTED_CURRENT, 'The original database was modified.'
    finally:
        conn.close()


def get_expected_metrics_from_database():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute('''
            WITH RankedEvents AS (
                SELECT emp_id, manager_id, salary, status,
                       ROW_NUMBER() OVER (
                           PARTITION BY emp_id ORDER BY event_timestamp DESC
                       ) AS rn
                FROM employee_events
            ),
            LatestActive AS (
                SELECT emp_id, manager_id, salary
                FROM RankedEvents
                WHERE rn = 1 AND status = 'active'
            ),
            Hierarchy AS (
                SELECT emp_id AS root_id, emp_id, salary FROM LatestActive
                UNION ALL
                SELECT h.root_id, c.emp_id, c.salary
                FROM Hierarchy h
                JOIN LatestActive c ON c.manager_id = h.emp_id
            )
            SELECT root_id AS emp_id,
                   (SELECT salary FROM LatestActive WHERE emp_id = root_id) AS salary,
                   SUM(salary) AS total_org_salary
            FROM Hierarchy
            GROUP BY root_id
            ORDER BY root_id
        ''').fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def independently_compute(events):
    latest = {}
    for emp_id, manager_id, salary, status, timestamp in events:
        if emp_id not in latest or timestamp > latest[emp_id][3]:
            latest[emp_id] = (manager_id, salary, status, timestamp)
    active = {
        emp_id: record for emp_id, record in latest.items() if record[2] == 'active'
    }
    children = {emp_id: [] for emp_id in active}
    for emp_id, (manager_id, _salary, _status, _timestamp) in active.items():
        if manager_id in active:
            children[manager_id].append(emp_id)

    result = []
    for root in sorted(active):
        total = 0
        stack = [root]
        visited = set()
        while stack:
            emp_id = stack.pop()
            assert emp_id not in visited, 'Verifier fixture unexpectedly contains a cycle.'
            visited.add(emp_id)
            total += active[emp_id][1]
            stack.extend(children[emp_id])
        result.append({
            'emp_id': root,
            'salary': active[root][1],
            'total_org_salary': total,
        })
    return result


def assert_json(expected):
    assert OUTPUT_PATH.exists(), f'The output file {OUTPUT_PATH} was not found.'
    assert OUTPUT_PATH.is_file(), f'The path {OUTPUT_PATH} is not a file.'
    try:
        with OUTPUT_PATH.open('r', encoding='utf-8') as handle:
            actual = json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{OUTPUT_PATH} does not contain valid JSON: {exc}')

    assert isinstance(actual, list), 'The JSON output must be a list of dictionaries.'
    assert len(actual) == len(expected), (
        f'Expected {len(expected)} records, but found {len(actual)}.'
    )
    for index, (item, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(item, dict), f'Item at index {index} is not a dictionary.'
        assert set(item) == {'emp_id', 'salary', 'total_org_salary'}, (
            f'Item at index {index} does not have exactly the required fields.'
        )
        assert item == wanted, f'Mismatch at index {index}: expected {wanted}, got {item}.'


def create_fixture(path, events):
    conn = sqlite3.connect(path)
    try:
        conn.execute('''
            CREATE TABLE employee_events (
                event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                emp_id INTEGER,
                manager_id INTEGER,
                salary INTEGER,
                status VARCHAR(20),
                event_timestamp DATETIME
            )
        ''')
        conn.execute('''
            CREATE TABLE current_employees (
                emp_id INTEGER PRIMARY KEY,
                manager_id INTEGER,
                salary INTEGER
            )
        ''')
        conn.executemany('''
            INSERT INTO employee_events
                (emp_id, manager_id, salary, status, event_timestamp)
            VALUES (?, ?, ?, ?, ?)
        ''', events)
        conn.executemany(
            'INSERT INTO current_employees VALUES (?, ?, ?)',
            [(10, None, 1), (20, 10, 1), (999, None, 999999999)],
        )
        conn.commit()
    finally:
        conn.close()


def install_trace_hook(directory):
    hook = pathlib.Path(directory) / 'sitecustomize.py'
    hook.write_text('''
import os
import sqlite3
_real_connect = sqlite3.connect

def _connect(*args, **kwargs):
    connection = _real_connect(*args, **kwargs)
    trace_file = os.environ.get("ORG_SQL_TRACE")
    if trace_file:
        def record(statement):
            try:
                with open(trace_file, "a", encoding="utf-8") as handle:
                    handle.write(statement.replace("\\n", " ") + "\\n")
            except Exception:
                pass
        connection.set_trace_callback(record)
    return connection

sqlite3.connect = _connect
''', encoding='utf-8')


def run_script(hook_dir, trace_path):
    if OUTPUT_PATH.exists() or OUTPUT_PATH.is_symlink():
        OUTPUT_PATH.unlink()
    trace_path.write_text('', encoding='utf-8')
    env = os.environ.copy()
    env['ORG_SQL_TRACE'] = str(trace_path)
    env['PYTHONPATH'] = str(hook_dir) + os.pathsep + env.get('PYTHONPATH', '')
    completed = subprocess.run(
        ['python3', str(SCRIPT_PATH)],
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f'process_org.py failed with exit code {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )
    trace = trace_path.read_text(encoding='utf-8')
    assert re.search(r'\bemployee_events\b', trace, re.IGNORECASE), (
        'The executed script did not query employee_events through SQLite.'
    )
    assert not re.search(r'\bcurrent_employees\b', trace, re.IGNORECASE), (
        'The executed script read the stale current_employees table.'
    )
    assert re.search(r'\bOVER\s*\(', trace, re.IGNORECASE), (
        'The executed SQLite queries did not use a window function.'
    )
    assert re.search(
        r'\b(?:ROW_NUMBER|RANK|DENSE_RANK|FIRST_VALUE|LAST_VALUE|MAX|MIN)\s*\(',
        trace,
        re.IGNORECASE,
    ), 'No supported SQLite window function was executed.'


def test_pipeline_and_database_integrity():
    assert SCRIPT_PATH.exists(), f'The required script {SCRIPT_PATH} was not found.'
    assert SCRIPT_PATH.is_file(), f'{SCRIPT_PATH} is not a regular file.'
    assert_original_database_is_pristine()

    original_db = DB_PATH.read_bytes()
    original_output = None
    hook_dir = tempfile.mkdtemp(prefix='org_verifier_')
    trace_path = pathlib.Path(hook_dir) / 'sql.trace'
    install_trace_hook(hook_dir)

    try:
        # Execute against the original database and preserve the verifier's
        # original content checks, after first establishing that it is pristine.
        run_script(hook_dir, trace_path)
        assert DB_PATH.read_bytes() == original_db, 'process_org.py modified the database.'
        assert_json(get_expected_metrics_from_database())
        original_output = OUTPUT_PATH.read_bytes()

        # Replace the fixed database temporarily with a fresh, unpredictable
        # fixture so a precomputed JSON file cannot pass.
        rng = random.SystemRandom()
        salaries = [rng.randrange(31001, 199999) for _ in range(11)]
        events = [
            (10, None, salaries[0], 'active', '2025-06-01 09:00:00'),
            (10, None, salaries[1], 'active', '2024-01-01 09:00:00'),
            (20, 10, salaries[2], 'active', '2024-02-01 09:00:00'),
            (20, 10, salaries[3], 'active', '2025-07-01 09:00:00'),
            (30, 20, salaries[4], 'active', '2025-01-03 09:00:00'),
            (40, 10, salaries[5], 'active', '2025-01-04 09:00:00'),
            (40, 10, salaries[6], 'terminated', '2025-08-04 09:00:00'),
            (50, 40, salaries[7], 'active', '2025-01-05 09:00:00'),
            (60, 20, salaries[8], 'active', '2024-01-06 09:00:00'),
            (60, 50, salaries[9], 'active', '2025-09-06 09:00:00'),
            (70, 30, salaries[0] + 7, 'terminated', '2024-01-07 09:00:00'),
            (70, 30, salaries[10], 'active', '2025-10-07 09:00:00'),
        ]
        fixture_path = pathlib.Path(hook_dir) / 'fixture.db'
        create_fixture(fixture_path, events)
        fixture_bytes = fixture_path.read_bytes()
        DB_PATH.write_bytes(fixture_bytes)

        run_script(hook_dir, trace_path)
        assert DB_PATH.read_bytes() == fixture_bytes, 'process_org.py modified the database.'
        assert_json(independently_compute(events))
    finally:
        DB_PATH.write_bytes(original_db)
        if original_output is not None:
            OUTPUT_PATH.write_bytes(original_output)
        shutil.rmtree(hook_dir, ignore_errors=True)

    assert_original_database_is_pristine()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
