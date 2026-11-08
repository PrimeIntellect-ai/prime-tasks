#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import re
import runpy
import subprocess
import sys
import time

import psycopg2
import pytest
import redis


def expected_ids(start_id):
    sql_query = f"""
    WITH RECURSIVE traverse AS (
        SELECT bj.id, bj.job_name, bj.status, bj.created_at
        FROM job_dependencies jd
        JOIN backup_jobs bj ON bj.id = jd.child_job_id
        WHERE jd.parent_job_id = {int(start_id)}
        UNION
        SELECT bj.id, bj.job_name, bj.status, bj.created_at
        FROM backup_jobs bj
        JOIN job_dependencies jd ON jd.child_job_id = bj.id
        JOIN traverse t ON t.id = jd.parent_job_id
    )
    SELECT id FROM (
        SELECT id, created_at,
               ROW_NUMBER() OVER (PARTITION BY job_name ORDER BY created_at DESC) AS rn
        FROM traverse
    ) sub
    WHERE rn = 1
    ORDER BY created_at ASC;
    """

    psql_cmd = [
        "psql", "-U", "postgres", "-d", "backups",
        "-t", "-A", "-c", sql_query
    ]
    proc = subprocess.run(psql_cmd, capture_output=True, text=True)
    assert proc.returncode == 0, f"Failed to query database for expected results: {proc.stderr}"
    return [int(line) for line in proc.stdout.splitlines() if line.strip()]


@pytest.mark.parametrize("start_id", [45, 19990])
def test_execution_time_and_redis_output(start_id):
    r = redis.Redis(host="localhost", port=6379, db=0, decode_responses=True)
    key = f"restore_chain:{start_id}"
    r.delete(key)

    start = time.time()
    proc = subprocess.run(
        ["python3", "/app/backup_extractor.py", str(start_id)],
        capture_output=True,
        text=True,
    )
    duration = time.time() - start

    assert proc.returncode == 0, f"Script failed with error: {proc.stderr}"
    assert duration <= 0.5, f"Execution time {duration:.3f}s exceeded 0.5s threshold."

    result_str = r.get(key)
    assert result_str is not None, f"Redis key '{key}' is missing."

    try:
        actual_ids = json.loads(result_str)
    except json.JSONDecodeError:
        pytest.fail(f"Redis value is not valid JSON: {result_str}")

    assert isinstance(actual_ids, list), "Redis value must be a JSON array."
    expected = expected_ids(start_id)
    assert actual_ids == expected, f"Expected IDs {expected}, but got {actual_ids}"


def test_executed_query_uses_recursive_cte_and_window_function():
    queries = []
    real_connect = psycopg2.connect

    class CursorProxy:
        def __init__(self, cursor):
            self._cursor = cursor

        def execute(self, query, *args, **kwargs):
            queries.append(str(query))
            return self._cursor.execute(query, *args, **kwargs)

        def executemany(self, query, *args, **kwargs):
            queries.append(str(query))
            return self._cursor.executemany(query, *args, **kwargs)

        def __getattr__(self, name):
            return getattr(self._cursor, name)

        def __iter__(self):
            return iter(self._cursor)

        def __enter__(self):
            self._cursor.__enter__()
            return self

        def __exit__(self, *args):
            return self._cursor.__exit__(*args)

    class ConnectionProxy:
        def __init__(self, connection):
            self._connection = connection

        def cursor(self, *args, **kwargs):
            return CursorProxy(self._connection.cursor(*args, **kwargs))

        def __getattr__(self, name):
            return getattr(self._connection, name)

        def __enter__(self):
            self._connection.__enter__()
            return self

        def __exit__(self, *args):
            return self._connection.__exit__(*args)

    def recording_connect(*args, **kwargs):
        return ConnectionProxy(real_connect(*args, **kwargs))

    old_argv = sys.argv[:]
    psycopg2.connect = recording_connect
    try:
        sys.argv = ["/app/backup_extractor.py", "19990"]
        try:
            runpy.run_path("/app/backup_extractor.py", run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"Script exited with status {exc.code}"
    finally:
        psycopg2.connect = real_connect
        sys.argv = old_argv

    qualifying = []
    for query in queries:
        if re.search(r"\bWITH\s+RECURSIVE\b", query, re.IGNORECASE) and re.search(
            r"\bOVER\b", query, re.IGNORECASE
        ):
            qualifying.append(query)

    assert qualifying, (
        "The script did not execute a SQL statement containing both a recursive CTE "
        "and a window function."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
