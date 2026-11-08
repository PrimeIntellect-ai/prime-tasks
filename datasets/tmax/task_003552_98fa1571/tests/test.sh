#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

def test_top_authors_file_exists():
    """Test that the output JSON file exists."""
    assert os.path.isfile('/home/user/top_authors.json'), "/home/user/top_authors.json is missing."

def test_top_authors_content():
    """Test that the output JSON matches the expected structure and data derived from the DB."""

    # Recompute the expected results from the database, ignoring the cache
    db_path = '/home/user/research_data.db'
    assert os.path.isfile(db_path), "Database file missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    SELECT a.name, COUNT(c.source_id) as impact_score
    FROM authors a
    JOIN papers p ON a.id = p.author_id
    LEFT JOIN citations c ON p.id = c.target_id
    GROUP BY a.id, a.name
    ORDER BY impact_score DESC, a.name ASC
    LIMIT 3
    """
    cursor.execute(query)
    expected_rows = cursor.fetchall()
    conn.close()

    expected_top_authors = [
        {"name": row[0], "impact_score": row[1]}
        for row in expected_rows
    ]

    # Now read the output file
    with open('/home/user/top_authors.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/top_authors.json is not a valid JSON file.")

    # Check structure
    assert isinstance(data, dict), "The root of the JSON must be an object."
    assert "top_authors" in data, "The JSON must contain a 'top_authors' key."
    assert isinstance(data["top_authors"], list), "'top_authors' must be an array."
    assert len(data["top_authors"]) == 3, "'top_authors' must contain exactly 3 items."

    for item in data["top_authors"]:
        assert isinstance(item, dict), "Each item in 'top_authors' must be an object."
        assert "name" in item, "Each item must have a 'name' key."
        assert "impact_score" in item, "Each item must have an 'impact_score' key."
        assert isinstance(item["name"], str), "'name' must be a string."
        assert isinstance(item["impact_score"], int), "'impact_score' must be an integer."

    # Check exact equivalence
    assert data["top_authors"] == expected_top_authors, (
        f"The top_authors data is incorrect.\n"
        f"Expected: {expected_top_authors}\n"
        f"Found: {data['top_authors']}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
