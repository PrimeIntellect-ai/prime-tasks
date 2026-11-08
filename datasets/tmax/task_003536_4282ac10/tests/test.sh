#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import stat
import subprocess
import uuid

import pytest

SCRIPT_PATH = "/home/user/generate_report.sh"
DB_PATH = "/home/user/analytics.db"


def test_script_exists_and_executable():
    """Test that the wrapper script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

    st = os.stat(SCRIPT_PATH)
    assert st.st_mode & stat.S_IXUSR, f"Script {SCRIPT_PATH} is not executable"


def test_script_execution_and_output():
    """Test executing the script and verify the JSON output."""
    output_path = "/home/user/test_report_1.json"
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH, "completed", "50", output_path],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Script execution failed with return code {result.returncode}.\nStderr: {result.stderr}"
    assert os.path.exists(output_path), f"Output JSON file was not created at {output_path}"

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} does not contain valid JSON.")

    expected_data = [
        {"customer_name": "Charlie Brown", "total_spent": 300.0, "total_interaction_time": 0},
        {"customer_name": "Alice Smith", "total_spent": 250.0, "total_interaction_time": 120},
        {"customer_name": "Bob Jones", "total_spent": 100.0, "total_interaction_time": 300}
    ]

    assert isinstance(data, list), "Output JSON must be an array of objects."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get("customer_name") == expected["customer_name"], f"Record {i}: Expected customer_name '{expected['customer_name']}', got '{actual.get('customer_name')}'"
        assert float(actual.get("total_spent", 0)) == expected["total_spent"], f"Record {i}: Expected total_spent {expected['total_spent']}, got {actual.get('total_spent')}"
        assert int(actual.get("total_interaction_time", 0)) == expected["total_interaction_time"], f"Record {i}: Expected total_interaction_time {expected['total_interaction_time']}, got {actual.get('total_interaction_time')}"


def test_script_parameterization():
    """Test executing the script with different parameters to ensure queries are parameterized."""
    output_path = "/home/user/test_report_2.json"
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH, "refunded", "100", output_path],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Script execution failed with return code {result.returncode}.\nStderr: {result.stderr}"
    assert os.path.exists(output_path), f"Output JSON file was not created at {output_path}"

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} does not contain valid JSON.")

    expected_data = [
        {"customer_name": "Alice Smith", "total_spent": 50.0, "total_interaction_time": 120},
        {"customer_name": "Bob Jones", "total_spent": 0.0, "total_interaction_time": 300},
        {"customer_name": "Charlie Brown", "total_spent": 0.0, "total_interaction_time": 0}
    ]

    assert isinstance(data, list), "Output JSON must be an array of objects."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get("customer_name") == expected["customer_name"], f"Record {i}: Expected customer_name '{expected['customer_name']}', got '{actual.get('customer_name')}'"
        assert float(actual.get("total_spent", 0)) == expected["total_spent"], f"Record {i}: Expected total_spent {expected['total_spent']}, got {actual.get('total_spent')}"
        assert int(actual.get("total_interaction_time", 0)) == expected["total_interaction_time"], f"Record {i}: Expected total_interaction_time {expected['total_interaction_time']}, got {actual.get('total_interaction_time')}"


def _derive_expected(status_value, minimum_duration):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            """
            WITH order_totals AS (
                SELECT fk_client_id, SUM(purchase_amount) AS total_spent
                FROM purchase_history
                WHERE current_status = ?
                GROUP BY fk_client_id
            ),
            interaction_totals AS (
                SELECT fk_client_id, SUM(duration_secs) AS total_interaction_time
                FROM support_logs
                WHERE duration_secs >= ?
                GROUP BY fk_client_id
            )
            SELECT c.full_name,
                   COALESCE(o.total_spent, 0),
                   COALESCE(i.total_interaction_time, 0)
            FROM client_records AS c
            LEFT JOIN order_totals AS o ON o.fk_client_id = c.client_id
            LEFT JOIN interaction_totals AS i ON i.fk_client_id = c.client_id
            WHERE EXISTS (
                SELECT 1 FROM purchase_history AS p
                WHERE p.fk_client_id = c.client_id
            ) OR EXISTS (
                SELECT 1 FROM support_logs AS s
                WHERE s.fk_client_id = c.client_id
            )
            ORDER BY COALESCE(o.total_spent, 0) DESC, c.full_name ASC
            """,
            (status_value, minimum_duration),
        ).fetchall()
    finally:
        conn.close()

    return [
        {
            "customer_name": name,
            "total_spent": float(spent),
            "total_interaction_time": int(duration),
        }
        for name, spent, duration in rows
    ]


def _run_and_check(status_value, minimum_duration, output_path):
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH, status_value, str(minimum_duration), output_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Script execution failed with return code {result.returncode}.\nStderr: {result.stderr}"
    assert os.path.isfile(output_path), f"Output JSON file was not created at {output_path}"

    with open(output_path, "r") as f:
        data = json.load(f)

    assert isinstance(data, list), "Output JSON must be an array of objects."
    normalized = []
    required_keys = {"customer_name", "total_spent", "total_interaction_time"}
    for index, row in enumerate(data):
        assert isinstance(row, dict), f"Record {index} is not an object"
        assert set(row) == required_keys, f"Record {index} has incorrect fields: {set(row)}"
        normalized.append({
            "customer_name": row["customer_name"],
            "total_spent": float(row["total_spent"]),
            "total_interaction_time": int(row["total_interaction_time"]),
        })

    assert normalized == _derive_expected(status_value, minimum_duration)


def test_dynamic_database_content_and_unseen_parameters():
    """Exercise unpredictable database rows, statuses, thresholds, and an injection-shaped value."""
    token = uuid.uuid4().hex
    quoted_status = "audit_' OR 1=1 -- " + token
    plain_status = "audit_plain_" + token
    threshold = 40 + (int(token[:4], 16) % 80)
    backup_path = "/tmp/analytics_audit_" + token + ".db"
    outputs = [
        "/home/user/.audit_report_" + token + "_1.json",
        "/home/user/.audit_report_" + token + "_2.json",
    ]
    shutil.copy2(DB_PATH, backup_path)

    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        next_client = cur.execute("SELECT COALESCE(MAX(client_id), 0) + 1 FROM client_records").fetchone()[0]
        next_purchase = cur.execute("SELECT COALESCE(MAX(purchase_id), 0) + 1 FROM purchase_history").fetchone()[0]
        next_log = cur.execute("SELECT COALESCE(MAX(log_id), 0) + 1 FROM support_logs").fetchone()[0]

        clients = [
            (next_client, "Verifier Z " + token, "z@audit.invalid"),
            (next_client + 1, "Verifier A " + token, "a@audit.invalid"),
            (next_client + 2, "Verifier Events " + token, "e@audit.invalid"),
            (next_client + 3, "Verifier Empty " + token, "n@audit.invalid"),
        ]
        cur.executemany("INSERT INTO client_records VALUES (?, ?, ?)", clients)

        purchases = [
            (next_purchase, next_client, 17.25, quoted_status),
            (next_purchase + 1, next_client, 31.75, quoted_status),
            (next_purchase + 2, next_client + 1, 49.0, quoted_status),
            (next_purchase + 3, next_client, 70.0, plain_status),
            (next_purchase + 4, next_client + 1, 12.0, plain_status),
            (next_purchase + 5, next_client + 2, 9.0, "nonmatching_" + token),
        ]
        cur.executemany("INSERT INTO purchase_history VALUES (?, ?, ?, ?)", purchases)

        logs = [
            (next_log, next_client, threshold),
            (next_log + 1, next_client, threshold + 7),
            (next_log + 2, next_client + 1, threshold - 1),
            (next_log + 3, next_client + 2, threshold + 3),
        ]
        cur.executemany("INSERT INTO support_logs VALUES (?, ?, ?)", logs)
        conn.commit()
        conn.close()

        _run_and_check(quoted_status, threshold, outputs[0])
        _run_and_check(plain_status, threshold + 2, outputs[1])
    finally:
        for output in outputs:
            if os.path.exists(output):
                os.remove(output)
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
