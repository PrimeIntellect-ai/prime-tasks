#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import sqlite3
import pytest

DB_PATH = "/home/user/org.db"
CSV_PATH = "/home/user/org_chart.csv"
JSON_PATH = "/home/user/deep_org.json"


def csv_rows():
    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        rows = []
        for row in csv.DictReader(f):
            rows.append((
                int(row["id"]),
                row["name"],
                None if row["manager_id"] == "" else int(row["manager_id"]),
            ))
    return rows


def expected_from_csv():
    rows = csv_rows()
    children = {}
    roots = []
    for employee_id, _name, manager_id in rows:
        if manager_id is None:
            roots.append(employee_id)
        else:
            children.setdefault(manager_id, []).append(employee_id)

    result = []
    stack = [(root, [root]) for root in roots]
    while stack:
        employee_id, path = stack.pop()
        if len(path) >= 4:
            result.append({"id": employee_id, "path": "->".join(map(str, path))})
        for child in children.get(employee_id, []):
            stack.append((child, path + [child]))
    return sorted(result, key=lambda item: item["id"])


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} does not exist."


def test_employees_schema_and_import():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} does not exist."
    with sqlite3.connect(DB_PATH) as conn:
        schema = conn.execute("PRAGMA table_info(employees)").fetchall()
        assert schema, "The employees table does not exist."
        assert [column[1] for column in schema] == ["id", "name", "manager_id"], \
            "employees must contain exactly id, name, and manager_id columns."

        declared_types = {column[1]: (column[2] or "").upper() for column in schema}
        assert "INT" in declared_types["id"], "employees.id must have integer affinity."
        assert "INT" in declared_types["manager_id"], \
            "employees.manager_id must have integer affinity."

        actual = conn.execute(
            "SELECT id, name, manager_id, typeof(id), typeof(manager_id) "
            "FROM employees ORDER BY id"
        ).fetchall()

    expected = []
    for employee_id, name, manager_id in sorted(csv_rows()):
        expected.append((
            employee_id,
            name,
            manager_id,
            "integer",
            "null" if manager_id is None else "integer",
        ))
    assert actual == expected, \
        "employees must exactly contain the CSV rows with integer IDs and a NULL root manager_id."


def test_index_exists():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_manager';")
    result = cursor.fetchone()

    assert result is not None, "The index 'idx_manager' does not exist in the database."
    assert result[0] == 'idx_manager', "The index 'idx_manager' was not found."

    index_owner = cursor.execute(
        "SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_manager'"
    ).fetchone()
    indexed_columns = cursor.execute("PRAGMA index_info('idx_manager')").fetchall()
    conn.close()

    assert index_owner == ("employees",), "idx_manager must index the employees table."
    assert [row[2] for row in indexed_columns] == ["manager_id"], \
        "idx_manager must index employees.manager_id."


def test_recursive_cte_artifact_and_result():
    # The instruction requires writing a recursive CTE. Require retained query/source
    # evidence rather than accepting only a hard-coded JSON export.
    candidates = []
    excluded = {CSV_PATH, DB_PATH, JSON_PATH}
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache"}]
        for filename in files:
            path = os.path.join(root, filename)
            if path in excluded:
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "r", encoding="utf-8", errors="ignore") as f:
                    candidates.append(f.read())
            except OSError:
                pass

    cte_pattern = re.compile(r"\bWITH\s+RECURSIVE\b", re.IGNORECASE | re.DOTALL)
    assert any(
        cte_pattern.search(text)
        and re.search(r"\bemployees\b", text, re.IGNORECASE)
        and re.search(r"\bmanager_id\b", text, re.IGNORECASE)
        and "->" in text
        for text in candidates
    ), "No retained script or SQL artifact contains the required recursive employees CTE."

    query = """
        WITH RECURSIVE hierarchy(id, path, depth) AS (
            SELECT id, CAST(id AS TEXT), 1
            FROM employees
            WHERE manager_id IS NULL
            UNION ALL
            SELECT e.id, hierarchy.path || '->' || e.id, hierarchy.depth + 1
            FROM employees AS e
            JOIN hierarchy ON e.manager_id = hierarchy.id
        )
        SELECT id, path FROM hierarchy WHERE depth >= 4 ORDER BY id
    """
    with sqlite3.connect(DB_PATH) as conn:
        actual = [
            {"id": row[0], "path": row[1]}
            for row in conn.execute(query).fetchall()
        ]
    assert actual == expected_from_csv(), \
        "A recursive traversal of the imported employees table does not produce the required hierarchy."


def test_json_export_exists():
    assert os.path.isfile(JSON_PATH), f"The JSON file {JSON_PATH} does not exist."


def test_json_export_content():
    assert os.path.isfile(JSON_PATH), f"The JSON file {JSON_PATH} does not exist."

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    expected_data = [
        {"id": 7, "path": "1->2->4->7"},
        {"id": 8, "path": "1->2->5->8"},
        {"id": 9, "path": "1->2->5->8->9"}
    ]

    assert isinstance(data, list), "The JSON data should be a list of objects."

    # Preserve the original exact-content assertion.
    data_sorted = sorted(data, key=lambda x: x.get("id", 0))
    expected_sorted = sorted(expected_data, key=lambda x: x["id"])
    assert data_sorted == expected_sorted, f"The content of {JSON_PATH} does not match the expected output."

    assert all(isinstance(item, dict) and list(item.keys()) == ["id", "path"] for item in data), \
        "Each JSON object must have exactly the keys id and path."
    assert all(type(item["id"]) is int and isinstance(item["path"], str) for item in data), \
        "JSON ids must be integers and paths must be strings."
    assert data == sorted(data, key=lambda item: item["id"]), \
        "The JSON array must be sorted by id in ascending order."
    assert data == expected_from_csv(), \
        "The JSON export does not match the hierarchy derived from the supplied CSV."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
