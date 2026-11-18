#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
import time

import pytest

DB_PATH = '/app/data/audit_logs.db'
ENGINE_PATH = '/app/legacy_risk_scorer'


def get_user_stats():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT u_id, COUNT(event_id), COUNT(DISTINCT ip_address)
        FROM access_events
        GROUP BY u_id
    """)
    stats = {u_id: (total_events, distinct_ips)
             for u_id, total_events, distinct_ips in cursor.fetchall()}
    conn.close()
    return stats


def get_expected_flagged_users():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Get all users, their total events, and distinct IPs
    cursor.execute("""
        SELECT u_id, COUNT(event_id), COUNT(DISTINCT ip_address)
        FROM access_events
        GROUP BY u_id
    """)
    user_stats = cursor.fetchall()

    flagged_users = []
    for u_id, total_events, distinct_ips in user_stats:
        if distinct_ips > 0:
            score = 1.0 - (total_events / (distinct_ips * 10.0))
            if score < 0:
                score = 0.0
            if score > 0.80:
                flagged_users.append(u_id)

    # Calculate total tx amount for flagged users
    expected_results = {}
    if flagged_users:
        placeholders = ','.join(['?'] * len(flagged_users))
        cursor.execute(f"""
            SELECT u_id, SUM(amount)
            FROM tx_data
            WHERE u_id IN ({placeholders})
            GROUP BY u_id
        """, flagged_users)

        for u_id, total_amount in cursor.fetchall():
            expected_results[u_id] = round(total_amount, 2)

    conn.close()
    return expected_results


def index_columns(cursor, table):
    cursor.execute(f'PRAGMA index_list("{table}")')
    indexes = []
    for row in cursor.fetchall():
        name = row[1]
        escaped_name = name.replace('"', '""')
        cursor.execute(f'PRAGMA index_info("{escaped_name}")')
        columns = [info[2] for info in cursor.fetchall()]
        indexes.append((name, columns))
    return indexes


def assert_required_indexes():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    access_indexes = index_columns(cursor, 'access_events')
    tx_indexes = index_columns(cursor, 'tx_data')
    conn.close()

    assert any(cols and cols[0] == 'u_id' and 'ip_address' in cols
               for _, cols in access_indexes), \
        f"Missing useful access_events index beginning with u_id and including ip_address; found {access_indexes}"
    assert any(cols and cols[0] == 'u_id' for _, cols in tx_indexes), \
        f"Missing useful tx_data index beginning with u_id; found {tx_indexes}"


def parse_scorer_input(capture_path):
    assert os.path.isfile(capture_path), "The legacy scoring engine was not invoked"
    observed = {}
    with open(capture_path, newline='') as f:
        for row in csv.reader(f):
            if not row:
                continue
            assert len(row) == 3, f"Invalid CSV sent to scoring engine: {row}"
            user_id = row[0]
            assert user_id not in observed, f"Duplicate user sent to scoring engine: {user_id}"
            try:
                observed[user_id] = (int(row[1]), int(row[2]))
            except ValueError:
                pytest.fail(f"Non-integer statistics sent to scoring engine: {row}")
    return observed


def test_audit_aggregator_execution_and_output():
    script_path = '/home/user/audit_aggregator.py'
    output_path = '/home/user/flagged_users.json'

    assert os.path.isfile(script_path), f"Script missing at {script_path}"
    assert os.path.isfile(ENGINE_PATH) and os.access(ENGINE_PATH, os.X_OK), \
        f"Legacy scoring engine missing or not executable at {ENGINE_PATH}"

    # Transparently wrap the required engine so its stdin can be verified while
    # preserving the engine's real stdout and exit status.
    temp_dir = tempfile.mkdtemp(prefix='audit_verifier_')
    backup_engine = os.path.join(temp_dir, 'legacy_risk_scorer.real')
    capture_path = os.path.join(temp_dir, 'scorer_input.csv')
    shutil.copy2(ENGINE_PATH, backup_engine)
    wrapper = (
        '#!/bin/sh\n'
        f'tee -a {shlex.quote(capture_path)} | {shlex.quote(backup_engine)} "$@"\n'
    )
    with open(ENGINE_PATH, 'w') as f:
        f.write(wrapper)
    os.chmod(ENGINE_PATH, 0o755)

    # Remove output file if it exists to ensure we measure fresh generation
    if os.path.exists(output_path):
        os.remove(output_path)

    try:
        start_time = time.time()
        proc = subprocess.run(["python3", script_path], capture_output=True, text=True)
        runtime = time.time() - start_time
    finally:
        shutil.copy2(backup_engine, ENGINE_PATH)

    assert proc.returncode == 0, f"Script failed to execute. stderr: {proc.stderr}"
    assert runtime < 3.0, f"Execution time={runtime:.2f}s exceeded threshold of 3.0s"

    # Verify both mandatory implementation requirements.
    assert_required_indexes()
    observed_stats = parse_scorer_input(capture_path)
    expected_stats = get_user_stats()
    assert observed_stats == expected_stats, \
        "The scoring engine was not given the per-user access-event and distinct-IP data"

    assert os.path.isfile(output_path), f"Output file missing at {output_path}"

    with open(output_path, 'r') as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON")

    expected_results = get_expected_flagged_users()

    # Check exact match
    assert set(actual_results.keys()) == set(expected_results.keys()), \
        f"Keys mismatch. Expected: {list(expected_results.keys())}, Got: {list(actual_results.keys())}"

    for k, expected_val in expected_results.items():
        actual_val = actual_results[k]
        assert abs(actual_val - expected_val) < 1e-5, \
            f"Value mismatch for user {k}. Expected: {expected_val}, Got: {actual_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
