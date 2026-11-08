#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import sys
import shutil
import sqlite3
import secrets
import subprocess
from collections import defaultdict

import pytest

SCRIPT_PATH = '/home/user/generate_report.py'
DB_PATH = '/home/user/audit.db'
CSV_PATH = '/home/user/unauthorized_edges.csv'
JSON_PATH = '/home/user/dept_summary.json'
BACKUP_PATH = '/tmp/audit.db.verifier_backup'


def run_report():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    for path in (CSV_PATH, JSON_PATH):
        if os.path.exists(path):
            os.remove(path)
    subprocess.run(
        [sys.executable, SCRIPT_PATH],
        check=True,
        timeout=15,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


@pytest.fixture(scope='session', autouse=True)
def execute_and_restore_original_database():
    shutil.copy2(DB_PATH, BACKUP_PATH)
    run_report()
    try:
        yield
    finally:
        shutil.copy2(BACKUP_PATH, DB_PATH)
        try:
            run_report()
        except Exception:
            pass


def test_unauthorized_edges_csv():
    csv_path = '/home/user/unauthorized_edges.csv'
    assert os.path.isfile(csv_path), f"Expected output file {csv_path} is missing."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{csv_path} is empty."

    # Check header
    assert rows[0] == ['user_id', 'resource_id'], f"Header in {csv_path} is incorrect. Expected ['user_id', 'resource_id']."

    # Check data
    expected_data = [
        ['u1', 'r3'],
        ['u3', 'r2'],
        ['u3', 'r4']
    ]

    actual_data = rows[1:]
    assert actual_data == expected_data, f"Data in {csv_path} is incorrect or not properly sorted. Expected {expected_data}, got {actual_data}."


def test_dept_summary_json():
    json_path = '/home/user/dept_summary.json'
    assert os.path.isfile(json_path), f"Expected output file {json_path} is missing."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} does not contain valid JSON.")

    expected_data = {"Sales": 1, "IT": 2}

    assert data == expected_data, f"Data in {json_path} is incorrect. Expected {expected_data}, got {data}."


def test_script_modified():
    script_path = '/home/user/generate_report.py'
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    with open(script_path, 'r') as f:
        content = f.read()

    assert "BROKEN QUERY WITH IMPLICIT CROSS JOIN" not in content or "p.resource_id != a.resource_id" not in content or "unauthorized_edges.csv" in content, "It seems the script was not fully implemented or the broken query was not fixed."


def test_report_executes_correctly_on_unseen_database():
    token = secrets.token_hex(8)
    users = [
        (f'a_user_{token}', f'Dept_A_{token}'),
        (f'b_user_{token}', f'Dept_A_{token}'),
        (f'c_user_{token}', f'Dept_B_{token}'),
        (f'd_user_{token}', f'Dept_None_{token}'),
    ]
    permissions = [
        (f'Dept_A_{token}', f'a_resource_{token}'),
        (f'Dept_A_{token}', f'shared_resource_{token}'),
        (f'Dept_B_{token}', f'b_resource_{token}'),
        (f'Dept_B_{token}', f'shared_resource_{token}'),
    ]
    access_logs = [
        (f'a_user_{token}', f'a_resource_{token}'),
        (f'a_user_{token}', f'b_resource_{token}'),
        (f'b_user_{token}', f'shared_resource_{token}'),
        (f'b_user_{token}', f'z_resource_{token}'),
        (f'c_user_{token}', f'b_resource_{token}'),
        (f'c_user_{token}', f'a_resource_{token}'),
        (f'd_user_{token}', f'shared_resource_{token}'),
    ]

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE users (user_id TEXT, dept_id TEXT)')
        conn.execute('CREATE TABLE permissions (dept_id TEXT, resource_id TEXT)')
        conn.execute('CREATE TABLE access_logs (user_id TEXT, resource_id TEXT)')
        conn.executemany('INSERT INTO users VALUES (?, ?)', users)
        conn.executemany('INSERT INTO permissions VALUES (?, ?)', permissions)
        conn.executemany('INSERT INTO access_logs VALUES (?, ?)', access_logs)
        conn.commit()
    finally:
        conn.close()

    user_departments = dict(users)
    allowed = set(permissions)
    expected_edges = []
    expected_summary = defaultdict(int)
    for user_id, resource_id in access_logs:
        dept_id = user_departments[user_id]
        if (dept_id, resource_id) not in allowed:
            expected_edges.append([user_id, resource_id])
            expected_summary[dept_id] += 1
    expected_edges.sort(key=lambda row: (row[0], row[1]))

    run_report()

    assert os.path.isfile(CSV_PATH), f"Expected output file {CSV_PATH} is missing after executing the script."
    with open(CSV_PATH, 'r', newline='') as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ['user_id', 'resource_id'], f"Header in {CSV_PATH} is incorrect."
    assert rows[1:] == expected_edges, f"Unseen-database CSV result is incorrect. Expected {expected_edges}, got {rows[1:]}."

    assert os.path.isfile(JSON_PATH), f"Expected output file {JSON_PATH} is missing after executing the script."
    with open(JSON_PATH, 'r') as f:
        summary = json.load(f)
    assert summary == dict(expected_summary), f"Unseen-database summary is incorrect. Expected {dict(expected_summary)}, got {summary}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
