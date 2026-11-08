#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

REPORT_PATH = "/home/user/anomaly_report.csv"
DB_PATH = "/home/user/backups.db"

def get_expected_anomalies():
    """Derives the expected anomalies directly from the database using the task's logic."""
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file missing at {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    query = """
    WITH RECURSIVE downstream AS (
        SELECT 'db-main' AS node
        UNION
        SELECT t.target_node
        FROM topology t
        JOIN downstream d ON t.source_node = d.node
    ),
    rolling AS (
        SELECT 
            j.node,
            j.job_id,
            j.size_mb,
            j.run_date,
            AVG(j.size_mb) OVER (
                PARTITION BY j.node 
                ORDER BY j.run_date ASC 
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
            ) as rolling_avg,
            ROW_NUMBER() OVER (
                PARTITION BY j.node 
                ORDER BY j.run_date DESC
            ) as rn
        FROM jobs j
        JOIN downstream d ON j.node = d.node
        WHERE j.status = 'SUCCESS'
    )
    SELECT 
        node, 
        job_id, 
        size_mb, 
        ROUND(rolling_avg, 2) as rolling_avg
    FROM rolling
    WHERE rn = 1 AND size_mb > 1.5 * rolling_avg
    ORDER BY size_mb DESC;
    """

    cursor.execute(query)
    results = cursor.fetchall()
    conn.close()

    return [f"{row[0]}|{row[1]}|{row[2]}|{row[3]:.2f}".replace(".00", ".0").replace(".30", ".3") for row in results]

def test_anomaly_report_exists():
    """Test that the output CSV file exists."""
    assert os.path.exists(REPORT_PATH), f"Output file missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file"

def test_anomaly_report_content():
    """Test that the anomaly report contains the correct derived data."""
    if not os.path.exists(REPORT_PATH):
        pytest.fail(f"Cannot check content, file missing: {REPORT_PATH}")

    expected_lines = get_expected_anomalies()

    with open(REPORT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    # We parse the actual output to allow for slight formatting differences in floats
    # e.g., 300 vs 300.0
    parsed_actual = []
    for line in actual_lines:
        parts = line.split("|")
        if len(parts) != 4:
            pytest.fail(f"Line does not have exactly 4 columns separated by '|': {line}")
        node, job_id, size_mb, rolling_avg = parts
        try:
            parsed_actual.append((node, job_id, float(size_mb), float(rolling_avg)))
        except ValueError:
            pytest.fail(f"Non-numeric value found in size_mb or rolling_avg: {line}")

    parsed_expected = []
    for line in expected_lines:
        parts = line.split("|")
        parsed_expected.append((parts[0], parts[1], float(parts[2]), float(parts[3])))

    assert len(parsed_actual) == len(parsed_expected), f"Expected {len(parsed_expected)} rows, found {len(parsed_actual)}"

    for i, (actual, expected) in enumerate(zip(parsed_actual, parsed_expected)):
        assert actual[0] == expected[0], f"Row {i+1}: Expected node {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"Row {i+1}: Expected job_id {expected[1]}, got {actual[1]}"
        assert abs(actual[2] - expected[2]) < 1e-5, f"Row {i+1}: Expected size_mb {expected[2]}, got {actual[2]}"
        assert abs(actual[3] - expected[3]) < 1e-5, f"Row {i+1}: Expected rolling_avg {expected[3]}, got {actual[3]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
