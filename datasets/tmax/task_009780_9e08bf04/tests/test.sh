#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_instrument
cat <<'PYEOF' > /tmp/verifier_instrument/sitecustomize.py
import sqlite3

SQL_LOG = "/tmp/verifier_sql.log"
SPARQL_LOG = "/tmp/verifier_sparql.log"

def _log(path, value):
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(str(value).replace("\x00", "") + "\n---\n")
    except Exception:
        pass

_real_connect = sqlite3.connect

class _CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor
    def execute(self, sql, *args, **kwargs):
        _log(SQL_LOG, sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self
    def executemany(self, sql, *args, **kwargs):
        _log(SQL_LOG, sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self
    def executescript(self, sql, *args, **kwargs):
        _log(SQL_LOG, sql)
        self._cursor.executescript(sql, *args, **kwargs)
        return self
    def __iter__(self):
        return iter(self._cursor)
    def __getattr__(self, name):
        return getattr(self._cursor, name)

class _ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection
    def cursor(self, *args, **kwargs):
        return _CursorProxy(self._connection.cursor(*args, **kwargs))
    def execute(self, sql, *args, **kwargs):
        _log(SQL_LOG, sql)
        return _CursorProxy(self._connection.execute(sql, *args, **kwargs))
    def executemany(self, sql, *args, **kwargs):
        _log(SQL_LOG, sql)
        return _CursorProxy(self._connection.executemany(sql, *args, **kwargs))
    def executescript(self, sql, *args, **kwargs):
        _log(SQL_LOG, sql)
        return _CursorProxy(self._connection.executescript(sql, *args, **kwargs))
    def __enter__(self):
        self._connection.__enter__()
        return self
    def __exit__(self, *args):
        return self._connection.__exit__(*args)
    def __getattr__(self, name):
        return getattr(self._connection, name)

def _connect(*args, **kwargs):
    return _ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = _connect

try:
    from rdflib.graph import Graph
    _real_query = Graph.query
    def _query(self, query_object, *args, **kwargs):
        _log(SPARQL_LOG, query_object)
        return _real_query(self, query_object, *args, **kwargs)
    Graph.query = _query
except Exception:
    pass
PYEOF

cat <<'PYEOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import uuid
from pathlib import Path

HOME = Path("/home/user")
DATA_PATH = HOME / "data.ttl"
DB_PATH = HOME / "org.db"
JSON_PATH = HOME / "dept_summary.json"
SQL_LOG = Path("/tmp/verifier_sql.log")
SPARQL_LOG = Path("/tmp/verifier_sparql.log")

ORIGINAL_DEPARTMENTS = {
    ("Engineering", "Corporation"),
    ("Backend", "Engineering"),
    ("Frontend", "Engineering"),
    ("Sales", "Corporation"),
    ("Enterprise Sales", "Sales"),
}
ORIGINAL_EMPLOYEES = {
    ("Alice", "Backend"),
    ("Bob", "Frontend"),
    ("Charlie", "Sales"),
    ("Dave", "Engineering"),
    ("Eve", "Enterprise Sales"),
}


def find_script():
    candidates = []
    for path in HOME.rglob("*.py"):
        if not path.is_file() or any(part.startswith(".") for part in path.relative_to(HOME).parts):
            continue
        try:
            source = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        required = sum(name in source for name in ("data.ttl", "org.db", "dept_summary.json"))
        if required == 3:
            score = required * 20
            score += sum(token.lower() in source.lower() for token in
                         ("rdflib", "sparql", "sqlite3", "with recursive", "/home/user/data.ttl"))
            candidates.append((score, str(path), path))
    assert candidates, "No end-to-end Python script referencing data.ttl, org.db, and dept_summary.json was found."
    candidates.sort(reverse=True)
    return candidates[0][2]


def run_script(script):
    for marker in (SQL_LOG, SPARQL_LOG):
        marker.unlink(missing_ok=True)
    DB_PATH.unlink(missing_ok=True)
    JSON_PATH.unlink(missing_ok=True)
    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = "/tmp/verifier_instrument" + ((":" + old_pythonpath) if old_pythonpath else "")
    result = subprocess.run(
        ["python3", str(script)], cwd=str(HOME), env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, (
        f"Python script did not run end-to-end (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert DB_PATH.exists() and DB_PATH.is_file(), f"Database file {DB_PATH} is missing."
    assert JSON_PATH.exists() and JSON_PATH.is_file(), f"Summary JSON file {JSON_PATH} is missing."

    sparql = SPARQL_LOG.read_text(encoding="utf-8", errors="ignore") if SPARQL_LOG.exists() else ""
    sql = SQL_LOG.read_text(encoding="utf-8", errors="ignore") if SQL_LOG.exists() else ""
    sparql_lower = sparql.lower()
    assert "select" in sparql_lower, "The executed script did not execute a SPARQL SELECT query."
    assert "parentdept" in sparql_lower, "Executed SPARQL did not query department parent relationships."
    assert "worksin" in sparql_lower, "Executed SPARQL did not query employee assignments."
    assert "with recursive" in sql.lower(), "The executed script did not execute a recursive SQLite CTE."


def read_and_check_database(expected_departments, expected_employees):
    conn = sqlite3.connect(str(DB_PATH))
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in cursor.fetchall()]
        assert "departments" in tables, "Table 'departments' is missing in org.db."
        assert "employees" in tables, "Table 'employees' is missing in org.db."

        cursor.execute("PRAGMA table_info(departments);")
        dept_info = cursor.fetchall()
        dept_cols = {row[1]: row[2].upper() for row in dept_info}
        assert "dept_name" in dept_cols, "Column 'dept_name' missing in 'departments' table."
        assert "parent_name" in dept_cols, "Column 'parent_name' missing in 'departments' table."
        assert [(r[1], r[2].upper()) for r in dept_info] == [
            ("dept_name", "TEXT"), ("parent_name", "TEXT")
        ], "The departments table does not have the exact required schema."

        cursor.execute("PRAGMA table_info(employees);")
        emp_info = cursor.fetchall()
        emp_cols = {row[1]: row[2].upper() for row in emp_info}
        assert "emp_name" in emp_cols, "Column 'emp_name' missing in 'employees' table."
        assert "dept_name" in emp_cols, "Column 'dept_name' missing in 'employees' table."
        assert [(r[1], r[2].upper()) for r in emp_info] == [
            ("emp_name", "TEXT"), ("dept_name", "TEXT")
        ], "The employees table does not have the exact required schema."

        cursor.execute("SELECT COUNT(*) FROM departments;")
        assert cursor.fetchone()[0] >= 5, "Not enough departments extracted into the database."
        cursor.execute("SELECT COUNT(*) FROM employees;")
        assert cursor.fetchone()[0] >= 5, "Not enough employees extracted into the database."

        cursor.execute("SELECT dept_name, parent_name FROM departments")
        dept_rows = cursor.fetchall()
        cursor.execute("SELECT emp_name, dept_name FROM employees")
        emp_rows = cursor.fetchall()
    finally:
        conn.close()

    non_root = {(name, parent) for name, parent in dept_rows if name != "Corporation"}
    root_rows = [(name, parent) for name, parent in dept_rows if name == "Corporation"]
    assert len(dept_rows) == len(set(dept_rows)), "Duplicate department rows were materialized."
    assert non_root == expected_departments, "Department rows do not accurately match the RDF graph."
    assert len(root_rows) <= 1, "Corporation was materialized more than once."
    if root_rows:
        assert root_rows[0][1] in (None, ""), "Corporation must not have a parent."
    assert len(emp_rows) == len(set(emp_rows)), "Duplicate employee rows were materialized."
    assert set(emp_rows) == expected_employees, "Employee rows do not accurately match the RDF graph."


def read_summary(expected):
    try:
        with JSON_PATH.open("r", encoding="utf-8") as f:
            summary = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{JSON_PATH} is not a valid JSON file: {exc}")
    assert isinstance(summary, dict), "JSON summary should be a dictionary."
    assert set(summary) == set(expected), "JSON contains missing or extra top-level departments."
    assert all(type(v) is int for v in summary.values()), "Every summary count must be an integer."
    assert summary == expected, "Aggregated employee counts are incorrect."
    return summary


def make_hidden_fixture():
    suffix = uuid.uuid4().hex[:10]
    names = {
        "a": f"Platform_{suffix}", "a1": f"Runtime_{suffix}", "a2": f"Kernel_{suffix}",
        "b": f"Markets_{suffix}", "b1": f"Regional_{suffix}",
        "c": f"Research_{suffix}", "c1": f"Labs_{suffix}",
    }
    employees = [(f"Person{i}_{suffix}", dept) for i, dept in enumerate(
        (names["a"], names["a1"], names["a2"], names["a2"], names["b"], names["b1"], names["c1"]), 1)]
    departments = [
        (names["a"], "Corporation"), (names["a1"], names["a"]),
        (names["a2"], names["a1"]), (names["b"], "Corporation"),
        (names["b1"], names["b"]), (names["c"], "Corporation"),
        (names["c1"], names["c"]),
    ]
    id_for_name = {"Corporation": "Corp"}
    for i, (name, _) in enumerate(departments, 1):
        id_for_name[name] = f"Dept{i}"

    lines = [
        "@prefix org: <http://example.org/org#> .",
        "@prefix foaf: <http://xmlns.com/foaf/0.1/> .",
        'org:Corp a org:Department ; foaf:name "Corporation" .',
    ]
    for name, parent in departments:
        lines.append(f'org:{id_for_name[name]} a org:Department ; foaf:name "{name}" ; org:parentDept org:{id_for_name[parent]} .')
    for i, (person, dept) in enumerate(employees, 1):
        lines.append(f'org:Employee{i} a foaf:Person ; foaf:name "{person}" ; org:worksIn org:{id_for_name[dept]} .')
    expected_summary = {names["a"]: 4, names["b"]: 2, names["c"]: 1}
    return "\n".join(lines) + "\n", set(departments), set(employees), expected_summary


def test_complete_end_to_end_solution():
    script = find_script()
    saved = {}
    for path in (DATA_PATH, DB_PATH, JSON_PATH):
        saved[path] = path.read_bytes() if path.exists() and path.is_file() else None
    try:
        # Execute against the supplied graph, rather than trusting pre-created artifacts.
        run_script(script)
        read_and_check_database(ORIGINAL_DEPARTMENTS, ORIGINAL_EMPLOYEES)
        summary = read_summary({"Engineering": 3, "Sales": 2})
        assert "Engineering" in summary, "Missing 'Engineering' top-level department in JSON."
        assert "Sales" in summary, "Missing 'Sales' top-level department in JSON."
        assert summary["Engineering"] == 3, f"Expected 3 employees under Engineering, got {summary['Engineering']}"
        assert summary["Sales"] == 2, f"Expected 2 employees under Sales, got {summary['Sales']}"

        # A runtime-random graph prevents hardcoded rows and counts from passing.
        ttl, departments, employees, expected_summary = make_hidden_fixture()
        DATA_PATH.write_text(ttl, encoding="utf-8")
        run_script(script)
        read_and_check_database(departments, employees)
        read_summary(expected_summary)
    finally:
        for path, content in saved.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
PYEOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
