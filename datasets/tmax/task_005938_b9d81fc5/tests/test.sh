#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR="$(mktemp -d)"
INSTRUMENT_DIR="$(mktemp -d)"
export BACKUP_DIR INSTRUMENT_DIR

cp /home/user/employees.db "$BACKUP_DIR/employees.db"
cp /home/user/access_logs.jsonl "$BACKUP_DIR/access_logs.jsonl"
cp /home/user/schema.json "$BACKUP_DIR/schema.json"
if [ -f /home/user/leak_report.json ]; then
    cp /home/user/leak_report.json "$BACKUP_DIR/leak_report.json"
    HAD_REPORT=1
else
    HAD_REPORT=0
fi

restore_files() {
    cp "$BACKUP_DIR/employees.db" /home/user/employees.db
    cp "$BACKUP_DIR/access_logs.jsonl" /home/user/access_logs.jsonl
    cp "$BACKUP_DIR/schema.json" /home/user/schema.json
    if [ "$HAD_REPORT" = "1" ]; then
        cp "$BACKUP_DIR/leak_report.json" /home/user/leak_report.json
    else
        rm -f /home/user/leak_report.json
    fi
    rm -rf "$BACKUP_DIR" "$INSTRUMENT_DIR"
}
trap restore_files EXIT

cat > "$INSTRUMENT_DIR/sitecustomize.py" <<'PY_EOF'
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get("SQL_TRACE_PATH")

def _connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    if _trace_path:
        def record(statement):
            with open(_trace_path, "a", encoding="utf-8") as trace_file:
                trace_file.write(statement.replace("\n", " ") + "\n")
        conn.set_trace_callback(record)
    return conn

sqlite3.connect = _connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess
from collections import defaultdict

import jsonschema
import pytest

SCRIPT_PATH = "/home/user/analyze_leak.py"
REPORT_PATH = "/home/user/leak_report.json"
LOGS_PATH = "/home/user/access_logs.jsonl"
DB_PATH = "/home/user/employees.db"
SCHEMA_PATH = "/home/user/schema.json"
BACKUP_DIR = os.environ["BACKUP_DIR"]
INSTRUMENT_DIR = os.environ["INSTRUMENT_DIR"]
TRACE_PATH = "/tmp/analyze_leak_sql_trace.txt"


def run_script():
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)
    env = os.environ.copy()
    env["PYTHONPATH"] = INSTRUMENT_DIR + os.pathsep + env.get("PYTHONPATH", "")
    env["SQL_TRACE_PATH"] = TRACE_PATH
    return subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def assert_report_matches_sources():
    assert os.path.isfile(REPORT_PATH), f"The report {REPORT_PATH} does not exist."
    assert os.path.isfile(LOGS_PATH), "Access logs missing."

    access_counts = defaultdict(int)
    with open(LOGS_PATH, "r", encoding="utf-8") as f:
        for line in f:
            log = json.loads(line)
            if log.get("doc_id") == "DOC-999":
                access_counts[log["emp_id"]] += 1

    suspect_id = max(access_counts, key=access_counts.get)
    expected_access_count = access_counts[suspect_id]

    assert os.path.isfile(DB_PATH), "Employees DB missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT e.name, d.name
        FROM employees e
        JOIN departments d ON e.dept_id = d.id
        WHERE e.id = ?
    """, (suspect_id,))
    row = cursor.fetchone()
    assert row is not None, f"Suspect ID {suspect_id} not found in DB."
    suspect_name, department_name = row

    cursor.execute("SELECT id, name, manager_id FROM employees")
    employees = cursor.fetchall()
    conn.close()

    emp_dict = {emp[0]: {"name": emp[1], "manager_id": emp[2]} for emp in employees}
    path = []
    current_id = suspect_id
    while current_id is not None:
        path.append(emp_dict[current_id]["name"])
        current_id = emp_dict[current_id]["manager_id"]
    expected_management_path = path[::-1]

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The report {REPORT_PATH} is not valid JSON.")

    assert report_data.get("suspect_id") == suspect_id, \
        f"Expected suspect_id {suspect_id}, got {report_data.get('suspect_id')}"
    assert report_data.get("suspect_name") == suspect_name, \
        f"Expected suspect_name '{suspect_name}', got '{report_data.get('suspect_name')}'"
    assert report_data.get("department") == department_name, \
        f"Expected department '{department_name}', got '{report_data.get('department')}'"
    assert report_data.get("access_count") == expected_access_count, \
        f"Expected access_count {expected_access_count}, got {report_data.get('access_count')}"
    assert report_data.get("management_path") == expected_management_path, \
        f"Expected management_path {expected_management_path}, got {report_data.get('management_path')}"

    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        schema = json.load(f)
    jsonschema.validate(report_data, schema)
    return report_data


def install_random_fixture():
    shutil.copy(os.path.join(BACKUP_DIR, "schema.json"), SCHEMA_PATH)
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    base = 1000 + secrets.randbelow(500000) * 10
    ceo_id, manager_id, suspect_id, decoy_id, peer_id = (
        base + 1, base + 2, base + 3, base + 4, base + 5
    )
    executive_dept, secure_dept, other_dept = base + 101, base + 102, base + 103
    token = secrets.token_hex(8)
    ceo_name = f"CEO-{token}"
    manager_name = f"Manager-{token}"
    suspect_name = f"Suspect-{token}"
    decoy_name = f"Decoy-{token}"
    peer_name = f"Peer-{token}"
    secure_name = f"Secure-{token}"

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)")
    cur.execute("CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, dept_id INTEGER)")
    cur.executemany("INSERT INTO departments VALUES (?, ?)", [
        (executive_dept, f"Executive-{token}"),
        (secure_dept, secure_name),
        (other_dept, f"Other-{token}"),
    ])
    cur.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)", [
        (ceo_id, ceo_name, None, executive_dept),
        (manager_id, manager_name, ceo_id, secure_dept),
        (suspect_id, suspect_name, manager_id, secure_dept),
        (decoy_id, decoy_name, ceo_id, other_dept),
        (peer_id, peer_name, manager_id, secure_dept),
    ])
    conn.commit()
    conn.close()

    logs = []
    logs.extend({"emp_id": suspect_id, "doc_id": "DOC-999", "timestamp": f"T{i}"} for i in range(7))
    logs.extend({"emp_id": decoy_id, "doc_id": "DOC-999", "timestamp": f"D{i}"} for i in range(4))
    logs.extend({"emp_id": peer_id, "doc_id": "DOC-111", "timestamp": f"P{i}"} for i in range(15))
    random.SystemRandom().shuffle(logs)
    with open(LOGS_PATH, "w", encoding="utf-8") as f:
        for entry in logs:
            f.write(json.dumps(entry) + "\n")

    return {
        "suspect_id": suspect_id,
        "suspect_name": suspect_name,
        "department": secure_name,
        "access_count": 7,
        "management_path": [ceo_name, manager_name, suspect_name],
    }


def test_01_analyze_leak_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_02_execute_script_and_check_original_report():
    shutil.copy(os.path.join(BACKUP_DIR, "employees.db"), DB_PATH)
    shutil.copy(os.path.join(BACKUP_DIR, "access_logs.jsonl"), LOGS_PATH)
    shutil.copy(os.path.join(BACKUP_DIR, "schema.json"), SCHEMA_PATH)
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = run_script()
    assert result.returncode == 0, f"analyze_leak.py failed:\n{result.stderr}"
    assert_report_matches_sources()


def test_03_randomized_inputs_require_parsing_join_and_traversal():
    expected = install_random_fixture()
    result = run_script()
    assert result.returncode == 0, f"analyze_leak.py failed on fresh inputs:\n{result.stderr}"

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        report = json.load(f)
    assert report == expected
    assert_report_matches_sources()

    assert os.path.isfile(TRACE_PATH), "The script did not open the SQLite database."
    with open(TRACE_PATH, "r", encoding="utf-8") as f:
        statements = f.read().lower()
    join_was_executed = any(
        re.search(r"\bjoin\b", statement)
        and "employees" in statement
        and "departments" in statement
        for statement in statements.splitlines()
    )
    assert join_was_executed, "No executed SQL JOIN between employees and departments was observed."


def test_04_schema_is_validated_before_writing():
    install_random_fixture()
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        schema = json.load(f)
    schema["properties"]["_verification_required_field"] = {"type": "string"}
    schema["required"] = list(schema["required"]) + ["_verification_required_field"]
    with open(SCHEMA_PATH, "w", encoding="utf-8") as f:
        json.dump(schema, f)

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    run_script()
    assert not os.path.exists(REPORT_PATH), \
        "The script wrote a report that fails the supplied schema instead of validating before writing."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
