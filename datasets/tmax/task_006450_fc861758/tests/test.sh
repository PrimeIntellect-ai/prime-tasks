#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import runpy
import shutil
import sqlite3
import sys
import uuid

import jsonschema
import pytest

SCRIPT_PATH = "/home/user/query_graph.py"
OUTPUT_PATH = "/home/user/output.json"
DB_PATH = "/home/user/graph.db"
SCHEMA_PATH = "/home/user/schema.json"
EXPECTED_KEYS = {
    "employee_name",
    "department_name",
    "project_name",
    "manager_name",
    "manager_department",
}


def get_expected_results(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    SELECT
      A.name as employee_name,
      B.name as department_name,
      C.name as project_name,
      M.name as manager_name,
      D.name as manager_department
    FROM Entity A
    JOIN Relation R1 ON A.id = R1.source_id AND R1.rel_type = 'WORKS_FOR'
    JOIN Entity B ON R1.target_id = B.id AND B.label = 'Department'

    JOIN Relation R2 ON B.id = R2.source_id AND R2.rel_type = 'MANAGES'
    JOIN Entity C ON R2.target_id = C.id AND C.label = 'Project'

    JOIN Relation R3 ON A.id = R3.source_id AND R3.rel_type = 'ASSIGNED_TO' AND R3.target_id = C.id

    JOIN Relation R4 ON A.id = R4.source_id AND R4.rel_type = 'REPORTS_TO'
    JOIN Entity M ON R4.target_id = M.id AND M.label = 'Person'

    JOIN Relation R5 ON M.id = R5.source_id AND R5.rel_type = 'WORKS_FOR'
    JOIN Entity D ON R5.target_id = D.id AND D.label = 'Department'

    WHERE A.label = 'Person' AND B.id != D.id
    ORDER BY A.name ASC;
    """

    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    expected = []
    for row in rows:
        expected.append({
            "employee_name": row[0],
            "department_name": row[1],
            "project_name": row[2],
            "manager_name": row[3],
            "manager_department": row[4],
        })
    return expected


def add_random_match(db_path):
    token = uuid.uuid4().hex
    conn = sqlite3.connect(db_path)
    try:
        first_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM Entity").fetchone()[0]
        employee_id, department_id, project_id, manager_id, manager_department_id = range(first_id, first_id + 5)
        entities = [
            (employee_id, "Employee_" + token, "Person"),
            (department_id, "Department_" + token, "Department"),
            (project_id, "Project_" + token, "Project"),
            (manager_id, "Manager_" + token, "Person"),
            (manager_department_id, "ManagerDepartment_" + token, "Department"),
        ]
        relations = [
            (employee_id, department_id, "WORKS_FOR"),
            (department_id, project_id, "MANAGES"),
            (employee_id, project_id, "ASSIGNED_TO"),
            (employee_id, manager_id, "REPORTS_TO"),
            (manager_id, manager_department_id, "WORKS_FOR"),
        ]
        conn.executemany("INSERT INTO Entity(id, name, label) VALUES (?, ?, ?)", entities)
        conn.executemany("INSERT INTO Relation(source_id, target_id, rel_type) VALUES (?, ?, ?)", relations)
        conn.commit()
    finally:
        conn.close()


class TracingConnection(sqlite3.Connection):
    statements = None

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.set_trace_callback(type(self).statements.append)


def test_script_executes_query_validates_and_writes_correct_output(tmp_path):
    assert os.path.isfile(SCRIPT_PATH), f"Python script is missing at {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), "query_graph.py must be a regular file, not a symlink"

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "query_graph.py is empty"
    ast.parse(source, filename=SCRIPT_PATH)

    backup_path = tmp_path / "graph.db"
    shutil.copy2(DB_PATH, backup_path)

    original_connect = sqlite3.connect
    original_jsonschema_validate = jsonschema.validate
    original_validator_methods = {}
    traced_statements = []
    validation_calls = []

    try:
        add_random_match(DB_PATH)
        expected_data = get_expected_results(DB_PATH)

        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        TracingConnection.statements = traced_statements

        def traced_connect(*args, **kwargs):
            kwargs.setdefault("factory", TracingConnection)
            return original_connect(*args, **kwargs)

        sqlite3.connect = traced_connect

        def wrapped_jsonschema_validate(instance, schema, *args, **kwargs):
            validation_calls.append((instance, schema))
            return original_jsonschema_validate(instance, schema, *args, **kwargs)

        jsonschema.validate = wrapped_jsonschema_validate

        seen_classes = set()
        for name in dir(jsonschema):
            candidate = getattr(jsonschema, name)
            if isinstance(candidate, type) and hasattr(candidate, "validate") and id(candidate) not in seen_classes:
                seen_classes.add(id(candidate))
                original_method = candidate.validate
                original_validator_methods[candidate] = original_method

                def make_wrapper(method):
                    def wrapper(self, instance, *args, **kwargs):
                        validation_calls.append((instance, getattr(self, "schema", None)))
                        return method(self, instance, *args, **kwargs)
                    return wrapper

                candidate.validate = make_wrapper(original_method)

        old_cwd = os.getcwd()
        old_argv = sys.argv[:]
        try:
            os.chdir("/home/user")
            sys.argv = [SCRIPT_PATH]
            try:
                runpy.run_path(SCRIPT_PATH, run_name="__main__")
            except SystemExit as exc:
                assert exc.code in (None, 0), f"query_graph.py exited with status {exc.code}"
        finally:
            os.chdir(old_cwd)
            sys.argv = old_argv

        assert os.path.exists(OUTPUT_PATH), f"Output file is missing at {OUTPUT_PATH}"

        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            try:
                output_data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"File {OUTPUT_PATH} is not valid JSON")

        assert isinstance(output_data, list), "Output JSON must be a list of objects"
        assert len(output_data) == len(expected_data), (
            f"Expected {len(expected_data)} results, but got {len(output_data)}"
        )

        for i, (actual, expected) in enumerate(zip(output_data, expected_data)):
            assert isinstance(actual, dict), f"Item at index {i} is not a JSON object"
            assert set(actual.keys()) == EXPECTED_KEYS, f"Result object at index {i} must have exactly the required keys"
            for key in [
                "employee_name",
                "department_name",
                "project_name",
                "manager_name",
                "manager_department",
            ]:
                assert key in actual, f"Missing key '{key}' in result object at index {i}"
                assert actual[key] == expected[key], (
                    f"Mismatch for key '{key}' at index {i}: expected '{expected[key]}', got '{actual[key]}'"
                )

        with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
            required_schema = json.load(f)
        assert any(instance == output_data and schema == required_schema for instance, schema in validation_calls), (
            "The generated output was not validated against /home/user/schema.json using jsonschema"
        )

        selects = [statement.upper() for statement in traced_statements if statement.lstrip().upper().startswith("SELECT")]
        pattern_queries = [
            statement for statement in selects
            if " JOIN " in statement
            and "ENTITY" in statement
            and "RELATION" in statement
            and all(rel in statement for rel in ["WORKS_FOR", "MANAGES", "ASSIGNED_TO", "REPORTS_TO"])
        ]
        assert pattern_queries, "The script did not execute the required graph-pattern SQL join query"
    finally:
        sqlite3.connect = original_connect
        jsonschema.validate = original_jsonschema_validate
        for validator_class, method in original_validator_methods.items():
            validator_class.validate = method
        shutil.copy2(backup_path, DB_PATH)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
