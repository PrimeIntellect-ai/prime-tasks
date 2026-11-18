#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import sqlite3

import networkx as nx
import pytest

DB_PATH = "/home/user/company.db"
RESULTS_PATH = "/home/user/results.json"
DATA_DIR = "/home/user/data"


def load_results():
    with open(RESULTS_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} is not a valid JSON file.")


def expected_source_rows():
    departments = [
        (1, "Engineering"),
        (2, "Sales"),
        (3, "HR"),
        (4, "Marketing"),
        (5, "Executive"),
    ]
    employees = [
        (101, "Alice", 1),
        (102, "Bob", 1),
        (201, "Charlie", 2),
        (202, "Dave", 2),
        (301, "Eve", 3),
        (401, "Frank", 4),
        (501, "Grace", 5),
    ]
    communications = []
    msg_id = 1

    def add(count, sender, receiver, timestamp):
        nonlocal msg_id
        for _ in range(count):
            communications.append((msg_id, sender, receiver, timestamp))
            msg_id += 1

    add(10, 101, 201, "2023-01-01T10:00:00")
    add(5, 102, 202, "2023-01-01T10:05:00")
    add(20, 201, 301, "2023-01-01T11:00:00")
    add(8, 501, 101, "2023-01-01T12:00:00")
    add(8, 501, 201, "2023-01-01T12:00:00")
    add(8, 501, 301, "2023-01-01T12:00:00")
    add(50, 101, 102, "2023-01-01T13:00:00")
    return departments, employees, communications


def read_csv_rows():
    paths = {
        "departments": os.path.join(DATA_DIR, "departments.csv"),
        "employees": os.path.join(DATA_DIR, "employees.csv"),
        "communications": os.path.join(DATA_DIR, "communications.csv"),
    }
    for path in paths.values():
        assert os.path.isfile(path), f"Required input file {path} is missing"

    with open(paths["departments"], newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["dept_id", "dept_name"]
        departments = [(int(r["dept_id"]), r["dept_name"]) for r in reader]

    with open(paths["employees"], newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["emp_id", "name", "dept_id"]
        employees = [(int(r["emp_id"]), r["name"], int(r["dept_id"])) for r in reader]

    with open(paths["communications"], newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["msg_id", "sender_id", "receiver_id", "timestamp"]
        communications = [
            (int(r["msg_id"]), int(r["sender_id"]), int(r["receiver_id"]), r["timestamp"])
            for r in reader
        ]
    return departments, employees, communications


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} was not found."


def test_results_json_exists():
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} was not found."


def test_results_json_content():
    results = load_results()
    assert "total_inter_dept_messages" in results, "Missing 'total_inter_dept_messages' in results.json"
    assert "top_dept_in_degree" in results, "Missing 'top_dept_in_degree' in results.json"
    assert "indexes_created" in results, "Missing 'indexes_created' in results.json"
    assert results["total_inter_dept_messages"] == 59, \
        f"Expected 59 total inter-department messages, got {results['total_inter_dept_messages']}"
    assert results["top_dept_in_degree"] == "HR", \
        f"Expected top department to be 'HR', got '{results['top_dept_in_degree']}'"
    assert isinstance(results["indexes_created"], list), "'indexes_created' should be a list"
    assert len(results["indexes_created"]) >= 2, \
        f"Expected at least 2 indexes created, found {len(results['indexes_created'])}"


def test_input_csvs_are_intact_and_database_contains_all_ingested_rows():
    expected = expected_source_rows()
    csv_rows = read_csv_rows()
    assert csv_rows == expected, "The supplied CSV input data was modified"

    conn = sqlite3.connect(DB_PATH)
    try:
        assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        required_columns = {
            "departments": ["dept_id", "dept_name"],
            "employees": ["emp_id", "name", "dept_id"],
            "communications": ["msg_id", "sender_id", "receiver_id", "timestamp"],
        }
        for table, columns in required_columns.items():
            info = conn.execute(f"PRAGMA table_info({table})").fetchall()
            assert [row[1] for row in info] == columns, f"Incorrect schema for table {table}"
            assert info[0][5] > 0, f"{table}.{columns[0]} must be a primary key"

        db_departments = conn.execute(
            "SELECT dept_id, dept_name FROM departments ORDER BY dept_id"
        ).fetchall()
        db_employees = conn.execute(
            "SELECT emp_id, name, dept_id FROM employees ORDER BY emp_id"
        ).fetchall()
        db_communications = conn.execute(
            "SELECT msg_id, sender_id, receiver_id, timestamp FROM communications ORDER BY msg_id"
        ).fetchall()
        assert db_departments == expected[0], "departments.csv was not ingested exactly"
        assert db_employees == expected[1], "employees.csv was not ingested exactly"
        assert db_communications == expected[2], "communications.csv was not ingested exactly"
    finally:
        conn.close()


def test_foreign_keys_enabled():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]
    fk_found = False
    for table in tables:
        cursor.execute(f"PRAGMA foreign_key_list({table});")
        if cursor.fetchall():
            fk_found = True
            break
    conn.close()
    assert fk_found, "No foreign key constraints were found in the database schema."


def test_required_foreign_keys_are_declared_and_effective():
    conn = sqlite3.connect(DB_PATH)
    try:
        employee_fks = conn.execute("PRAGMA foreign_key_list(employees)").fetchall()
        communication_fks = conn.execute("PRAGMA foreign_key_list(communications)").fetchall()
        employee_links = {(r[3], r[2], r[4]) for r in employee_fks}
        communication_links = {(r[3], r[2], r[4]) for r in communication_fks}
        assert ("dept_id", "departments", "dept_id") in employee_links
        assert ("sender_id", "employees", "emp_id") in communication_links
        assert ("receiver_id", "employees", "emp_id") in communication_links
        conn.execute("PRAGMA foreign_keys = ON")
        assert conn.execute("PRAGMA foreign_keys").fetchone()[0] == 1
        assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
        with pytest.raises(sqlite3.IntegrityError):
            conn.execute(
                "INSERT INTO communications(msg_id, sender_id, receiver_id, timestamp) VALUES (999999, -1, 101, 'x')"
            )
    finally:
        conn.rollback()
        conn.close()


def test_database_indexes_exist():
    results = load_results()
    indexes_created = results.get("indexes_created", [])
    if not isinstance(indexes_created, list) or len(indexes_created) < 2:
        pytest.skip("indexes_created is not a valid list of at least 2 items; already caught by another test.")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';")
    db_indexes = [row[0] for row in cursor.fetchall()]
    conn.close()
    for idx in indexes_created:
        assert idx in db_indexes, f"Index '{idx}' reported in results.json was not found in {DB_PATH}"


def test_reported_indexes_optimize_both_communication_joins():
    results = load_results()
    names = results["indexes_created"]
    assert all(isinstance(name, str) and name for name in names)
    assert len(set(names)) == len(names), "indexes_created must contain distinct index names"

    conn = sqlite3.connect(DB_PATH)
    try:
        index_rows = conn.execute(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type='index' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
        index_tables = dict(index_rows)
        assert len(index_tables) >= 2, "At least two secondary indexes are required"
        leading_columns = {}
        for name in names:
            assert name in index_tables, f"Reported index {name!r} does not exist"
            escaped = name.replace('"', '""')
            columns = conn.execute(f'PRAGMA index_info("{escaped}")').fetchall()
            assert columns, f"Reported index {name!r} has no indexed columns"
            leading_columns[name] = (index_tables[name], columns[0][2])
        assert any(v == ("communications", "sender_id") for v in leading_columns.values()), \
            "A reported secondary index must lead with communications.sender_id"
        assert any(v == ("communications", "receiver_id") for v in leading_columns.values()), \
            "A reported secondary index must lead with communications.receiver_id"
    finally:
        conn.close()


def test_aggregation_graph_and_report_are_derived_from_ingested_data():
    departments, employees, communications = read_csv_rows()
    dept_names = {dept_id: name for dept_id, name in departments}
    employee_depts = {emp_id: dept_id for emp_id, _name, dept_id in employees}
    expected_edges = {}
    for _msg_id, sender_id, receiver_id, _timestamp in communications:
        sender_dept = employee_depts[sender_id]
        receiver_dept = employee_depts[receiver_id]
        if sender_dept != receiver_dept:
            key = (dept_names[sender_dept], dept_names[receiver_dept])
            expected_edges[key] = expected_edges.get(key, 0) + 1

    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            SELECT sd.dept_name, rd.dept_name, COUNT(*)
            FROM communications AS c
            JOIN employees AS se ON se.emp_id = c.sender_id
            JOIN departments AS sd ON sd.dept_id = se.dept_id
            JOIN employees AS re ON re.emp_id = c.receiver_id
            JOIN departments AS rd ON rd.dept_id = re.dept_id
            WHERE se.dept_id <> re.dept_id
            GROUP BY sd.dept_id, sd.dept_name, rd.dept_id, rd.dept_name
        """).fetchall()
    finally:
        conn.close()
    actual_edges = {(sender, receiver): count for sender, receiver, count in rows}
    assert actual_edges == expected_edges, "Database inter-department aggregation is incorrect"

    graph = nx.DiGraph()
    graph.add_nodes_from(name for _dept_id, name in departments)
    for (sender, receiver), weight in actual_edges.items():
        graph.add_edge(sender, receiver, weight=weight)
    weighted_in_degree = dict(graph.in_degree(weight="weight"))
    highest = max(weighted_in_degree.values())
    winners = [name for name, value in weighted_in_degree.items() if value == highest]
    assert len(winners) == 1, "Expected a unique top weighted in-degree department"

    results = load_results()
    total = sum(actual_edges.values())
    assert type(results["total_inter_dept_messages"]) is int
    assert results["total_inter_dept_messages"] == total
    assert results["top_dept_in_degree"] == winners[0]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
