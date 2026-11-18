#!/bin/bash
set -e
mkdir -p /logs/verifier /tmp/sqltrace

cat <<'PY_EOF' > /tmp/sqltrace/sitecustomize.py
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get("AGGREGATE_SQL_TRACE")

def _record(sql):
    if _trace_path and isinstance(sql, str):
        with open(_trace_path, "a", encoding="utf-8") as f:
            f.write(sql)
            f.write("\n--END-SQL--\n")

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, "_cursor", cursor)

    def execute(self, sql, *args, **kwargs):
        _record(sql)
        return self._cursor.execute(sql, *args, **kwargs)

    def executemany(self, sql, *args, **kwargs):
        _record(sql)
        return self._cursor.executemany(sql, *args, **kwargs)

    def executescript(self, sql, *args, **kwargs):
        _record(sql)
        return self._cursor.executescript(sql, *args, **kwargs)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __iter__(self):
        return iter(self._cursor)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args, **kwargs):
        _record(sql)
        return self._connection.execute(sql, *args, **kwargs)

    def executemany(self, sql, *args, **kwargs):
        _record(sql)
        return self._connection.executemany(sql, *args, **kwargs)

    def executescript(self, sql, *args, **kwargs):
        _record(sql)
        return self._connection.executescript(sql, *args, **kwargs)

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
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import sqlite3
import subprocess

import jsonschema
import pytest

SCRIPT = "/home/user/aggregate.py"
RESULTS = "/home/user/results.json"
DATABASE = "/app/knowledge_graph.db"
SCHEMA = "/app/output_schema.json"
TRACE = "/tmp/aggregate_sql.log"


def run_script(traced=True):
    env = os.environ.copy()
    if traced:
        if os.path.exists(TRACE):
            os.remove(TRACE)
        env["AGGREGATE_SQL_TRACE"] = TRACE
        env["PYTHONPATH"] = "/tmp/sqltrace" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    return subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def load_results():
    assert os.path.exists(RESULTS), f"Output file {RESULTS} does not exist."
    with open(RESULTS, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS} is not valid JSON.")


def assert_original_metric(data):
    assert isinstance(data, list), f"Expected a JSON array in {RESULTS}."

    agent_data = {}
    for item in data:
        assert isinstance(item, dict), "Each item in the array must be a JSON object."
        assert "root_name" in item, "Missing 'root_name' in item."
        assert "total_value" in item, "Missing 'total_value' in item."
        assert isinstance(item["total_value"], (int, float)), "'total_value' must be a number."
        agent_data[item["root_name"]] = item["total_value"]

    reference = {"Alpha": 100.5, "Beta": 45.2}
    agent_keys = set(agent_data.keys())
    ref_keys = set(reference.keys())
    assert agent_keys == ref_keys, f"Extracted target root nodes mismatch. Expected {ref_keys}, got {agent_keys}."

    mse = sum((agent_data[k] - reference[k]) ** 2 for k in reference) / len(reference)
    assert mse <= 0.001, f"MSE of total_value is too high: {mse}. Expected <= 0.001."


def assert_recursive_cte_was_executed():
    assert os.path.exists(TRACE), "The script did not execute SQL through its SQLite connection."
    with open(TRACE, "r", encoding="utf-8") as f:
        sql = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", sql, flags=re.IGNORECASE), \
        "The script did not execute a recursive CTE."


def independently_expected(targets, minimum):
    expected = {}
    with sqlite3.connect(DATABASE) as conn:
        for target in targets:
            row = conn.execute(
                """
                WITH RECURSIVE subtree(id, value) AS (
                    SELECT id, value FROM nodes WHERE name = ?
                    UNION ALL
                    SELECT n.id, n.value
                    FROM nodes AS n
                    JOIN subtree AS s ON n.parent_id = s.id
                )
                SELECT SUM(value) FROM subtree
                """,
                (target,),
            ).fetchone()
            total = row[0]
            if total is not None and total >= minimum:
                expected[target] = total
    return expected


def as_mapping(data):
    assert isinstance(data, list)
    result = {}
    for item in data:
        assert isinstance(item, dict)
        assert set(item) == {"root_name", "total_value"}
        assert isinstance(item["root_name"], str)
        assert isinstance(item["total_value"], (int, float)) and not isinstance(item["total_value"], bool)
        assert item["root_name"] not in result, "Duplicate root node in output."
        result[item["root_name"]] = item["total_value"]
    return result


def test_aggregate_script_and_results():
    assert os.path.isfile(SCRIPT), f"Required Python script {SCRIPT} does not exist."
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    ast.parse(source, filename=SCRIPT)
    assert re.search(r"(^|\n)\s*(import\s+jsonschema\b|from\s+jsonschema\s+import\b)", source), \
        "aggregate.py must use the jsonschema library."

    db_backup = "/tmp/knowledge_graph.db.backup"
    schema_backup = "/tmp/output_schema.json.backup"
    shutil.copy2(DATABASE, db_backup)
    shutil.copy2(SCHEMA, schema_backup)

    try:
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        completed = run_script(traced=True)
        assert completed.returncode == 0, f"aggregate.py failed:\n{completed.stdout}\n{completed.stderr}"
        assert_recursive_cte_was_executed()

        data = load_results()
        assert_original_metric(data)
        with open(SCHEMA, "r", encoding="utf-8") as f:
            jsonschema.validate(data, json.load(f))

        # A schema that rejects every nonempty result must prevent output from
        # being written, demonstrating validation occurs before writing.
        with open(SCHEMA, "w", encoding="utf-8") as f:
            json.dump({"type": "array", "maxItems": 0}, f)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        run_script(traced=False)
        assert not os.path.exists(RESULTS), \
            "aggregate.py wrote results that fail the configured JSON schema."
        shutil.copy2(schema_backup, SCHEMA)

        # Exercise the implementation against a hierarchy and totals not present
        # when the agent created the script, including multiple deep descendants.
        with sqlite3.connect(DATABASE) as conn:
            conn.execute("UPDATE nodes SET value = 1.0 WHERE id = 2")
            conn.execute("UPDATE nodes SET value = 2.0 WHERE id = 3")
            conn.execute("UPDATE nodes SET value = 60.0 WHERE id = 5")
            conn.execute("UPDATE nodes SET value = 0.0 WHERE id = 6")
            conn.execute("INSERT INTO nodes(id, name, parent_id, value) VALUES (9, 'Alpha_deep', 3, 3.0)")
            conn.execute("INSERT INTO nodes(id, name, parent_id, value) VALUES (10, 'Beta_deep', 5, 7.0)")
            conn.execute("INSERT INTO nodes(id, name, parent_id, value) VALUES (11, 'Gamma_deep', 8, 20.0)")
            conn.commit()

        expected = independently_expected(["Alpha", "Beta", "Gamma"], 42.5)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        completed = run_script(traced=True)
        assert completed.returncode == 0, f"aggregate.py failed on changed data:\n{completed.stdout}\n{completed.stderr}"
        assert_recursive_cte_was_executed()
        actual = as_mapping(load_results())
        assert set(actual) == set(expected), f"Expected roots {set(expected)}, got {set(actual)}."
        for name, value in expected.items():
            assert abs(actual[name] - value) <= 0.0001, \
                f"Incorrect dynamic aggregate for {name}: expected {value}, got {actual[name]}."
    finally:
        shutil.copy2(db_backup, DATABASE)
        shutil.copy2(schema_backup, SCHEMA)
        if os.path.isfile(SCRIPT):
            run_script(traced=False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
