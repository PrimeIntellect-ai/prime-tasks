#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import sqlite3

def test_result_json():
    result_path = '/home/user/result.json'
    assert os.path.exists(result_path), f"Output file {result_path} is missing. Did you create it?"

    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{result_path} is not a valid JSON file."

    assert "top_author" in data, "Key 'top_author' is missing from the JSON output."
    assert "coauthor_count" in data, "Key 'coauthor_count' is missing from the JSON output."

    # Compute the expected top author and count from the database to be robust
    db_path = '/home/user/research.db'
    assert os.path.exists(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''
        SELECT a1.name, COUNT(DISTINCT a2.author_id)
        FROM paper_authors a1_pa
        JOIN authors a1 ON a1.id = a1_pa.author_id
        JOIN paper_authors a2 ON a1_pa.paper_id = a2.paper_id AND a1_pa.author_id != a2.author_id
        GROUP BY a1.id
        ORDER BY COUNT(DISTINCT a2.author_id) DESC, a1.name ASC
        LIMIT 1
    ''')
    row = c.fetchone()
    conn.close()

    assert row is not None, "Could not compute top author from database."
    expected_author, expected_count = row

    assert data["top_author"] == expected_author, f"Expected top_author to be '{expected_author}', but got '{data['top_author']}'."
    assert data["coauthor_count"] == expected_count, f"Expected coauthor_count to be {expected_count}, but got {data['coauthor_count']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
