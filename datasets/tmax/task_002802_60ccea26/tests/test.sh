#!/bin/bash
set -e
mkdir -p /logs/verifier

CSV_PATH=/home/user/employees.csv
CSV_BACKUP=$(mktemp)
cp "$CSV_PATH" "$CSV_BACKUP"
restore_csv() {
    cp "$CSV_BACKUP" "$CSV_PATH"
    rm -f "$CSV_BACKUP"
}
trap restore_csv EXIT

mkdir -p /tmp/org_verifier_py
cat <<'PY_EOF' > /tmp/org_verifier_py/sitecustomize.py
import json
import os
import sqlite3

_original_connect = sqlite3.connect
_log_path = os.environ.get("ORG_SQL_LOG")


def _record(sql, parameters=None):
    if not _log_path:
        return
    try:
        entry = {"sql": str(sql), "parameters": parameters}
        with open(_log_path, "a", encoding="utf-8") as f:
            json.dump(entry, f, default=str)
            f.write("\n")
    except Exception:
        pass


class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=()):
        _record(sql, parameters)
        self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        materialized = list(seq_of_parameters)
        _record(sql, materialized)
        self._cursor.executemany(sql, materialized)
        return self

    def executescript(self, sql_script):
        _record(sql_script, None)
        self._cursor.executescript(sql_script)
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

    def execute(self, sql, parameters=()):
        _record(sql, parameters)
        return CursorProxy(self._connection.execute(sql, parameters))

    def executemany(self, sql, seq_of_parameters):
        materialized = list(seq_of_parameters)
        _record(sql, materialized)
        return CursorProxy(self._connection.executemany(sql, materialized))

    def executescript(self, sql_script):
        _record(sql_script, None)
        return CursorProxy(self._connection.executescript(sql_script))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)


def connect(*args, **kwargs):
    return ConnectionProxy(_original_connect(*args, **kwargs))


sqlite3.connect = connect
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import subprocess

SCRIPT_PATH = "/home/user/org_query.py"
OUTPUT_PATH = "/home/user/output.json"
CSV_PATH = "/home/user/employees.csv"
TRACE_PATH = "/tmp/org_query_sql.jsonl"
TRACE_PYTHONPATH = "/tmp/org_verifier_py"


def _flatten(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from _flatten(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from _flatten(item)
    else:
        yield value


def run_script(emp_id):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = TRACE_PYTHONPATH + (os.pathsep + old_pythonpath if old_pythonpath else "")
    env["ORG_SQL_LOG"] = TRACE_PATH
    return subprocess.run(
        ["python3", SCRIPT_PATH, str(emp_id)],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )


def load_strict_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert type(data) is dict, "Output JSON must be an object."
    assert set(data) == {"manager_id", "total_employees", "total_salary"}, "Output JSON has an incorrect schema."
    for key in ("manager_id", "total_employees", "total_salary"):
        assert type(data[key]) is int, f"{key} must be a JSON integer."
    return data


def assert_recursive_parameterized_query(emp_id):
    assert os.path.isfile(TRACE_PATH), "The script did not connect to SQLite through sqlite3.connect."
    entries = []
    with open(TRACE_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                entries.append(json.loads(line))

    matching = []
    for entry in entries:
        sql = entry.get("sql", "").lower()
        values = list(_flatten(entry.get("parameters")))
        bound_target = any(str(value) == str(emp_id) for value in values)
        if "with recursive" in sql and "employees" in sql and bound_target:
            matching.append(entry)
    assert matching, "No executed recursive CTE over employees used the manager ID as a bound SQL parameter."


def assert_success(emp_id, expected_count, expected_salary):
    result = run_script(emp_id)
    assert result.returncode == 0, f"Script failed for emp_id {emp_id} with error: {result.stderr}"
    assert result.stdout == "", "The script must not print anything to standard output."
    data = load_strict_output()
    assert data.get("manager_id") == emp_id, "Incorrect manager_id in output."
    assert data.get("total_employees") == expected_count, f"Incorrect total_employees for emp_id {emp_id}."
    assert data.get("total_salary") == expected_salary, f"Incorrect total_salary for emp_id {emp_id}."
    assert_recursive_parameterized_query(emp_id)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_script_logic_and_output_emp_2():
    assert_success(2, 6, 650000)


def test_script_logic_and_output_emp_3():
    assert_success(3, 3, 340000)


def test_script_logic_and_output_emp_1():
    assert_success(1, 10, 1190000)


def test_script_uses_recursive_cte():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        content = f.read().lower()

    assert "with recursive" in content or "with " in content, "Script does not appear to use a CTE (WITH RECURSIVE)."
    assert "?" in content or ":" in content or "%s" in content, "Script does not appear to use parameterized queries."


def test_randomized_hierarchy_and_arbitrary_manager_ids():
    rng = random.SystemRandom()
    ids = rng.sample(range(10000, 900000), 18)
    rows = []
    managers = {}
    salaries = {}

    for index, emp_id in enumerate(ids):
        manager_id = None if index == 0 else ids[rng.randrange(index)]
        salary = rng.randrange(31, 301) * 1000 + rng.randrange(0, 997)
        managers[emp_id] = manager_id
        salaries[emp_id] = salary
        rows.append({
            "emp_id": emp_id,
            "name": f"Employee_{index}_{rng.randrange(1000000)}",
            "manager_id": "" if manager_id is None else manager_id,
            "salary": salary,
        })

    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["emp_id", "name", "manager_id", "salary"])
        writer.writeheader()
        writer.writerows(rows)

    children = {emp_id: [] for emp_id in ids}
    for emp_id, manager_id in managers.items():
        if manager_id is not None:
            children[manager_id].append(emp_id)

    def expected(target):
        stack = [target]
        descendants = []
        while stack:
            current = stack.pop()
            descendants.append(current)
            stack.extend(children[current])
        return len(descendants), sum(salaries[item] for item in descendants)

    internal = next(emp_id for emp_id in ids if children[emp_id] and emp_id != ids[0])
    leaf = next(emp_id for emp_id in reversed(ids) if not children[emp_id])
    additional = rng.sample(ids, 4)
    targets = list(dict.fromkeys([ids[0], internal, leaf] + additional))

    for target in targets:
        count, total_salary = expected(target)
        assert_success(target, count, total_salary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
