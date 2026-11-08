#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import csv
import math
import os
import sqlite3

import networkx as nx
import pytest

DB_PATH = '/home/user/company_analytics.db'
EMPLOYEES_PATH = '/home/user/raw_data/employees.csv'
MESSAGES_PATH = '/home/user/raw_data/messages.csv'


def expected_pagerank():
    """Derive the required weighted PageRank scores from the input CSV files."""
    graph = nx.DiGraph()

    with open(EMPLOYEES_PATH, newline='') as f:
        for row in csv.DictReader(f):
            graph.add_node(int(row['emp_id']))

    with open(MESSAGES_PATH, newline='') as f:
        for row in csv.DictReader(f):
            sender = int(row['sender_id'])
            receiver = int(row['receiver_id'])
            if graph.has_edge(sender, receiver):
                graph[sender][receiver]['weight'] += 1
            else:
                graph.add_edge(sender, receiver, weight=1)

    return nx.pagerank(graph, alpha=0.85, weight='weight')


@pytest.fixture
def db_connection():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} was not created."
    conn = sqlite3.connect(DB_PATH)
    yield conn
    conn.close()


def test_database_exists():
    """Verify that the SQLite database is created at the correct path."""
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"


def test_influencers_table(db_connection):
    """Verify the influencers table structure and content."""
    cur = db_connection.cursor()

    # Check if table exists
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='influencers'")
    assert cur.fetchone() is not None, "Table 'influencers' does not exist."

    # Check data
    cur.execute("SELECT emp_id, name, department, influencer_score FROM influencers ORDER BY emp_id")
    rows = cur.fetchall()

    assert len(rows) == 5, f"Expected 5 rows in influencers table, got {len(rows)}."

    expected_employees = {
        1: ('Alice', 'Engineering'),
        2: ('Bob', 'Engineering'),
        3: ('Charlie', 'HR'),
        4: ('Diana', 'Marketing'),
        5: ('Eve', 'Executive')
    }
    expected_scores = expected_pagerank()

    total_score = 0.0
    for row in rows:
        emp_id, name, department, score = row
        assert emp_id in expected_employees, f"Unexpected emp_id {emp_id}."
        assert name == expected_employees[emp_id][0], f"Expected name {expected_employees[emp_id][0]} for emp_id {emp_id}, got {name}."
        assert department == expected_employees[emp_id][1], f"Expected department {expected_employees[emp_id][1]} for emp_id {emp_id}, got {department}."
        assert isinstance(score, float), f"Influencer score for emp_id {emp_id} should be a float, got {type(score)}."
        assert math.isclose(score, expected_scores[emp_id], rel_tol=1e-6, abs_tol=1e-6), (
            f"Incorrect PageRank score for emp_id {emp_id}: expected "
            f"{expected_scores[emp_id]}, got {score}."
        )
        total_score += score

    # PageRank scores from NetworkX typically sum to 1.0
    assert 0.99 <= total_score <= 1.01, f"PageRank scores should sum to approximately 1.0, got {total_score}."


def test_triangles_table(db_connection):
    """Verify the triangles table structure and content."""
    cur = db_connection.cursor()

    # Check if table exists
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='triangles'")
    assert cur.fetchone() is not None, "Table 'triangles' does not exist."

    # Check data
    cur.execute("SELECT emp_a, emp_b, emp_c FROM triangles ORDER BY emp_a, emp_b, emp_c")
    rows = cur.fetchall()

    expected_triangles = [
        (1, 2, 3),
        (1, 2, 4)
    ]

    assert rows == expected_triangles, f"Expected triangles {expected_triangles}, got {rows}."

    # Verify the a < b < c constraint is respected in the results
    for a, b, c in rows:
        assert a < b < c, f"Triangle ({a}, {b}, {c}) does not satisfy emp_a < emp_b < emp_c."
TEST_EOF

if test -f /home/user/etl_pipeline.py \
   && python3 /home/user/etl_pipeline.py \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
