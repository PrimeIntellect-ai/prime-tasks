#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import time
import sqlite3
import subprocess
import pytest

def generate_test_db(db_path, num_users=50000):
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, created_at TEXT)")
    cursor.execute("CREATE TABLE devices (id INTEGER PRIMARY KEY, user_id INTEGER, device_type TEXT, os_version TEXT)")
    cursor.execute("CREATE TABLE logins (id INTEGER PRIMARY KEY, user_id INTEGER, device_id INTEGER, timestamp TEXT, ip_address TEXT)")

    users = []
    devices = []
    logins = []

    for i in range(1, num_users + 1):
        users.append((i, f"user_{i}", f"2023-01-01T12:00:{i%60:02d}"))
        devices.append((i, i, "Smartphone", "14.0"))
        logins.append((i, i, i, f"2023-01-02T12:00:{i%60:02d}", f"192.168.1.{i%255}"))

    cursor.executemany("INSERT INTO users VALUES (?, ?, ?)", users)
    cursor.executemany("INSERT INTO devices VALUES (?, ?, ?, ?)", devices)
    cursor.executemany("INSERT INTO logins VALUES (?, ?, ?, ?, ?)", logins)

    conn.commit()
    conn.close()

def get_expected_json(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    nodes = []
    edges = []

    cursor.execute("SELECT id, username, created_at FROM users")
    for row in cursor.fetchall():
        nodes.append({
            "id": f"u_{row[0]}",
            "label": "User",
            "properties": {"username": row[1], "joined": row[2]}
        })

    cursor.execute("SELECT id, user_id, device_type, os_version FROM devices")
    for row in cursor.fetchall():
        nodes.append({
            "id": f"d_{row[0]}",
            "label": "Device",
            "properties": {"type": row[2], "os": row[3]}
        })
        edges.append({
            "source": f"u_{row[1]}",
            "target": f"d_{row[0]}",
            "type": "OWNS"
        })

    cursor.execute("SELECT user_id, device_id, timestamp, ip_address FROM logins")
    for row in cursor.fetchall():
        edges.append({
            "source": f"u_{row[0]}",
            "target": f"d_{row[1]}",
            "type": "LOGGED_IN",
            "properties": {"time": row[2], "ip": row[3]}
        })

    conn.close()

    nodes.sort(key=lambda x: x["id"])
    edges.sort(key=lambda x: (x["source"], x["target"], x.get("type", "")))

    return {"nodes": nodes, "edges": edges}

def test_fast_backup_correctness_and_performance():
    script_path = "/home/user/fast_backup.py"
    assert os.path.exists(script_path), f"Agent's script not found at {script_path}"

    test_db_path = "/tmp/hidden_test.sqlite"
    output_json_path = "/tmp/output.json"

    generate_test_db(test_db_path, num_users=100000)

    start_time = time.time()
    result = subprocess.run(
        ["python3", script_path, test_db_path, output_json_path],
        capture_output=True,
        text=True
    )
    end_time = time.time()
    execution_time = end_time - start_time

    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"
    assert os.path.exists(output_json_path), "Output JSON file was not created"

    threshold = 1.5
    assert execution_time <= threshold, f"Execution time {execution_time:.2f}s exceeded threshold of {threshold}s"

    with open(output_json_path, 'r') as f:
        try:
            agent_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output is not valid JSON")

    expected_output = get_expected_json(test_db_path)

    assert "nodes" in agent_output, "Missing 'nodes' in output JSON"
    assert len(agent_output["nodes"]) == len(expected_output["nodes"]), "Incorrect number of nodes"
    assert agent_output["nodes"] == expected_output["nodes"], "Nodes do not match expected structure or are not sorted correctly"

    assert "edges" in agent_output, "Missing 'edges' in output JSON"
    assert len(agent_output["edges"]) == len(expected_output["edges"]), "Incorrect number of edges"
    assert agent_output["edges"] == expected_output["edges"], "Edges do not match expected structure or are not sorted correctly"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
