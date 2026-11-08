#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import csv
import pytest
from collections import Counter

def test_top_5_triangles_csv():
    csv_path = '/home/user/top_5_triangles.csv'
    db_path = '/home/user/graph.db'

    assert os.path.exists(csv_path), f"Output file missing at {csv_path}"
    assert os.path.exists(db_path), f"Database file missing at {db_path}"

    # Compute the expected result dynamically from the database
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    query = """
    SELECT c1.u1 AS u1_id, c1.u2 AS u2_id, c2.u2 AS u3_id, 
           (c1.weight + c2.weight + c3.weight) AS total_weight
    FROM connections c1
    JOIN connections c2 ON c1.u2 = c2.u1
    JOIN connections c3 ON c1.u1 = c3.u1 AND c2.u2 = c3.u2
    JOIN users u1 ON c1.u1 = u1.id
    JOIN users u2 ON c1.u2 = u2.id
    JOIN users u3 ON c2.u2 = u3.id
    WHERE u1.department = 'Engineering' 
      AND u2.department = 'Engineering' 
      AND u3.department = 'Engineering'
    ORDER BY total_weight DESC, u1_id ASC, u2_id ASC, u3_id ASC
    LIMIT 5;
    """

    c.execute(query)
    expected_rows = c.fetchall()
    conn.close()

    # Read the CSV file
    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        actual_rows = []
        for row in reader:
            if row:
                actual_rows.append(tuple(int(x) for x in row))

    expected_header = ['u1_id', 'u2_id', 'u3_id', 'total_weight']
    assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}"

    assert actual_rows == expected_rows, f"CSV data does not match expected output.\nExpected: {expected_rows}\nGot: {actual_rows}"

def test_query_plan_txt():
    txt_path = '/home/user/query_plan.txt'
    db_path = '/home/user/graph.db'
    assert os.path.exists(txt_path), f"Query plan file missing at {txt_path}"

    with open(txt_path, 'r') as f:
        content = f.read().upper()

    # Keep the original basic validity assertion.
    valid_keywords = ["SCAN", "SEARCH", "USING INDEX", "COROUTINE", "B-TREE", "LIST"]
    has_keyword = any(keyword in content for keyword in valid_keywords)
    assert has_keyword, "query_plan.txt does not appear to contain a valid SQLite EXPLAIN QUERY PLAN output."

    # Derive the real plan for the corrected triangle query from this database.
    corrected_query = """
    SELECT c1.u1 AS u1_id, c1.u2 AS u2_id, c2.u2 AS u3_id,
           (c1.weight + c2.weight + c3.weight) AS total_weight
    FROM connections c1
    JOIN connections c2 ON c1.u2 = c2.u1
    JOIN connections c3 ON c1.u1 = c3.u1 AND c2.u2 = c3.u2
    JOIN users u1 ON c1.u1 = u1.id
    JOIN users u2 ON c1.u2 = u2.id
    JOIN users u3 ON c2.u2 = u3.id
    WHERE u1.department = 'Engineering'
      AND u2.department = 'Engineering'
      AND u3.department = 'Engineering'
    ORDER BY total_weight DESC, u1_id ASC, u2_id ASC, u3_id ASC
    LIMIT 5
    """
    conn = sqlite3.connect(db_path)
    expected_plan = conn.execute("EXPLAIN QUERY PLAN " + corrected_query).fetchall()
    conn.close()

    expected_details = [str(row[3]).upper() for row in expected_plan]
    assert expected_details, "SQLite unexpectedly returned an empty query plan"

    # Accept normal raw renderings (sqlite3 tree/table/CSV or tuple output), while
    # requiring every operation of the actual corrected query's plan in order.
    position = 0
    for detail in expected_details:
        found = content.find(detail, position)
        assert found != -1, (
            "query_plan.txt is not the EXPLAIN QUERY PLAN output for the corrected "
            f"triangle query; missing or out-of-order operation: {detail}"
        )
        position = found + len(detail)

    # Also reject files padded with duplicate plan-operation text.
    for detail, expected_count in Counter(expected_details).items():
        assert content.count(detail) == expected_count, (
            f"query_plan.txt contains an unexpected number of plan operations: {detail}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
