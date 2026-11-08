#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import sqlite3
import statistics
import time
import pytest

RESULTS_PATH = '/home/user/optimized_results.json'
DB_PATH = '/home/user/company.db'
QUERIES_PATH = '/home/user/queries.sql'
SCHEMA_PATH = '/home/user/schema.json'

EXPECTED_QUERIES = [
    "SELECT d.dept_name, AVG(s.amount) FROM employees e JOIN salaries s ON e.emp_id = s.emp_id JOIN departments d ON e.dept_id = d.dept_id GROUP BY d.dept_name",
    "SELECT emp_name FROM employees WHERE hire_date > '2022-01-01'",
    "SELECT e.emp_name, s.amount FROM employees e JOIN salaries s ON e.emp_id = s.emp_id WHERE s.amount > 140000",
]

EXPECTED_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "query_id": {"type": "string", "pattern": "^query_[0-9]+$"},
            "row_count": {"type": "integer", "minimum": 0},
            "execution_time_ms": {"type": "number", "minimum": 0},
        },
        "required": ["query_id", "row_count", "execution_time_ms"],
        "additionalProperties": False,
    },
}


def normalized_sql(sql):
    return re.sub(r'\s+', ' ', sql.strip().rstrip(';').strip())


def load_queries():
    assert os.path.isfile(QUERIES_PATH), f"Queries file missing: {QUERIES_PATH}"
    with open(QUERIES_PATH, encoding='utf-8') as f:
        queries = [q.strip() for q in f.read().split(';') if q.strip()]
    assert len(queries) == 3, "Expected 3 queries in queries.sql"
    assert [normalized_sql(q) for q in queries] == [normalized_sql(q) for q in EXPECTED_QUERIES], \
        "queries.sql was modified from the supplied analytical workload"
    return queries


def load_results():
    assert os.path.isfile(RESULTS_PATH), f"Expected results file not found at {RESULTS_PATH}"
    with open(RESULTS_PATH, encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON: {exc}")


def open_db():
    assert os.path.isfile(DB_PATH), f"Database file missing: {DB_PATH}"
    return sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)


def test_supplied_inputs_and_database_were_not_rewritten():
    load_queries()
    assert os.path.isfile(SCHEMA_PATH), f"Schema file missing: {SCHEMA_PATH}"
    with open(SCHEMA_PATH, encoding='utf-8') as f:
        assert json.load(f) == EXPECTED_SCHEMA, "schema.json was modified"

    with open_db() as conn:
        assert conn.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        objects = conn.execute("SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").fetchall()
        assert {name for typ, name in objects if typ == 'table'} == {'employees', 'departments', 'salaries'}
        assert not [(typ, name) for typ, name in objects if typ in ('view', 'trigger')], \
            "Unexpected views or triggers were added"

        expected_columns = {
            'departments': [('dept_id', 'INTEGER', 1), ('dept_name', 'TEXT', 0)],
            'employees': [('emp_id', 'INTEGER', 1), ('emp_name', 'TEXT', 0), ('dept_id', 'INTEGER', 0), ('hire_date', 'TEXT', 0)],
            'salaries': [('emp_id', 'INTEGER', 0), ('amount', 'REAL', 0), ('effective_date', 'TEXT', 0)],
        }
        for table, expected in expected_columns.items():
            actual = [(r[1], r[2].upper(), r[5]) for r in conn.execute(f'PRAGMA table_info({table})')]
            assert actual == expected, f"Unexpected schema for {table}: {actual}"

        assert conn.execute('SELECT COUNT(*) FROM departments').fetchone()[0] == 5
        assert conn.execute('SELECT COUNT(*) FROM employees').fetchone()[0] == 10000
        assert conn.execute('SELECT COUNT(*) FROM salaries').fetchone()[0] == 30000
        assert conn.execute('SELECT group_concat(dept_id || ":" || dept_name, "|") FROM (SELECT * FROM departments ORDER BY dept_id)').fetchone()[0] == \
            '1:Engineering|2:Sales|3:Marketing|4:HR|5:Finance'
        assert conn.execute("SELECT COUNT(*) FROM employees WHERE emp_id NOT BETWEEN 1 AND 10000 OR emp_name != 'Employee_' || emp_id OR dept_id NOT BETWEEN 1 AND 5 OR hire_date < '2015-01-01' OR hire_date > '2023-03-20'").fetchone()[0] == 0
        assert conn.execute('SELECT COUNT(*) FROM (SELECT emp_id FROM employees GROUP BY emp_id HAVING COUNT(*) != 1)').fetchone()[0] == 0
        assert conn.execute('SELECT COUNT(*) FROM salaries WHERE emp_id NOT BETWEEN 1 AND 10000 OR amount < 50000 OR amount > 150000').fetchone()[0] == 0
        assert conn.execute('SELECT COUNT(*) FROM (SELECT emp_id FROM salaries GROUP BY emp_id HAVING COUNT(*) != 3)').fetchone()[0] == 0
        bad_salary_dates = conn.execute("""
            SELECT COUNT(*) FROM salaries s JOIN employees e USING(emp_id)
            WHERE s.effective_date NOT IN (
                e.hire_date, date(e.hire_date, '+365 days'), date(e.hire_date, '+730 days')
            )
        """).fetchone()[0]
        assert bad_salary_dates == 0
        assert conn.execute('SELECT COUNT(DISTINCT hire_date) FROM employees').fetchone()[0] > 2500
        dept_counts = [r[0] for r in conn.execute('SELECT COUNT(*) FROM employees GROUP BY dept_id')]
        assert len(dept_counts) == 5 and all(1500 <= n <= 2500 for n in dept_counts)


def test_results_file_exists_and_valid_json():
    results = load_results()
    assert isinstance(results, list), "JSON root must be an array"
    assert len(results) == 3, f"Expected exactly 3 query results, but got {len(results)}"


def test_results_schema_conformance():
    results = load_results()
    for i, res in enumerate(results):
        assert isinstance(res, dict), f"Item at index {i} is not a JSON object"
        expected_keys = {'query_id', 'row_count', 'execution_time_ms'}
        assert set(res.keys()) == expected_keys, f"Item at index {i} has incorrect keys"
        assert isinstance(res['query_id'], str)
        assert res['query_id'] == f'query_{i+1}'
        assert isinstance(res['row_count'], int) and not isinstance(res['row_count'], bool)
        assert res['row_count'] >= 0
        timing = res['execution_time_ms']
        assert isinstance(timing, (int, float)) and not isinstance(timing, bool)
        assert math.isfinite(timing) and timing > 0, f"query_{i+1} must contain a finite, positive measured execution time"


def test_results_row_counts_and_timings_match_execution():
    results = load_results()
    queries = load_queries()
    with open_db() as conn:
        for i, query in enumerate(queries):
            samples = []
            rows = None
            for _ in range(3):
                start = time.perf_counter_ns()
                current_rows = conn.execute(query).fetchall()
                elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000.0
                samples.append(elapsed_ms)
                if rows is None:
                    rows = current_rows
            actual_count = len(rows)
            assert results[i]['row_count'] == actual_count, \
                f"Row count mismatch for query_{i+1}: expected {actual_count}, got {results[i]['row_count']}"
            observed = statistics.median(samples)
            reported = float(results[i]['execution_time_ms'])
            assert observed / 100.0 <= reported <= observed * 100.0 + 1.0, \
                f"Reported timing for query_{i+1} is implausible relative to actual execution"


def test_indexes_created_and_used_for_workload():
    with open_db() as conn:
        indexes = conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'").fetchall()
        assert len(indexes) >= 2, f"Expected at least 2 custom indexes created for optimization, found {len(indexes)}: {indexes}"

        leading_columns = {}
        for (name,) in indexes:
            escaped = name.replace("'", "''")
            columns = [r[2] for r in conn.execute(f"PRAGMA index_info('{escaped}')")]
            if columns:
                leading_columns[name] = columns[0]

        assert 'hire_date' in leading_columns.values(), \
            f"No index has employees.hire_date as its leading search column: {leading_columns}"
        assert 'amount' in leading_columns.values(), \
            f"No index has salaries.amount as its leading search column: {leading_columns}"

        q2_plan = ' | '.join(r[3] for r in conn.execute('EXPLAIN QUERY PLAN ' + EXPECTED_QUERIES[1])).upper()
        q3_plan = ' | '.join(r[3] for r in conn.execute('EXPLAIN QUERY PLAN ' + EXPECTED_QUERIES[2])).upper()
        assert 'SEARCH EMPLOYEES USING' in q2_plan and 'HIRE_DATE' in q2_plan, \
            f"hire_date query does not use an appropriate search index: {q2_plan}"
        assert 'SEARCH S USING' in q3_plan and 'AMOUNT' in q3_plan, \
            f"salary threshold query does not use an appropriate search index: {q3_plan}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
