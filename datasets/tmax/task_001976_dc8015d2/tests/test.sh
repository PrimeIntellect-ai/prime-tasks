#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import textwrap
import uuid

import jsonschema
import pytest

SCRIPT = '/home/user/generate_report.py'
DB = '/home/user/company.db'
SCHEMA = '/home/user/schema.json'
REPORT = '/home/user/report.json'
TRACE = '/tmp/sql_trace.json'
RUNNER = '/tmp/run_report_traced.py'


def run_script(traced=False):
    if not traced:
        return subprocess.run([sys.executable, SCRIPT], cwd='/home/user', capture_output=True, text=True)

    with open(RUNNER, 'w') as f:
        f.write(textwrap.dedent(r'''
            import json
            import os
            import runpy
            import sqlite3

            trace = []
            real_connect = sqlite3.connect
            sentinel = object()

            def record(sql, parameters):
                trace.append({"sql": sql, "parameters": None if parameters is sentinel else parameters})

            class CursorProxy:
                def __init__(self, inner):
                    self._inner = inner

                def execute(self, sql, parameters=sentinel):
                    record(sql, parameters)
                    if parameters is sentinel:
                        self._inner.execute(sql)
                    else:
                        self._inner.execute(sql, parameters)
                    return self

                def executemany(self, sql, seq):
                    values = list(seq)
                    trace.append({"sql": sql, "parameters": values})
                    self._inner.executemany(sql, values)
                    return self

                def __iter__(self):
                    return iter(self._inner)

                def __getattr__(self, name):
                    return getattr(self._inner, name)

            class ConnectionProxy:
                def __init__(self, inner):
                    self._inner = inner

                def cursor(self, *args, **kwargs):
                    return CursorProxy(self._inner.cursor(*args, **kwargs))

                def execute(self, sql, parameters=sentinel):
                    record(sql, parameters)
                    if parameters is sentinel:
                        return CursorProxy(self._inner.execute(sql))
                    return CursorProxy(self._inner.execute(sql, parameters))

                def __enter__(self):
                    self._inner.__enter__()
                    return self

                def __exit__(self, *args):
                    return self._inner.__exit__(*args)

                def __getattr__(self, name):
                    return getattr(self._inner, name)

            def connect(*args, **kwargs):
                return ConnectionProxy(real_connect(*args, **kwargs))

            sqlite3.connect = connect
            try:
                runpy.run_path('/home/user/generate_report.py', run_name='__main__')
            finally:
                with open('/tmp/sql_trace.json', 'w') as out:
                    json.dump(trace, out, default=repr)
        '''))
    return subprocess.run([sys.executable, RUNNER], cwd='/home/user', capture_output=True, text=True)


def load_report():
    assert os.path.exists(REPORT), f"The output file was not found at {REPORT}. Did you save the report?"
    with open(REPORT, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT} does not contain valid JSON.")


def sorted_report(data):
    try:
        return sorted(data, key=lambda x: (x.get('emp1', ''), x.get('emp2', '')))
    except (TypeError, AttributeError):
        pytest.fail("The JSON output contains elements that are not comparable or missing expected string fields.")


def test_report_and_implementation_behavior():
    assert os.path.exists(SCRIPT), f"Script file missing: {SCRIPT}"
    with open(SCRIPT, 'r') as f:
        content = f.read()

    # Preserve the original implementation assertions.
    assert 'report.json' in content, "The script doesn't seem to reference 'report.json'."
    assert 'json.dump' in content or 'json.dumps' in content, "The script doesn't seem to use the json module to save the data."

    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = run_script()
    assert result.returncode == 0, result.stderr or result.stdout

    report_data = load_report()
    assert isinstance(report_data, list), f"The JSON root in {REPORT} must be an array (list)."
    expected_data = [
        {"emp1": "Alice", "emp2": "Bob", "weight": 5, "dept_name": "Engineering"},
        {"emp1": "Alice", "emp2": "Dave", "weight": 3, "dept_name": "Engineering"},
    ]
    assert sorted_report(report_data) == sorted_report(expected_data), (
        "The contents of report.json do not match the expected output. "
        "Check if you correctly fixed the implicit cross join in the SQL query."
    )
    with open(SCHEMA) as f:
        jsonschema.validate(report_data, json.load(f))

    db_backup = DB + '.verifier_backup'
    schema_backup = SCHEMA + '.verifier_backup'
    shutil.copy2(DB, db_backup)
    shutil.copy2(SCHEMA, schema_backup)

    token = uuid.uuid4().hex[:10]
    dept1 = 'Engineering_' + token
    dept2 = 'Sales_' + token
    emp_a = 'A_' + token
    emp_b = 'B_' + token
    emp_c = 'C_' + token
    emp_x = 'X_' + token
    weight1 = 20 + int(token[0], 16)
    weight2 = 50 + int(token[1], 16)

    expected_dynamic = [
        {"emp1": emp_a, "emp2": emp_b, "weight": weight1, "dept_name": dept1},
        {"emp1": emp_c, "emp2": emp_a, "weight": weight2, "dept_name": dept1},
    ]

    try:
        os.remove(DB)
        conn = sqlite3.connect(DB)
        conn.executescript('''
            CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER);
            CREATE TABLE collaborations (emp_id_1 INTEGER, emp_id_2 INTEGER, weight INTEGER);
        ''')
        conn.executemany('INSERT INTO departments VALUES (?, ?)', [(1, dept1), (2, dept2), (3, 'Unused_' + token)])
        conn.executemany('INSERT INTO employees VALUES (?, ?, ?)', [
            (201, emp_a, 1), (202, emp_b, 2), (203, emp_c, 1), (204, emp_x, 2)
        ])
        conn.executemany('INSERT INTO collaborations VALUES (?, ?, ?)', [
            (201, 202, weight1), (203, 201, weight2), (204, 201, 99)
        ])
        conn.commit()
        conn.close()

        if os.path.exists(REPORT):
            os.remove(REPORT)
        if os.path.exists(TRACE):
            os.remove(TRACE)
        result = run_script(traced=True)
        assert result.returncode == 0, result.stderr or result.stdout

        dynamic_report = load_report()
        assert isinstance(dynamic_report, list)
        assert sorted_report(dynamic_report) == sorted_report(expected_dynamic), (
            "The script did not derive the report from the database with departments linked "
            "to the first employee's department."
        )
        with open(SCHEMA) as f:
            jsonschema.validate(dynamic_report, json.load(f))

        assert os.path.exists(TRACE), "No SQL execution was observed while running the report script."
        with open(TRACE) as f:
            trace = json.load(f)

        expected_rows = sorted((x['emp1'], x['emp2'], x['weight'], x['dept_name']) for x in expected_dynamic)
        qualifying_query = False
        conn = sqlite3.connect(DB)
        for call in trace:
            sql = call.get('sql')
            params = call.get('parameters')
            if not isinstance(sql, str) or not sql.lstrip().lower().startswith('select') or params is None:
                continue
            values = list(params.values()) if isinstance(params, dict) else list(params) if isinstance(params, (list, tuple)) else [params]
            if 1 not in values:
                continue
            try:
                rows = conn.execute(sql, params).fetchall()
            except Exception:
                continue
            try:
                if sorted(tuple(row) for row in rows) == expected_rows:
                    qualifying_query = True
                    break
            except TypeError:
                pass
        conn.close()
        assert qualifying_query, (
            "The executed report SELECT must remain parameterized with department ID 1 and must itself "
            "produce the correctly joined collaboration rows."
        )

        # Replace the schema with one that rejects the generated rows. A validating
        # implementation must not create report.json containing unvalidated data.
        with open(SCHEMA) as f:
            rejecting_schema = json.load(f)
        rejecting_schema['items']['properties']['emp1']['maxLength'] = 0
        with open(SCHEMA, 'w') as f:
            json.dump(rejecting_schema, f)
        if os.path.exists(REPORT):
            os.remove(REPORT)
        run_script()
        assert not os.path.exists(REPORT), (
            "report.json was written even though the generated data fails the supplied JSON schema; "
            "validate the data before saving it."
        )
    finally:
        shutil.move(db_backup, DB)
        shutil.move(schema_backup, SCHEMA)
        if os.path.exists(REPORT):
            os.remove(REPORT)
        final_result = run_script()
        assert final_result.returncode == 0, final_result.stderr or final_result.stdout
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
