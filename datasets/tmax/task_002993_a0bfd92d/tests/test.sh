#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess
import uuid

import pytest

APP_DIR = "/home/user/app"
DB_PATH = os.path.join(APP_DIR, "db", "data.db")
JSON_PATH = os.path.join(APP_DIR, "output", "results.json")


def expected_results():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT users.name, SUM(transactions.amount) as total
        FROM users
        JOIN transactions ON users.id = transactions.user_id
        WHERE users.status = 'active'
        GROUP BY users.name
        HAVING total > 0
        ORDER BY total DESC
    """)
    results = [{"name": row[0], "total": row[1]} for row in cursor.fetchall()]
    conn.close()
    return results


def add_dynamic_cases():
    token = uuid.uuid4().hex
    positive_name = f"VerifierPositive_{token}"
    amount = float(secrets.randbelow(90000) + 1000)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    next_user = cursor.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM users").fetchone()[0]
    next_tx = cursor.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM transactions").fetchone()[0]

    cursor.executemany(
        "INSERT INTO users (id, name, status) VALUES (?, ?, ?)",
        [
            (next_user, positive_name, "active"),
            (next_user + 1, f"VerifierNull_{token}", "active"),
            (next_user + 2, f"VerifierZero_{token}", "active"),
            (next_user + 3, f"VerifierInactive_{token}", "inactive"),
        ],
    )
    cursor.executemany(
        "INSERT INTO transactions (id, user_id, amount) VALUES (?, ?, ?)",
        [
            (next_tx, next_user, amount),
            (next_tx + 1, next_user + 2, 0.0),
            (next_tx + 2, next_user + 3, amount + 100000.0),
        ],
    )
    conn.commit()
    conn.close()
    return positive_name


def run_command(command):
    try:
        completed = subprocess.run(
            command,
            cwd=APP_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {command}")

    assert completed.returncode == 0, (
        f"Command failed with exit code {completed.returncode}: {command}\n"
        f"Output:\n{completed.stdout[-6000:]}"
    )


def assert_current_output(expected, required_name):
    assert os.path.isfile(JSON_PATH), (
        f"Output file {JSON_PATH} does not exist after running the application."
    )
    try:
        with open(JSON_PATH, "r") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The file {JSON_PATH} does not contain valid JSON: {exc}")

    assert isinstance(actual, list), "The JSON output should be a list of dictionaries."
    assert actual == expected, f"Expected dynamic results {expected}, but got {actual}."
    assert any(item.get("name") == required_name for item in actual), (
        "The application did not process the dynamically added active user."
    )


@pytest.fixture(scope="module")
def exercise_artifacts():
    run_path = os.path.join(APP_DIR, "run.sh")
    process_path = os.path.join(APP_DIR, "src", "process_data.py")

    assert os.path.isfile(run_path), f"File {run_path} does not exist."
    assert os.access(run_path, os.X_OK), f"File {run_path} is not executable."
    assert os.path.isfile(process_path), f"File {process_path} does not exist."

    # Exercise run.sh against data unavailable when the submission was authored.
    required_name = add_dynamic_cases()
    expected_before = expected_results()
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    run_command([run_path])
    assert expected_results() == expected_before, "The application modified the source database."
    assert_current_output(expected_before, required_name)

    # Also execute the requested Python application directly so run.sh cannot
    # conceal a still-broken process_data.py implementation.
    required_name = add_dynamic_cases()
    expected_before = expected_results()
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    venv_python = os.path.join(APP_DIR, "venv", "bin", "python")
    assert os.path.isfile(venv_python), "run.sh did not successfully create its virtual environment."
    run_command([venv_python, process_path])
    assert expected_results() == expected_before, "The Python application modified the source database."
    assert_current_output(expected_before, required_name)

    return True


def test_requirements_fixed():
    req_path = os.path.join(APP_DIR, "requirements.txt")
    assert os.path.isfile(req_path), f"File {req_path} does not exist."

    with open(req_path, 'r') as f:
        content = f.read()

    assert "fake-broken-package-999" not in content, "The broken package 'fake-broken-package-999' is still in requirements.txt."


def test_application_artifacts_execute(exercise_artifacts):
    assert exercise_artifacts


def test_results_json_correctness(exercise_artifacts):
    db_path = os.path.join(APP_DIR, "db", "data.db")
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    # Derive expected results from the database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT users.name, SUM(transactions.amount) as total
        FROM users
        JOIN transactions ON users.id = transactions.user_id
        WHERE users.status = 'active'
        GROUP BY users.name
        HAVING total > 0
        ORDER BY total DESC
    """)
    expected_results_value = [{"name": row[0], "total": row[1]} for row in cursor.fetchall()]
    conn.close()

    json_path = os.path.join(APP_DIR, "output", "results.json")
    assert os.path.isfile(json_path), f"Output file {json_path} does not exist. The script may have crashed or not run."

    with open(json_path, 'r') as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    assert isinstance(actual_results, list), "The JSON output should be a list of dictionaries."
    assert actual_results == expected_results_value, (
        f"The output JSON does not match the expected results. "
        f"Expected: {expected_results_value}, but got: {actual_results}. "
        "Ensure filtering (active users, total > 0) and descending sorting by total are correct."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
