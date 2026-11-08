#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import pytest


def test_analyze_go_uses_sql_window_query():
    source_path = '/home/user/analyze.go'
    assert os.path.isfile(source_path), f"The file {source_path} does not exist."
    with open(source_path, 'r', encoding='utf-8') as f:
        source = f.read()

    assert re.search(r'"database/sql"', source), "analyze.go must use Go's database/sql package."
    assert re.search(r'\bsql\.Open\s*\(', source), "analyze.go must open the SQLite database through database/sql."
    assert re.search(r'\.Query(?:Context)?\s*\(', source), "analyze.go must execute the SQL query from Go."
    assert re.search(r'\bRANK\s*\(\s*\)\s*OVER\s*\(', source, re.IGNORECASE | re.DOTALL), \
        "The SQL query in analyze.go must use the RANK() window function."


def test_recommendations_json_exists():
    assert os.path.isfile('/home/user/recommendations.json'), "The file /home/user/recommendations.json does not exist."


def test_recommendations_content():
    db_path = '/home/user/graph.db'
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    # Compute expected results dynamically from the database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    WITH mutual_counts AS (
        SELECT e1.source_id AS user1, e2.source_id AS user2, COUNT(*) AS mutual_friends
        FROM edges e1
        JOIN edges e2 ON e1.target_id = e2.target_id
        WHERE e1.source_id < e2.source_id
        AND NOT EXISTS (
            SELECT 1 FROM edges e3
            WHERE e3.source_id = e1.source_id AND e3.target_id = e2.source_id
        )
        GROUP BY e1.source_id, e2.source_id
    )
    SELECT user1, user2, mutual_friends,
           RANK() OVER (ORDER BY mutual_friends DESC, user1 ASC, user2 ASC) as rank
    FROM mutual_counts
    ORDER BY rank
    LIMIT 10;
    """

    cursor.execute(query)
    expected_rows = cursor.fetchall()
    conn.close()

    expected_data = []
    for row in expected_rows:
        expected_data.append({
            "user1": row[0],
            "user2": row[1],
            "mutual_friends": row[2],
            "rank": row[3]
        })

    with open('/home/user/recommendations.json', 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/recommendations.json does not contain valid JSON.")

    assert isinstance(actual_data, list), "The JSON output should be a list of objects."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} recommendations, but got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get('user1') == expected['user1'], f"Mismatch at rank {expected['rank']}: expected user1={expected['user1']}, got {actual.get('user1')}."
        assert actual.get('user2') == expected['user2'], f"Mismatch at rank {expected['rank']}: expected user2={expected['user2']}, got {actual.get('user2')}."
        assert actual.get('mutual_friends') == expected['mutual_friends'], f"Mismatch at rank {expected['rank']}: expected mutual_friends={expected['mutual_friends']}, got {actual.get('mutual_friends')}."
        assert actual.get('rank') == expected['rank'], f"Mismatch at index {i}: expected rank={expected['rank']}, got {actual.get('rank')}."
TEST_EOF

status=0
cp /home/user/graph.db /tmp/graph.db.verifier-backup

(
    set -e

    run_analyzer() {
        local before after
        before=$(sha256sum /home/user/graph.db | awk '{print $1}')
        rm -f /home/user/recommendations.json
        cd /home/user
        timeout 180s go run analyze.go
        test -f /home/user/recommendations.json
        after=$(sha256sum /home/user/graph.db | awk '{print $1}')
        test "$before" = "$after"
    }

    # Execute the submitted Go program against the original database, then retain
    # all of the original verifier's content assertions.
    run_analyzer
    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    # Exercise the implementation on a distinct graph so a fixed or hardcoded
    # recommendations.json cannot pass.
    python3 - << 'PY_EOF'
import random
import sqlite3

path = '/home/user/graph.db'
conn = sqlite3.connect(path)
cur = conn.cursor()
cur.execute('DROP TABLE IF EXISTS edges')
cur.execute('CREATE TABLE edges (source_id INTEGER, target_id INTEGER)')

rng = random.Random(918273)
nodes = list(range(101, 121))
undirected = []
for i, a in enumerate(nodes):
    for b in nodes[i + 1:]:
        if rng.random() < 0.27:
            undirected.append((a, b))

rows = []
for a, b in undirected:
    rows.append((a, b))
    rows.append((b, a))
cur.executemany('INSERT INTO edges(source_id, target_id) VALUES (?, ?)', rows)
conn.commit()
conn.close()
PY_EOF

    run_analyzer
    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    # Restore the task database and leave the required final output generated by
    # the submitted Go program for that database.
    cp /tmp/graph.db.verifier-backup /home/user/graph.db
    run_analyzer
    python3 -m pytest /tmp/test_final_state.py -x --tb=short
) || status=1

# Always restore the original database, including on a failed verification run.
cp /tmp/graph.db.verifier-backup /home/user/graph.db

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
