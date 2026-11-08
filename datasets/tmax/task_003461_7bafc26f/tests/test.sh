#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import json
import os
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import pytest

SCRIPT_PATH = '/home/user/ticket_system/report_generator.py'
DB_PATH = '/home/user/ticket_system/tickets.db'
JSON_PATH = '/home/user/ticket_system/critical_tickets.json'


def get_expected_critical_tickets():
    db_path = '/home/user/ticket_system/tickets.db'
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id, payload FROM tickets ORDER BY id")
    rows = cursor.fetchall()
    conn.close()

    expected_ids = []
    for t_id, payload in rows:
        if payload.startswith("DATA:"):
            b64_part = payload[5:]
            try:
                decoded = base64.b64decode(b64_part, validate=True)
                data = json.loads(decoded.decode('utf-8'))
                if data.get("critical") is True:
                    expected_ids.append(t_id)
            except Exception:
                pass
    return expected_ids


def inspect_script():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} must be a regular file."

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    batch_values = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            if any(isinstance(target, ast.Name) and target.id == 'batch_size' for target in node.targets):
                batch_values.append(node.value)
        elif isinstance(node, ast.AnnAssign):
            if isinstance(node.target, ast.Name) and node.target.id == 'batch_size':
                batch_values.append(node.value)

    assert batch_values, "The script must retain its batch_size setting."
    assert all(isinstance(value, ast.Constant) and type(value.value) is int and value.value == 10
               for value in batch_values), "The batch size must remain 10."

    uses_batch_pagination = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or len(node.args) < 2:
            continue
        if not (isinstance(node.func, ast.Attribute) and node.func.attr == 'execute'):
            continue
        query = node.args[0]
        if not (isinstance(query, ast.Constant) and isinstance(query.value, str)):
            continue
        normalized = query.value.upper()
        argument_names = {part.id for part in ast.walk(node.args[1]) if isinstance(part, ast.Name)}
        if 'LIMIT' in normalized and 'OFFSET' in normalized and {'batch_size', 'offset'} <= argument_names:
            uses_batch_pagination = True
            break
    assert uses_batch_pagination, "The database query must continue paginating with batch_size and offset."


def run_script():
    if os.path.lexists(JSON_PATH):
        os.remove(JSON_PATH)
    try:
        completed = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd=os.path.dirname(SCRIPT_PATH),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("report_generator.py did not finish successfully within 30 seconds.")

    assert completed.returncode == 0, (
        "report_generator.py did not run successfully.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(JSON_PATH), f"Output file {JSON_PATH} was not generated. Did the script run successfully?"


def assert_current_report_is_correct():
    with open(JSON_PATH, 'r') as f:
        try:
            actual_ids = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {JSON_PATH} is not valid JSON.")

    expected_ids = get_expected_critical_tickets()

    assert isinstance(actual_ids, list), "Output JSON should be a list of integers."

    # Check if they only got partial results (e.g. missing 11 and 22 due to pagination bug)
    if set(actual_ids) == {45} and expected_ids != actual_ids:
        pytest.fail("The output only contains ticket 45. The pagination bug (skipping records) is likely still present.")

    assert actual_ids == expected_ids, f"Expected critical ticket IDs {expected_ids}, but got {actual_ids}. Both slicing and pagination bugs must be fixed."


def create_exercise_database():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('CREATE TABLE tickets (id INTEGER PRIMARY KEY, status TEXT, payload TEXT)')

    critical_positions = {1, 11, 22, 33, 47}
    for position in range(1, 48):
        ticket_id = 1000 + position * 7
        data = {
            "critical": position in critical_positions,
            "info": "verification_payload_" + ("x" * (position % 13)) + str(position),
        }
        encoded = base64.b64encode(json.dumps(data).encode('utf-8')).decode('ascii')
        cursor.execute(
            "INSERT INTO tickets (id, status, payload) VALUES (?, ?, ?)",
            (ticket_id, 'closed', 'DATA:' + encoded),
        )
    conn.commit()
    conn.close()


def test_critical_tickets_json_exists_and_correct():
    inspect_script()

    # Execute the submitted script on the task database and retain the original assertions.
    run_script()
    assert_current_report_is_correct()

    with open(JSON_PATH, 'rb') as f:
        original_report = f.read()

    backup_dir = tempfile.mkdtemp(prefix='ticket_verifier_')
    backup_db = os.path.join(backup_dir, 'tickets.db')
    shutil.copy2(DB_PATH, backup_db)

    try:
        os.remove(DB_PATH)
        create_exercise_database()

        # Run it again on independently generated records so a prewritten answer cannot pass.
        run_script()
        assert_current_report_is_correct()
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.copy2(backup_db, DB_PATH)
        with open(JSON_PATH, 'wb') as f:
            f.write(original_report)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
