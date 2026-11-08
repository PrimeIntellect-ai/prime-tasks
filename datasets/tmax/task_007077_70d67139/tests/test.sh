#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import runpy
import shutil
import sqlite3
import sys
import tempfile
import uuid

DB_PATH = '/home/user/services.db'
SCRIPT_PATH = '/home/user/analyze.py'
CSV_PATH = '/home/user/critical_services.csv'
HEADERS = ['rank', 'service_id', 'service_name', 'dependent_count']

EXPECTED_ORIGINAL = [
    {'rank': '1', 'service_id': '4', 'service_name': 'user_db', 'dependent_count': '6'},
    {'rank': '2', 'service_id': '3', 'service_name': 'auth_service', 'dependent_count': '4'},
    {'rank': '2', 'service_id': '8', 'service_name': 'product_db', 'dependent_count': '4'},
    {'rank': '3', 'service_id': '7', 'service_name': 'inventory_service', 'dependent_count': '2'},
    {'rank': '4', 'service_id': '2', 'service_name': 'api_gateway', 'dependent_count': '1'},
    {'rank': '4', 'service_id': '5', 'service_name': 'payment_service', 'dependent_count': '1'},
    {'rank': '5', 'service_id': '1', 'service_name': 'frontend', 'dependent_count': '0'},
    {'rank': '5', 'service_id': '6', 'service_name': 'checkout_ui', 'dependent_count': '0'},
    {'rank': '5', 'service_id': '9', 'service_name': 'recommendation_engine', 'dependent_count': '0'},
    {'rank': '5', 'service_id': '10', 'service_name': 'analytics_service', 'dependent_count': '0'},
]

_evaluated = False
_dynamic_trace = []


def read_csv(path):
    assert os.path.exists(path), f'The output CSV file {path} is missing.'
    assert os.path.isfile(path), f'{path} is not a file.'
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADERS, 'CSV headers are incorrect.'
        rows = list(reader)
    try:
        for row in rows:
            assert set(row) == set(HEADERS), 'CSV contains missing or extra columns.'
            int(row['rank'])
            int(row['service_id'])
            int(row['dependent_count'])
    except (TypeError, ValueError, KeyError) as exc:
        assert False, f'CSV contains invalid data types or missing columns: {exc}'
    return rows


def sorted_rows(rows):
    return sorted(rows, key=lambda r: (int(r['rank']), int(r['service_id'])))


def expected_from_graph(services, edges):
    callers_by_callee = {service_id: set() for service_id, _ in services}
    for caller, callee in edges:
        callers_by_callee[callee].add(caller)

    counts = {}
    for service_id, _ in services:
        seen = set()
        stack = list(callers_by_callee[service_id])
        while stack:
            dependent = stack.pop()
            if dependent == service_id or dependent in seen:
                continue
            seen.add(dependent)
            stack.extend(callers_by_callee[dependent])
        counts[service_id] = len(seen)

    distinct_counts = sorted(set(counts.values()), reverse=True)
    ranks = {count: rank for rank, count in enumerate(distinct_counts, 1)}
    names = dict(services)
    return [
        {
            'rank': str(ranks[counts[service_id]]),
            'service_id': str(service_id),
            'service_name': names[service_id],
            'dependent_count': str(counts[service_id]),
        }
        for service_id, _ in services
        if ranks[counts[service_id]] <= 5
    ]


def run_analyzer_with_trace():
    statements = []
    real_connect = sqlite3.connect

    def traced_connect(*args, **kwargs):
        conn = real_connect(*args, **kwargs)
        conn.set_trace_callback(statements.append)
        return conn

    old_argv = sys.argv[:]
    sqlite3.connect = traced_connect
    sys.argv = [SCRIPT_PATH]
    try:
        runpy.run_path(SCRIPT_PATH, run_name='__main__')
    finally:
        sqlite3.connect = real_connect
        sys.argv = old_argv
    return statements


def create_dynamic_database(path):
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 10000), 10)
    services = [(sid, 'svc_' + uuid.uuid4().hex) for sid in ids]

    # A chain supplies at least seven distinct dependent counts. Skip edges create
    # multiple paths to the same dependent, exercising the uniqueness requirement.
    edges = [(ids[i], ids[i + 1]) for i in range(6)]
    edges += [(ids[0], ids[2]), (ids[1], ids[3]), (ids[2], ids[4]),
              (ids[0], ids[4]), (ids[3], ids[5])]

    conn = sqlite3.connect(path)
    try:
        conn.execute('CREATE TABLE services (id INTEGER PRIMARY KEY, service_name TEXT NOT NULL)')
        conn.execute('CREATE TABLE dependencies (caller_id INTEGER, callee_id INTEGER, FOREIGN KEY(caller_id) REFERENCES services(id), FOREIGN KEY(callee_id) REFERENCES services(id))')
        conn.executemany('INSERT INTO services VALUES (?, ?)', services)
        conn.executemany('INSERT INTO dependencies VALUES (?, ?)', edges)
        conn.commit()
    finally:
        conn.close()
    return services, edges


def evaluate_submission():
    global _evaluated, _dynamic_trace
    if _evaluated:
        return
    _evaluated = True

    assert os.path.exists(SCRIPT_PATH), f'The script file {SCRIPT_PATH} is missing.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file.'
    assert os.path.exists(DB_PATH), f'The database file {DB_PATH} is missing.'

    workdir = tempfile.mkdtemp(prefix='verifier_')
    initial_backup = os.path.join(workdir, 'initial.db')
    postrun_backup = os.path.join(workdir, 'postrun.db')
    dynamic_db = os.path.join(workdir, 'dynamic.db')
    saved_csv = None
    shutil.copy2(DB_PATH, initial_backup)

    try:
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        run_analyzer_with_trace()
        original_rows = read_csv(CSV_PATH)
        assert sorted_rows(original_rows) == sorted_rows(EXPECTED_ORIGINAL), (
            f'CSV contents do not match the expected top five dense ranks. '
            f'Expected: {sorted_rows(EXPECTED_ORIGINAL)}, Got: {sorted_rows(original_rows)}'
        )
        with open(CSV_PATH, 'rb') as f:
            saved_csv = f.read()
        shutil.copy2(DB_PATH, postrun_backup)

        services, edges = create_dynamic_database(dynamic_db)
        expected_dynamic = expected_from_graph(services, edges)
        shutil.copy2(dynamic_db, DB_PATH)
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)

        _dynamic_trace = run_analyzer_with_trace()
        dynamic_rows = read_csv(CSV_PATH)
        assert sorted_rows(dynamic_rows) == sorted_rows(expected_dynamic), (
            'analyze.py did not compute the correct result for a fresh dependency graph.'
        )

        candidates = [
            statement for statement in _dynamic_trace
            if 'with recursive' in statement.lower()
            and 'dense_rank' in statement.lower()
            and ' over' in statement.lower()
        ]
        assert len(candidates) == 1, (
            'analyze.py must execute one SQL query containing both a recursive CTE '
            'and a DENSE_RANK window function.'
        )

        conn = sqlite3.connect(DB_PATH)
        try:
            cursor = conn.execute(candidates[0])
            assert cursor.description is not None, 'The recursive SQL query returned no result set.'
            column_names = [column[0] for column in cursor.description]
            assert column_names == HEADERS, (
                f'The recursive SQL query must return columns {HEADERS}; got {column_names}.'
            )
            query_rows = [dict(zip(HEADERS, map(str, row))) for row in cursor.fetchall()]
        finally:
            conn.close()
        assert sorted_rows(query_rows) == sorted_rows(expected_dynamic), (
            'The executed recursive/window SQL query itself did not produce the required top-five results.'
        )
    finally:
        restore = postrun_backup if os.path.exists(postrun_backup) else initial_backup
        shutil.copy2(restore, DB_PATH)
        if saved_csv is None:
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)
        else:
            with open(CSV_PATH, 'wb') as f:
                f.write(saved_csv)
        shutil.rmtree(workdir, ignore_errors=True)


def test_csv_exists_and_correct():
    evaluate_submission()
    actual_rows = read_csv(CSV_PATH)
    assert sorted_rows(actual_rows) == sorted_rows(EXPECTED_ORIGINAL), (
        f'CSV contents do not match the expected top critical services. '
        f'Expected: {sorted_rows(EXPECTED_ORIGINAL)}, Got: {sorted_rows(actual_rows)}'
    )


def test_indexes_created():
    evaluate_submission()
    assert os.path.exists(DB_PATH), f'The database file {DB_PATH} is missing.'
    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='dependencies'").fetchall()
        assert len(indexes) > 0, "No indexes were created on the 'dependencies' table to optimize hierarchical querying."
        usable = False
        for (name,) in indexes:
            escaped = name.replace("'", "''")
            columns = conn.execute(f"PRAGMA index_info('{escaped}')").fetchall()
            if columns and columns[0][2] == 'callee_id':
                usable = True
                break
        assert usable, "No dependency index has callee_id as its leading column for reverse hierarchical traversal."
    finally:
        conn.close()


def test_analyze_script_exists():
    evaluate_submission()
    assert os.path.exists(SCRIPT_PATH), f'The script file {SCRIPT_PATH} is missing.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
