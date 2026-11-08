#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import subprocess
import uuid
import pytest
from collections import defaultdict


def get_expected_violations():
    # Connect to DB
    db_path = '/home/user/data/hr.db'
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Load employees
    c.execute("SELECT id, department FROM employees")
    employees = {row[0]: row[1] for row in c.fetchall()}

    # Load resources
    c.execute("SELECT id, department_owner FROM resources")
    resources = {row[0]: row[1] for row in c.fetchall()}

    conn.close()

    # Load authorizations
    auth_path = '/home/user/data/authorizations.json'
    with open(auth_path, 'r') as f:
        auth_data = json.load(f)
    authorizations = {(item["user_id"], item["resource_id"]) for item in auth_data}

    # Load access logs
    logs_path = '/home/user/data/access_logs.json'
    with open(logs_path, 'r') as f:
        logs_data = json.load(f)

    # Compute violations
    violations = defaultdict(int)
    for log in logs_data:
        uid = log.get("user_id")
        rid = log.get("resource_id")

        user_dept = employees.get(uid)
        res_owner = resources.get(rid)

        if user_dept and res_owner:
            if user_dept != res_owner:
                if (uid, rid) not in authorizations:
                    violations[user_dept] += 1

    # Remove departments with 0 violations
    return {k: v for k, v in violations.items() if v > 0}


def test_audit_script_exists():
    script_path = '/home/user/audit.py'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_violations_summary_exists_and_correct():
    summary_path = '/home/user/violations_summary.json'
    assert os.path.isfile(summary_path), f"The output file {summary_path} does not exist."

    with open(summary_path, 'r') as f:
        try:
            actual_summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {summary_path} is not valid JSON.")

    expected_summary = get_expected_violations()

    assert actual_summary == expected_summary, (
        f"The violations summary is incorrect.\n"
        f"Expected: {expected_summary}\n"
        f"Actual: {actual_summary}"
    )


def test_audit_script_executes_and_processes_changed_inputs():
    script_path = '/home/user/audit.py'
    db_path = '/home/user/data/hr.db'
    logs_path = '/home/user/data/access_logs.json'
    auth_path = '/home/user/data/authorizations.json'
    summary_path = '/home/user/violations_summary.json'
    paths = [db_path, logs_path, auth_path, summary_path]

    backups = {}
    for path in paths:
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    def remove_sqlite_sidecars():
        for suffix in ('-wal', '-shm', '-journal'):
            sidecar = db_path + suffix
            if os.path.exists(sidecar):
                os.remove(sidecar)

    token = uuid.uuid4().hex
    dept_a = 'AuditA_' + token
    dept_b = 'AuditB_' + token
    dept_c = 'AuditC_' + token

    try:
        remove_sqlite_sidecars()
        if os.path.exists(db_path):
            os.remove(db_path)

        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute('CREATE TABLE employees (id INTEGER, name TEXT, department TEXT)')
        c.execute('CREATE TABLE resources (id INTEGER, name TEXT, department_owner TEXT)')
        c.executemany('INSERT INTO employees VALUES (?, ?, ?)', [
            (91001, 'Fixture User A', dept_a),
            (91002, 'Fixture User B', dept_b),
            (91003, 'Fixture User C', dept_c),
        ])
        c.executemany('INSERT INTO resources VALUES (?, ?, ?)', [
            (92001, 'Fixture Resource A', dept_a),
            (92002, 'Fixture Resource B', dept_b),
            (92003, 'Fixture Resource C', dept_c),
        ])
        conn.commit()
        conn.close()

        access_logs = [
            {"user_id": 91001, "resource_id": 92001, "timestamp": "X1"},
            {"user_id": 91001, "resource_id": 92002, "timestamp": "X2"},
            {"user_id": 91001, "resource_id": 92003, "timestamp": "X3"},
            {"user_id": 91001, "resource_id": 92003, "timestamp": "X4"},
            {"user_id": 91002, "resource_id": 92001, "timestamp": "X5"},
            {"user_id": 91002, "resource_id": 92003, "timestamp": "X6"},
            {"user_id": 91003, "resource_id": 92003, "timestamp": "X7"},
            {"user_id": 91003, "resource_id": 92001, "timestamp": "X8"},
        ]
        authorizations = [
            {"user_id": 91001, "resource_id": 92002},
            {"user_id": 91002, "resource_id": 92003},
        ]
        with open(logs_path, 'w') as f:
            json.dump(access_logs, f)
        with open(auth_path, 'w') as f:
            json.dump(authorizations, f)

        if os.path.exists(summary_path):
            os.remove(summary_path)

        try:
            result = subprocess.run(
                ['python3', script_path],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            pytest.fail('The audit script did not finish within 15 seconds.')

        assert result.returncode == 0, (
            f"The audit script exited with status {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(summary_path), (
            f"Running {script_path} did not create {summary_path}."
        )

        with open(summary_path, 'r') as f:
            try:
                actual_summary = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"The generated file {summary_path} is not valid JSON.")

        expected_summary = get_expected_violations()
        assert actual_summary == expected_summary, (
            "The script did not correctly process the changed test inputs.\n"
            f"Expected: {expected_summary}\nActual: {actual_summary}"
        )
    finally:
        remove_sqlite_sidecars()
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, 'wb') as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
