#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/audit.db"
SCRIPT_PATH = "/home/user/generate_graph.sh"
JSON_PATH = "/home/user/audit_graph.json"


def assert_exact_indexes():
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index'")
        names = {row[0] for row in cursor.fetchall()}
        assert names == {"idx_gm_emp", "idx_ga_group"}, \
            f"Expected exactly indexes idx_gm_emp and idx_ga_group, but found {names}."

        cursor.execute("SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_gm_emp';")
        row = cursor.fetchone()
        assert row is not None, "Index 'idx_gm_emp' is missing."
        sql = row[0].lower()
        assert "group_members" in sql, "Index 'idx_gm_emp' should be on the 'group_members' table."
        assert "emp_id" in sql, "Index 'idx_gm_emp' should be on the 'emp_id' column."
        cursor.execute("PRAGMA index_info('idx_gm_emp')")
        assert [r[2] for r in cursor.fetchall()] == ["emp_id"], \
            "Index 'idx_gm_emp' must index exactly group_members.emp_id."

        cursor.execute("SELECT sql FROM sqlite_master WHERE type='index' AND name='idx_ga_group';")
        row = cursor.fetchone()
        assert row is not None, "Index 'idx_ga_group' is missing."
        sql = row[0].lower()
        assert "group_access" in sql, "Index 'idx_ga_group' should be on the 'group_access' table."
        assert "group_id" in sql, "Index 'idx_ga_group' should be on the 'group_id' column."
        cursor.execute("PRAGMA index_info('idx_ga_group')")
        assert [r[2] for r in cursor.fetchall()] == ["group_id"], \
            "Index 'idx_ga_group' must index exactly group_access.group_id."
    finally:
        conn.close()


def run_script_and_load_json():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    try:
        subprocess.run([SCRIPT_PATH], check=True, capture_output=True, text=True, timeout=30)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script execution failed with exit code {e.returncode}.\nStderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Script execution timed out.")

    assert os.path.exists(JSON_PATH), f"Script did not generate the expected output file at {JSON_PATH}."
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON output: {e}")


def validate_graph(data, expected_nodes, expected_edges):
    assert isinstance(data, dict), "JSON output must be an object."
    assert "nodes" in data, "JSON output is missing the 'nodes' array."
    assert "edges" in data, "JSON output is missing the 'edges' array."
    assert isinstance(data["nodes"], list), "'nodes' must be an array."
    assert isinstance(data["edges"], list), "'edges' must be an array."

    nodes = {n.get("id"): n for n in data["nodes"]}
    edges = {(e.get("source"), e.get("target"), e.get("relation")) for e in data["edges"]}
    assert set(nodes) == set(expected_nodes), \
        f"Expected node IDs {set(expected_nodes)}, but got {set(nodes)}."
    for node_id, expected in expected_nodes.items():
        assert nodes[node_id] == expected
    assert edges == expected_edges, f"Expected edges {expected_edges}, but got {edges}."
    assert len(data["nodes"]) == len(nodes), "Duplicate nodes found in the JSON output."
    assert len(data["edges"]) == len(edges), "Duplicate edges found in the JSON output."


def test_database_indexes():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    assert_exact_indexes()


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_json_output():
    data = run_script_and_load_json()
    expected_nodes = {
        "emp_1": {"id": "emp_1", "type": "employee", "name": "Alice"},
        "emp_2": {"id": "emp_2", "type": "employee", "name": "Bob"},
        "emp_3": {"id": "emp_3", "type": "employee", "name": "Charlie"},
        "sys_50": {"id": "sys_50", "type": "system", "name": "Finance"},
        "sys_51": {"id": "sys_51", "type": "system", "name": "HR"},
        "sys_52": {"id": "sys_52", "type": "system", "name": "IT"},
    }
    expected_edges = {
        ("emp_1", "sys_50", "HAS_ACCESS"),
        ("emp_1", "sys_51", "HAS_ACCESS"),
        ("emp_2", "sys_50", "HAS_ACCESS"),
    }
    validate_graph(data, expected_nodes, expected_edges)


def test_script_projects_randomized_database_contents():
    token = secrets.token_hex(6)
    base = 100000 + secrets.randbelow(800000)
    emp_ids = [base + i for i in range(4)]
    group_ids = [base + 100 + i for i in range(5)]
    system_ids = [base + 200 + i for i in range(4)]
    employee_names = [f"Employee_{token}_{i}" for i in range(4)]
    system_names = [f"System_{token}_{i}" for i in range(4)]

    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute("DELETE FROM group_members")
        cur.execute("DELETE FROM group_access")
        cur.execute("DELETE FROM employees")
        cur.executemany("INSERT INTO employees(id, name) VALUES (?, ?)", zip(emp_ids, employee_names))
        cur.executemany("INSERT INTO group_members(emp_id, group_id) VALUES (?, ?)", [
            (emp_ids[0], group_ids[0]),
            (emp_ids[0], group_ids[0]),
            (emp_ids[0], group_ids[1]),
            (emp_ids[1], group_ids[0]),
            (emp_ids[2], group_ids[2]),
            (emp_ids[2], group_ids[3]),
        ])
        cur.executemany("INSERT INTO group_access(group_id, system_id, system_name) VALUES (?, ?, ?)", [
            (group_ids[0], system_ids[0], system_names[0]),
            (group_ids[0], system_ids[0], system_names[0]),
            (group_ids[1], system_ids[0], system_names[0]),
            (group_ids[1], system_ids[1], system_names[1]),
            (group_ids[2], system_ids[2], system_names[2]),
            (group_ids[3], system_ids[2], system_names[2]),
            (group_ids[4], system_ids[3], system_names[3]),
        ])
        conn.commit()

        expected_nodes = {}
        for emp_id, name in cur.execute("SELECT id, name FROM employees"):
            node_id = f"emp_{emp_id}"
            expected_nodes[node_id] = {"id": node_id, "type": "employee", "name": name}
        for system_id, name in cur.execute("SELECT DISTINCT system_id, system_name FROM group_access"):
            node_id = f"sys_{system_id}"
            expected_nodes[node_id] = {"id": node_id, "type": "system", "name": name}
        expected_edges = {
            (f"emp_{emp_id}", f"sys_{system_id}", "HAS_ACCESS")
            for emp_id, system_id in cur.execute(
                "SELECT DISTINCT gm.emp_id, ga.system_id "
                "FROM group_members AS gm "
                "JOIN group_access AS ga ON ga.group_id = gm.group_id"
            )
        }
    finally:
        conn.close()

    data = run_script_and_load_json()
    validate_graph(data, expected_nodes, expected_edges)
    assert_exact_indexes()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
