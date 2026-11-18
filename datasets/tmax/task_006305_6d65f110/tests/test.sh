#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess

import pytest

DB_PATH = '/home/user/finance.db'
SOURCE_PATH = '/home/user/audit.cpp'
EXECUTABLE_PATH = '/home/user/audit'
RESULTS_PATH = '/home/user/audit_results.json'


def get_expected_results():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    query = """
    WITH Deadlocks AS (
        SELECT account_id, event_timestamp
        FROM system_events
        WHERE event_code = 'ERR_DEADLOCK'
    ),
    Suspicious AS (
        SELECT DISTINCT d1.account_id
        FROM Deadlocks d1
        JOIN Deadlocks d2 ON d1.account_id = d2.account_id
        WHERE d1.event_timestamp < d2.event_timestamp
          AND (d2.event_timestamp - d1.event_timestamp) <= 3600
    )
    SELECT s.account_id,
           COALESCE(SUM(CASE WHEN t.tx_type = 'CREDIT' THEN t.amount ELSE 0 END), 0) -
           COALESCE(SUM(CASE WHEN t.tx_type = 'DEBIT' THEN t.amount ELSE 0 END), 0) AS net_volume
    FROM Suspicious s
    LEFT JOIN tx_records t ON s.account_id = t.account_id AND t.status = 'COMPLETED'
    GROUP BY s.account_id
    ORDER BY s.account_id ASC
    """
    c.execute(query)
    results = c.fetchall()
    conn.close()
    return [{"account_id": row[0], "net_volume": round(row[1], 2)} for row in results]


@pytest.fixture(scope='session', autouse=True)
def validate_and_run_submission():
    assert os.path.isfile(SOURCE_PATH), f"The required source file {SOURCE_PATH} is missing."
    with open(SOURCE_PATH, 'r', errors='replace') as f:
        source = f.read()
    assert re.search(r'#\s*include\s*[<\"]sqlite3\.h[>\"]', source), \
        "audit.cpp must include sqlite3.h."
    assert re.search(r'\bsqlite3_(open|open_v2)\s*\(', source), \
        "audit.cpp must open the database through the SQLite C/C++ API."
    assert re.search(r'\bsqlite3_(prepare|prepare_v2|exec)\s*\(', source), \
        "audit.cpp must execute SQL through the SQLite C/C++ API."

    assert os.path.isfile(EXECUTABLE_PATH), f"The required executable {EXECUTABLE_PATH} is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable."
    with open(EXECUTABLE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{EXECUTABLE_PATH} is not a compiled executable."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    while True:
        suspicious_id = 700000000 + secrets.randbelow(100000000)
        ordinary_id = 800000000 + secrets.randbelow(100000000)
        c.execute(
            "SELECT 1 FROM system_events WHERE account_id IN (?, ?) LIMIT 1",
            (suspicious_id, ordinary_id),
        )
        if c.fetchone() is None:
            break

    base_time = 1800000000 + secrets.randbelow(10000000)
    credit = (10000 + secrets.randbelow(900000)) / 100.0
    debit = (1 + secrets.randbelow(9000)) / 100.0
    adjustment = (1 + secrets.randbelow(50000)) / 100.0

    c.executemany(
        "INSERT INTO system_events(account_id, event_code, event_timestamp) VALUES (?, ?, ?)",
        [
            (suspicious_id, 'ERR_DEADLOCK', base_time),
            (suspicious_id, 'ERR_DEADLOCK', base_time + 3600),
            (ordinary_id, 'ERR_DEADLOCK', base_time),
            (ordinary_id, 'ERR_DEADLOCK', base_time + 3601),
            (suspicious_id, 'INFO', base_time + 10),
        ],
    )
    c.executemany(
        "INSERT INTO tx_records(account_id, tx_type, amount, status) VALUES (?, ?, ?, ?)",
        [
            (suspicious_id, 'CREDIT', credit, 'COMPLETED'),
            (suspicious_id, 'DEBIT', debit, 'COMPLETED'),
            (suspicious_id, 'CREDIT', 98765.43, 'ROLLED_BACK'),
            (ordinary_id, 'CREDIT', 12345.67, 'COMPLETED'),
            (101, 'CREDIT', adjustment, 'COMPLETED'),
        ],
    )
    conn.commit()
    conn.close()

    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    completed = subprocess.run(
        [EXECUTABLE_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, \
        f"audit exited with status {completed.returncode}: {completed.stderr}"


def test_results_file_exists():
    assert os.path.isfile(RESULTS_PATH), f"The expected output file {RESULTS_PATH} is missing."


def test_results_content():
    try:
        with open(RESULTS_PATH, 'r') as f:
            raw = f.read()
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"The file {RESULTS_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be an array of objects."
    expected_data = get_expected_results()
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Record {i} must be a JSON object."
        assert "account_id" in actual, f"Record {i} is missing 'account_id'"
        assert "net_volume" in actual, f"Record {i} is missing 'net_volume'"
        assert actual["account_id"] == expected["account_id"], \
            f"Expected account_id {expected['account_id']} at index {i}, but got {actual['account_id']}."
        assert isinstance(actual["net_volume"], (int, float)) and not isinstance(actual["net_volume"], bool), \
            f"net_volume for record {i} must be numeric."
        assert abs(actual["net_volume"] - expected["net_volume"]) < 0.001, \
            f"Expected net_volume {expected['net_volume']} for account {expected['account_id']}, but got {actual['net_volume']}."

    formatted_values = re.findall(r'"net_volume"\s*:\s*(-?\d+\.\d{2})(?=\s*[,}])', raw)
    assert len(formatted_values) == len(data), "Every net_volume must be formatted with exactly two decimal places."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
