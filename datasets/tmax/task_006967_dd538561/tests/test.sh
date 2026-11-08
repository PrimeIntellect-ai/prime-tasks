#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

OUTPUT_PATH = '/home/user/citation_patterns.json'
DB_PATH = '/home/user/research_data.db'

def get_expected_chains():
    """Dynamically compute the expected chains directly from the SQLite database."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    query = """
    SELECT pA.title, pB.title, pC.title
    FROM citations c1
    JOIN citations c2 ON c1.cited_paper_id = c2.citing_paper_id
    JOIN papers pA ON c1.citing_paper_id = pA.id
    JOIN papers pB ON c1.cited_paper_id = pB.id
    JOIN papers pC ON c2.cited_paper_id = pC.id
    WHERE pA.year >= 2010 AND pB.year >= 2010 AND pC.year >= 2010
    AND NOT EXISTS (
        SELECT 1 FROM paper_authors pa1 
        JOIN paper_authors pa2 ON pa1.author_id = pa2.author_id
        WHERE pa1.paper_id = pA.id AND pa2.paper_id = pB.id
    )
    AND NOT EXISTS (
        SELECT 1 FROM paper_authors pa2 
        JOIN paper_authors pa3 ON pa2.author_id = pa3.author_id
        WHERE pa2.paper_id = pB.id AND pa3.paper_id = pC.id
    )
    AND NOT EXISTS (
        SELECT 1 FROM paper_authors pa1 
        JOIN paper_authors pa3 ON pa1.author_id = pa3.author_id
        WHERE pa1.paper_id = pA.id AND pa3.paper_id = pC.id
    )
    ORDER BY pA.title ASC, pB.title ASC, pC.title ASC
    """

    c.execute(query)
    results = c.fetchall()
    conn.close()

    expected = [{"chain": [row[0], row[1], row[2]]} for row in results]
    return expected

def test_json_output_exists():
    """Check if the JSON output file was created."""
    assert os.path.exists(OUTPUT_PATH), f"Output file missing at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file"

def test_json_output_contents():
    """Validate the contents of the JSON output file."""
    assert os.path.exists(OUTPUT_PATH), f"Output file missing at {OUTPUT_PATH}"

    try:
        with open(OUTPUT_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File at {OUTPUT_PATH} is not valid JSON.")

    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}"

    expected_data = get_expected_chains()

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} chains, but found {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary"
        assert "chain" in actual, f"Item at index {i} is missing the 'chain' key"
        assert isinstance(actual["chain"], list), f"The 'chain' key at index {i} does not map to a list"
        assert len(actual["chain"]) == 3, f"The chain at index {i} does not have exactly 3 papers"
        assert actual == expected, f"Chain at index {i} does not match expected. Actual: {actual}, Expected: {expected}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
