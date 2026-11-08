#!/bin/bash
set -e
mkdir -p /logs/verifier

DB=/home/user/company_data.db
BACKUP=/tmp/company_data.db.verifier_backup
cp -a "$DB" "$BACKUP"
trap 'cp -a "$BACKUP" "$DB"; rm -f "$BACKUP"' EXIT

mkdir -p /tmp/sql_instrument
cat <<'PY_EOF' > /tmp/sql_instrument/sitecustomize.py
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_SENTINEL = object()


def _log(sql, parameters=_SENTINEL):
    path = os.environ.get("ETL_SQL_TRACE")
    if not path:
        return
    record = {
        "sql": str(sql),
        "parameterized": parameters is not _SENTINEL,
        "params_repr": None if parameters is _SENTINEL else repr(parameters),
    }
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(record) + "\n")


class CursorProxy:
    def __init__(self, inner):
        object.__setattr__(self, "_inner", inner)

    def execute(self, sql, parameters=_SENTINEL):
        _log(sql, parameters)
        if parameters is _SENTINEL:
            self._inner.execute(sql)
        else:
            self._inner.execute(sql, parameters)
        return self

    def executemany(self, sql, seq):
        _log(sql, seq)
        self._inner.executemany(sql, seq)
        return self

    def executescript(self, sql):
        _log(sql)
        self._inner.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._inner)

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        setattr(self._inner, name, value)


class ConnectionProxy:
    def __init__(self, inner):
        object.__setattr__(self, "_inner", inner)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._inner.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_SENTINEL):
        cur = self.cursor()
        return cur.execute(sql, parameters)

    def executemany(self, sql, seq):
        cur = self.cursor()
        return cur.executemany(sql, seq)

    def executescript(self, sql):
        cur = self.cursor()
        return cur.executescript(sql)

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        setattr(self._inner, name, value)


def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))


sqlite3.connect = connect
PY_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import uuid

import pytest

SCRIPT = "/home/user/etl_hierarchy.py"
OUTPUT = "/home/user/hierarchy_cost.json"
DB = "/home/user/company_data.db"
TRACE = "/tmp/etl_sql_trace.jsonl"


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def load_output():
    assert os.path.isfile(OUTPUT), "The output JSON file /home/user/hierarchy_cost.json does not exist."
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("The file /home/user/hierarchy_cost.json does not contain valid JSON.")
    assert isinstance(data, list), "The JSON root must be a list (array)."
    for i, row in enumerate(data):
        assert isinstance(row, dict), f"Record at index {i} is not an object."
        assert "employee_name" in row, f"Record at index {i} is missing 'employee_name'."
        assert "level" in row, f"Record at index {i} is missing 'level'."
        assert "total_asset_cost" in row, f"Record at index {i} is missing 'total_asset_cost'."
        assert set(row) == {"employee_name", "level", "total_asset_cost"}, \
            f"Record at index {i} does not contain exactly the required keys."
        assert isinstance(row["employee_name"], str)
        assert isinstance(row["level"], int) and not isinstance(row["level"], bool)
        assert isinstance(row["total_asset_cost"], (int, float)) and not isinstance(row["total_asset_cost"], bool)
    assert data == sorted(data, key=lambda r: (r["level"], r["employee_name"])), \
        "The JSON array is not sorted by level and then employee_name."
    return data


def read_trace():
    if not os.path.exists(TRACE):
        return []
    with open(TRACE, "r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def run_script(manager, require_recursive=True):
    if os.path.exists(TRACE):
        os.remove(TRACE)
    before = file_hash(DB)
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/sql_instrument" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["ETL_SQL_TRACE"] = TRACE
    result = subprocess.run(
        [sys.executable, SCRIPT, "--manager-name", manager],
        text=True,
        capture_output=True,
        timeout=30,
        env=env,
    )
    assert result.returncode == 0, \
        f"Script failed for manager {manager!r}:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert file_hash(DB) == before, "The script modified /home/user/company_data.db."

    trace = read_trace()
    if require_recursive:
        assert any("with recursive" in " ".join(item["sql"].lower().split()) for item in trace), \
            "No executed SQL statement used a WITH RECURSIVE CTE."
    assert any(
        item["parameterized"]
        and manager in (item["params_repr"] or "")
        and manager not in item["sql"]
        for item in trace
    ), "The --manager-name value was not supplied to an executed query as a parameter."
    return load_output()


def independently_expected(manager):
    conn = sqlite3.connect(DB)
    try:
        root = conn.execute("SELECT id, name FROM employees WHERE name = ? ORDER BY id LIMIT 1", (manager,)).fetchone()
        if root is None:
            return []
        result = []
        frontier = [(root[0], root[1], 0)]
        seen = set()
        while frontier:
            employee_id, name, level = frontier.pop(0)
            if employee_id in seen:
                continue
            seen.add(employee_id)
            total = conn.execute(
                "SELECT COALESCE(SUM(cost), 0) FROM assets WHERE owner_id = ?", (employee_id,)
            ).fetchone()[0]
            result.append({"employee_name": name, "level": level, "total_asset_cost": total})
            children = conn.execute(
                "SELECT id, name FROM employees WHERE manager_id = ? ORDER BY id", (employee_id,)
            ).fetchall()
            frontier.extend((child_id, child_name, level + 1) for child_id, child_name in children)
        return sorted(result, key=lambda r: (r["level"], r["employee_name"]))
    finally:
        conn.close()


def assert_rows(actual, expected):
    assert len(actual) == len(expected), f"Expected {len(expected)} records, but got {len(actual)}."
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got["employee_name"] == want["employee_name"], \
            f"Expected employee_name {want['employee_name']!r} at index {i}, but got {got['employee_name']!r}."
        assert got["level"] == want["level"], \
            f"Expected level {want['level']} for {want['employee_name']}, but got {got['level']}."
        assert float(got["total_asset_cost"]) == float(want["total_asset_cost"]), \
            f"Expected total_asset_cost {want['total_asset_cost']} for {want['employee_name']}, but got {got['total_asset_cost']}."


def test_script_and_pipeline_behavior():
    # Preserve the original existence and source assertions.
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."
    with open(SCRIPT, "r", encoding="utf-8") as f:
        content = f.read().lower()
    assert "recursive" in content, "The script does not seem to use a Recursive CTE (missing 'RECURSIVE' keyword)."
    assert "manager-name" in content or "manager_name" in content, \
        "The script does not seem to define the --manager-name argument."

    expected_alice = [
        {"employee_name": "Alice Smith", "level": 0, "total_asset_cost": 2000},
        {"employee_name": "Bob Jones", "level": 1, "total_asset_cost": 2000},
        {"employee_name": "Charlie Brown", "level": 1, "total_asset_cost": 1500},
        {"employee_name": "Diana Prince", "level": 2, "total_asset_cost": 2500},
        {"employee_name": "Fiona Gallagher", "level": 2, "total_asset_cost": 0},
        {"employee_name": "Evan Wright", "level": 3, "total_asset_cost": 1300},
    ]
    assert_rows(run_script("Alice Smith"), expected_alice)

    # Add an unpredictable hierarchy after the agent has finished, so fixed output cannot pass.
    token = uuid.uuid4().hex
    names = {
        "root": "Verifier Root " + token,
        "alpha": "Verifier Alpha " + token,
        "zeta": "Verifier Zeta " + token,
        "deep": "Verifier Deep " + token,
        "leaf": "Verifier Leaf " + token,
    }
    conn = sqlite3.connect(DB)
    try:
        next_employee = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM employees").fetchone()[0]
        next_asset = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM assets").fetchone()[0]
        ids = {key: next_employee + i for i, key in enumerate(("root", "alpha", "zeta", "deep", "leaf"))}
        conn.executemany(
            "INSERT INTO employees(id, name, manager_id, dept_id) VALUES (?, ?, ?, ?)",
            [
                (ids["root"], names["root"], None, 1),
                (ids["zeta"], names["zeta"], ids["root"], 2),
                (ids["alpha"], names["alpha"], ids["root"], 3),
                (ids["deep"], names["deep"], ids["zeta"], 2),
                (ids["leaf"], names["leaf"], ids["deep"], 2),
            ],
        )
        conn.executemany(
            "INSERT INTO assets(id, asset_name, cost, owner_id) VALUES (?, ?, ?, ?)",
            [
                (next_asset, "Random root asset", 711.25, ids["root"]),
                (next_asset + 1, "Random zeta asset", 19.5, ids["zeta"]),
                (next_asset + 2, "Random zeta asset 2", 80.5, ids["zeta"]),
                (next_asset + 3, "Random leaf asset", 333.75, ids["leaf"]),
            ],
        )
        conn.commit()
    finally:
        conn.close()

    for manager in (names["root"], names["zeta"], names["leaf"]):
        assert_rows(run_script(manager), independently_expected(manager))

    injection = names["root"] + "' OR 1=1 --"
    assert_rows(run_script(injection), independently_expected(injection))

    # Leave the required final artifact generated for Alice Smith.
    assert_rows(run_script("Alice Smith"), expected_alice)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
