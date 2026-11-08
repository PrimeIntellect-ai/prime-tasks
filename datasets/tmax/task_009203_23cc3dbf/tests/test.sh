#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import sqlite3
import subprocess
import textwrap
import uuid

CSV_PATH = "/home/user/unauthorized_access.csv"
PY_SCRIPT_PATH = "/home/user/audit_query.py"
SH_SCRIPT_PATH = "/home/user/generate_report.sh"
DB_PATH = "/home/user/audit.db"


def test_csv_report_exists_and_correct():
    assert os.path.isfile(CSV_PATH), f"Report file missing at {CSV_PATH}"

    with open(CSV_PATH, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 4, f"Expected 4 lines in CSV (header + 3 rows), found {len(content)}"

    expected_lines = [
        "ID,Name",
        "101,Alice_Admin",
        "102,Bob_Manager",
        "103,Charlie_Staff"
    ]

    for i, expected in enumerate(expected_lines):
        assert content[i].strip() == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{content[i].strip()}'"


def test_python_script_exists_and_parameterized():
    assert os.path.isfile(PY_SCRIPT_PATH), f"Python script missing at {PY_SCRIPT_PATH}"

    with open(PY_SCRIPT_PATH, "r") as f:
        code = f.read()

    # Preserve the original source-level assertions.
    assert "execute" in code, "The Python script does not seem to execute any SQL queries."
    has_param_marker = re.search(r'\?|:\w+|%\w+', code)
    assert has_param_marker, "The Python script does not appear to use SQL parameterization (no ?, :name, or %s found)."
    assert "sys.argv" in code or "argparse" in code, "The Python script must take the resource name as a command-line argument."


def test_bash_script_exists():
    assert os.path.isfile(SH_SCRIPT_PATH), f"Bash script missing at {SH_SCRIPT_PATH}"

    with open(SH_SCRIPT_PATH, "r") as f:
        code = f.read()

    assert "audit_query.py" in code, "The bash script does not seem to call the Python script."
    assert "CONFIDENTIAL_FINANCE_RECORDS" in code, "The bash script does not pass the correct resource name parameter."


def reference_rows(resource_name):
    conn = sqlite3.connect(DB_PATH)
    try:
        parents = {}
        for group_id, parent_id in conn.execute("SELECT group_id, parent_group_id FROM groups"):
            parents.setdefault(parent_id, set()).add(group_id)

        accessible = {
            row[0] for row in conn.execute(
                "SELECT group_id FROM permissions WHERE resource_name = ?",
                (resource_name,),
            )
        }
        frontier = list(accessible)
        while frontier:
            parent = frontier.pop()
            for child in parents.get(parent, ()):
                if child not in accessible:
                    accessible.add(child)
                    frontier.append(child)

        if not accessible:
            return []
        placeholders = ",".join("?" for _ in accessible)
        query = (
            "SELECT DISTINCT e.emp_id, e.name "
            "FROM employees e JOIN group_members gm ON gm.emp_id = e.emp_id "
            f"WHERE gm.group_id IN ({placeholders}) ORDER BY e.emp_id"
        )
        return list(conn.execute(query, tuple(accessible)))
    finally:
        conn.close()


def test_scripts_execute_real_recursive_parameterized_query_and_dynamic_pipeline(tmp_path):
    backup_db = tmp_path / "audit.db.backup"
    source = sqlite3.connect(DB_PATH)
    backup = sqlite3.connect(str(backup_db))
    source.backup(backup)
    source.close()
    backup.close()

    old_csv = open(CSV_PATH, "rb").read() if os.path.exists(CSV_PATH) else None
    token = uuid.uuid4().hex
    dynamic_resource = "DYNAMIC_RESOURCE_" + token
    dynamic_name_1 = "DynamicRoot_" + token
    dynamic_name_2 = "DynamicDescendant_" + token
    pipeline_name = "PipelineDescendant_" + token

    wrapper = tmp_path / "run_instrumented.py"
    trace_path = tmp_path / "sql_trace.json"
    wrapper.write_text(textwrap.dedent(r'''
        import json
        import runpy
        import sqlite3
        import sys

        real_connect = sqlite3.connect
        calls = []

        class CursorProxy:
            def __init__(self, cursor):
                self._cursor = cursor
            def execute(self, sql, *args):
                calls.append({"sql": str(sql), "params": repr(args[0]) if args else None})
                self._cursor.execute(sql, *args)
                return self
            def executemany(self, sql, *args):
                calls.append({"sql": str(sql), "params": repr(args[0]) if args else None})
                self._cursor.executemany(sql, *args)
                return self
            def __iter__(self):
                return iter(self._cursor)
            def __getattr__(self, name):
                return getattr(self._cursor, name)

        class ConnectionProxy:
            def __init__(self, connection):
                self._connection = connection
            def cursor(self, *args, **kwargs):
                return CursorProxy(self._connection.cursor(*args, **kwargs))
            def execute(self, sql, *args):
                calls.append({"sql": str(sql), "params": repr(args[0]) if args else None})
                return CursorProxy(self._connection.execute(sql, *args))
            def executemany(self, sql, *args):
                calls.append({"sql": str(sql), "params": repr(args[0]) if args else None})
                return CursorProxy(self._connection.executemany(sql, *args))
            def __enter__(self):
                self._connection.__enter__()
                return self
            def __exit__(self, *args):
                return self._connection.__exit__(*args)
            def __getattr__(self, name):
                return getattr(self._connection, name)

        def instrumented_connect(*args, **kwargs):
            return ConnectionProxy(real_connect(*args, **kwargs))

        sqlite3.connect = instrumented_connect
        script, resource, trace_file = sys.argv[1:4]
        sys.argv = [script, resource]
        try:
            runpy.run_path(script, run_name="__main__")
        finally:
            with open(trace_file, "w") as f:
                json.dump(calls, f)
    '''))

    try:
        conn = sqlite3.connect(DB_PATH)
        max_group = conn.execute("SELECT COALESCE(MAX(group_id), 0) FROM groups").fetchone()[0]
        max_emp = conn.execute("SELECT COALESCE(MAX(emp_id), 0) FROM employees").fetchone()[0]
        g_root, g_child, g_grandchild, g_pipeline = [max_group + i for i in range(1, 5)]
        e_root, e_descendant, e_pipeline = [max_emp + i for i in range(1, 4)]

        conn.executemany(
            "INSERT INTO groups(group_id, parent_group_id, name) VALUES (?, ?, ?)",
            [
                (g_root, None, "DynamicRootGroup_" + token),
                (g_child, g_root, "DynamicChildGroup_" + token),
                (g_grandchild, g_child, "DynamicGrandchildGroup_" + token),
                (g_pipeline, 3, "PipelineChildGroup_" + token),
            ],
        )
        conn.executemany(
            "INSERT INTO employees(emp_id, name) VALUES (?, ?)",
            [(e_root, dynamic_name_1), (e_descendant, dynamic_name_2), (e_pipeline, pipeline_name)],
        )
        conn.executemany(
            "INSERT INTO group_members(emp_id, group_id) VALUES (?, ?)",
            [(e_root, g_root), (e_descendant, g_grandchild), (e_pipeline, g_pipeline)],
        )
        conn.execute(
            "INSERT INTO permissions(group_id, resource_name) VALUES (?, ?)",
            (g_root, dynamic_resource),
        )
        conn.commit()
        conn.close()

        expected_dynamic = reference_rows(dynamic_resource)
        result = subprocess.run(
            ["python3", str(wrapper), PY_SCRIPT_PATH, dynamic_resource, str(trace_path)],
            text=True,
            capture_output=True,
            timeout=15,
        )
        assert result.returncode == 0, f"Python extractor failed: {result.stderr}"
        actual_dynamic = [line for line in result.stdout.strip().splitlines() if line]
        expected_tsv = [f"{emp_id}\t{name}" for emp_id, name in expected_dynamic]
        assert actual_dynamic == expected_tsv, (
            f"Extractor output for a verifier-created resource was incorrect. "
            f"Expected {expected_tsv}, got {actual_dynamic}"
        )

        calls = json.loads(trace_path.read_text())
        qualifying = []
        for call in calls:
            sql = call.get("sql", "")
            lowered = sql.lower()
            params = call.get("params")
            if (
                re.search(r"\bwith\s+recursive\b", lowered)
                and all(name in lowered for name in ("groups", "permissions", "group_members", "employees"))
                and params is not None
                and dynamic_resource in params
                and dynamic_resource not in sql
            ):
                qualifying.append(call)
        assert qualifying, (
            "No executed SQL statement both used WITH RECURSIVE over the access-control tables "
            "and received the command-line resource through a bound parameter."
        )

        expected_pipeline = reference_rows("CONFIDENTIAL_FINANCE_RECORDS")
        report_run = subprocess.run(
            ["bash", SH_SCRIPT_PATH],
            text=True,
            capture_output=True,
            timeout=15,
        )
        assert report_run.returncode == 0, f"Reporting pipeline failed: {report_run.stderr}"
        assert os.path.isfile(CSV_PATH), f"Report file missing at {CSV_PATH} after running pipeline"
        with open(CSV_PATH, newline="") as f:
            report_rows = list(csv.reader(f))
        expected_csv = [["ID", "Name"]] + [[str(emp_id), name] for emp_id, name in expected_pipeline]
        assert report_rows == expected_csv, (
            "The executed reporting pipeline did not reflect current database contents. "
            f"Expected {expected_csv}, got {report_rows}"
        )
    finally:
        for suffix in ("", "-wal", "-shm"):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(backup_db, DB_PATH)
        if old_csv is None:
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)
        else:
            with open(CSV_PATH, "wb") as f:
                f.write(old_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
