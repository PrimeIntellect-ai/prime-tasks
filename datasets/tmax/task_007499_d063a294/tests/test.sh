#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/export_metrics.py"
OUTPUT_PATH = "/home/user/metrics_output.json"
DB_PATH = "/home/user/company.db"
SCHEMA_PATH = "/home/user/schema.json"


def get_expected_data(db_path):
    query = """
    WITH RECURSIVE
      hierarchy AS (
        SELECT id, name, manager_id, department, salary, 0 AS hierarchy_level
        FROM employees
        WHERE manager_id IS NULL
        UNION ALL
        SELECT e.id, e.name, e.manager_id, e.department, e.salary, h.hierarchy_level + 1
        FROM employees e
        JOIN hierarchy h ON e.manager_id = h.id
      )
    SELECT
      id,
      name,
      department,
      salary,
      hierarchy_level,
      SUM(salary) OVER(PARTITION BY department) AS dept_total_salary,
      RANK() OVER(PARTITION BY department ORDER BY salary DESC) AS dept_salary_rank
    FROM hierarchy;
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(query).fetchall()
    finally:
        conn.close()
    return [{
        "id": row["id"],
        "name": row["name"],
        "department": row["department"],
        "salary": row["salary"],
        "hierarchy_level": row["hierarchy_level"],
        "dept_total_salary": row["dept_total_salary"],
        "dept_salary_rank": row["dept_salary_rank"],
    } for row in rows]


def database_state(path):
    conn = sqlite3.connect(path)
    try:
        schema = conn.execute(
            "SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name"
        ).fetchall()
        rows = conn.execute(
            "SELECT id, name, manager_id, department, salary FROM employees ORDER BY id"
        ).fetchall()
        return schema, rows
    finally:
        conn.close()


def make_dynamic_database(path):
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(path + suffix)
        except FileNotFoundError:
            pass

    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 9000), 10)
    tag = uuid.uuid4().hex[:10]
    eng = "Engineering_" + tag
    sales = "Sales_" + tag
    ops = "Operations_" + tag
    executive = "Executive_" + tag
    tie_salary = rng.randrange(110000, 150000)

    employees = [
        (ids[0], "Root_" + tag, None, executive, rng.randrange(210000, 260000)),
        (ids[1], "EngLead_" + tag, ids[0], eng, rng.randrange(170000, 200000)),
        (ids[2], "SalesLead_" + tag, ids[0], sales, rng.randrange(155000, 175000)),
        (ids[3], "EngineerA_" + tag, ids[1], eng, tie_salary),
        (ids[4], "EngineerB_" + tag, ids[1], eng, tie_salary),
        (ids[5], "SalesA_" + tag, ids[2], sales, rng.randrange(90000, 120000)),
        (ids[6], "DeepEngineer_" + tag, ids[3], eng, rng.randrange(70000, 100000)),
        (ids[7], "OpsLead_" + tag, ids[0], ops, rng.randrange(130000, 155000)),
        (ids[8], "OpsA_" + tag, ids[7], ops, rng.randrange(80000, 110000)),
        (ids[9], "VeryDeep_" + tag, ids[6], eng, rng.randrange(50000, 75000)),
    ]
    rng.shuffle(employees)

    conn = sqlite3.connect(path)
    try:
        conn.execute(
            "CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, department TEXT, salary INTEGER)"
        )
        conn.executemany("INSERT INTO employees VALUES (?, ?, ?, ?, ?)", employees)
        conn.commit()
    finally:
        conn.close()


def install_sql_instrumentation(directory):
    code = r'''
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_log_path = os.environ.get("METRICS_SQL_LOG")

def _record(operation, sql):
    if not _log_path:
        return
    with open(_log_path, "a", encoding="utf-8") as f:
        f.write(json.dumps({"operation": operation, "sql": str(sql)}) + "\\n")

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, "_cursor", cursor)
    def execute(self, sql, *args, **kwargs):
        _record("execute", sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self
    def executemany(self, sql, *args, **kwargs):
        _record("executemany", sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self
    def executescript(self, sql, *args, **kwargs):
        _record("executescript", sql)
        self._cursor.executescript(sql, *args, **kwargs)
        return self
    def __iter__(self):
        return iter(self._cursor)
    def __enter__(self):
        self._cursor.__enter__()
        return self
    def __exit__(self, *args):
        return self._cursor.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._cursor, name)
    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)
    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))
    def execute(self, sql, *args, **kwargs):
        _record("execute", sql)
        return CursorProxy(self._connection.execute(sql, *args, **kwargs))
    def executemany(self, sql, *args, **kwargs):
        _record("executemany", sql)
        return CursorProxy(self._connection.executemany(sql, *args, **kwargs))
    def executescript(self, sql, *args, **kwargs):
        _record("executescript", sql)
        return CursorProxy(self._connection.executescript(sql, *args, **kwargs))
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)
    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(code)


def run_submission(instrument_dir, log_path):
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass
    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = instrument_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["METRICS_SQL_LOG"] = log_path
    return subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


def read_sql_log(path):
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def assert_single_required_query(entries):
    assert len(entries) == 1, f"Expected exactly one SQL execution, observed: {entries}"
    assert entries[0]["operation"] == "execute", "The database work must use one execute call"
    sql = entries[0]["sql"]
    normalized = re.sub(r"\s+", " ", sql).upper()
    assert re.search(r"\bWITH\s+RECURSIVE\b", normalized), "SQL must use a recursive CTE"
    assert re.search(r"\bSUM\s*\([^)]*\)\s*OVER\s*\(", normalized), "SQL must use SUM as a window function"
    assert re.search(r"\bRANK\s*\(\s*\)\s*OVER\s*\(", normalized), "SQL must use the RANK window function"
    assert normalized.count("OVER") >= 2, "Both department metrics must be computed with window functions"
    assert normalized.count("PARTITION BY") >= 2, "Window functions must partition by department"


def test_script_execution_output_query_and_schema_validation():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCHEMA_PATH), f"Schema not found at {SCHEMA_PATH}"

    work = tempfile.mkdtemp(prefix="metrics_verifier_")
    db_backup = os.path.join(work, "company.db.backup")
    schema_backup = os.path.join(work, "schema.json.backup")
    instrument_dir = os.path.join(work, "instrument")
    log_path = os.path.join(work, "sql.jsonl")
    os.mkdir(instrument_dir)
    shutil.copy2(DB_PATH, db_backup)
    shutil.copy2(SCHEMA_PATH, schema_backup)
    install_sql_instrumentation(instrument_dir)

    try:
        make_dynamic_database(DB_PATH)
        expected_data = get_expected_data(DB_PATH)
        state_before = database_state(DB_PATH)

        try:
            os.remove(OUTPUT_PATH)
        except FileNotFoundError:
            pass

        result = run_submission(instrument_dir, log_path)
        assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"
        assert os.path.isfile(OUTPUT_PATH), f"Output file not generated at {OUTPUT_PATH}"

        with open(OUTPUT_PATH, encoding="utf-8") as f:
            try:
                output_data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"Output file {OUTPUT_PATH} is not valid JSON.")

        assert isinstance(output_data, list), "Output JSON must be a list of objects."
        output_data_sorted = sorted(output_data, key=lambda x: x.get("id", -1))
        expected_data_sorted = sorted(expected_data, key=lambda x: x["id"])
        assert len(output_data_sorted) == len(expected_data_sorted), \
            f"Expected {len(expected_data_sorted)} records, got {len(output_data_sorted)}"
        for actual, expected in zip(output_data_sorted, expected_data_sorted):
            assert actual == expected, f"Record mismatch. Expected: {expected}, Got: {actual}"

        assert database_state(DB_PATH) == state_before, "The submitted script modified the source database"
        assert_single_required_query(read_sql_log(log_path))

        with open(SCHEMA_PATH, encoding="utf-8") as f:
            bad_schema = json.load(f)
        bad_schema = copy.deepcopy(bad_schema)
        bad_schema["items"]["properties"]["salary"]["maximum"] = -1
        with open(SCHEMA_PATH, "w", encoding="utf-8") as f:
            json.dump(bad_schema, f)

        os.remove(OUTPUT_PATH)
        run_submission(instrument_dir, log_path)
        assert not os.path.exists(OUTPUT_PATH), \
            "Script wrote output even though the supplied JSON schema rejected every record"
        assert database_state(DB_PATH) == state_before, "The submitted script modified the source database"
        assert_single_required_query(read_sql_log(log_path))
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(db_backup, DB_PATH)
        shutil.copy2(schema_backup, SCHEMA_PATH)
        shutil.rmtree(work, ignore_errors=True)
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
