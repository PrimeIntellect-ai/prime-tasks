#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import json
import subprocess
import pytest

DB_PATH = "/home/user/citation_network.db"
SCRIPT_PATH = "/home/user/export_graph_metrics.sh"

EXPECTED_PAPERS = [
    (1, "Graph Theory Basics", 2010),
    (2, "Advanced Graph Analytics", 2015),
    (3, "Modern AI", 2019),
    (4, "Deep Learning Innovations", 2020),
    (5, "Future of Tech", 2021),
    (6, "Old Paper", 1999),
    (7, "Another Old Paper", 2005),
]

EXPECTED_CITATIONS = sorted([
    (2, 1),
    (3, 1),
    (4, 1),
    (5, 1),
    (6, 1),
    (3, 2),
    (4, 2),
    (5, 2),
    (4, 3),
    (5, 3),
    (5, 4),
])


def assert_fixture_intact():
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        papers = conn.execute(
            "SELECT id, title, year FROM papers ORDER BY id"
        ).fetchall()
        citations = conn.execute(
            "SELECT source_id, target_id FROM citations ORDER BY source_id, target_id"
        ).fetchall()
    finally:
        conn.close()

    assert papers == EXPECTED_PAPERS, "The papers fixture data was modified."
    assert citations == EXPECTED_CITATIONS, "The citations fixture data was modified."


def test_database_indexes():
    """Verify that optimal indexes exist for both source_id and target_id on the citations table."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_list('citations');")
    indexes = cursor.fetchall()

    has_source_idx = False
    has_target_idx = False

    for idx in indexes:
        idx_name = idx[1]
        cursor.execute(f"PRAGMA index_info('{idx_name}');")
        cols = cursor.fetchall()
        if len(cols) > 0:
            col_name = cols[0][2]
            if col_name == 'source_id':
                has_source_idx = True
            elif col_name == 'target_id':
                has_target_idx = True

    conn.close()

    assert has_source_idx, "Missing index on 'source_id' in the 'citations' table."
    assert has_target_idx, "Missing index on 'target_id' in the 'citations' table."


def test_fixture_data_is_intact():
    """Verify that the citation fixture used by the task has not been altered."""
    assert_fixture_intact()


def test_script_exists_and_executable():
    """Verify the Bash script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_script_json_output():
    """Verify the Bash script outputs the correct JSON array."""
    assert_fixture_intact()

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    query_inner = """
    SELECT p.id, p.title, COUNT(c.source_id) as recent_in_degree
    FROM papers p
    JOIN citations c ON p.id = c.target_id
    JOIN papers sp ON c.source_id = sp.id
    WHERE sp.year >= 2018
    GROUP BY p.id
    ORDER BY recent_in_degree DESC, p.id ASC
    LIMIT 5
    """
    cursor.execute(query_inner)
    expected_inner = [dict(row) for row in cursor.fetchall()]
    conn.close()

    assert expected_inner == [
        {"id": 1, "title": "Graph Theory Basics", "recent_in_degree": 3},
        {"id": 2, "title": "Advanced Graph Analytics", "recent_in_degree": 3},
        {"id": 3, "title": "Modern AI", "recent_in_degree": 2},
        {"id": 4, "title": "Deep Learning Innovations", "recent_in_degree": 1},
    ], "Unexpected analytics result from the required fixture."

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    stdout = result.stdout.strip()
    assert stdout, "Script produced no output."

    try:
        output_json = json.loads(stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Script output is not valid JSON. Output:\n{stdout}")

    assert isinstance(output_json, list), "Output should be a JSON array."
    assert len(output_json) >= len(expected_inner), f"Expected at least {len(expected_inner)} elements, got {len(output_json)}"
    assert len(output_json) <= 5, f"Expected at most 5 elements, got {len(output_json)}"

    for i in range(len(expected_inner)):
        assert output_json[i] == expected_inner[i], (
            f"Mismatch at index {i}:\nExpected: {expected_inner[i]}\nGot: {output_json[i]}"
        )

    if len(output_json) == 5 and len(expected_inner) == 4:
        fifth_element = output_json[4]
        assert "recent_in_degree" in fifth_element, "Missing 'recent_in_degree' key in the 5th element."
        assert fifth_element["recent_in_degree"] == 0, "The 5th element should have a recent_in_degree of 0."
        assert fifth_element == {
            "id": 5,
            "title": "Future of Tech",
            "recent_in_degree": 0,
        }, "The 5th element has the wrong paper, title, fields, or ordering."

    assert_fixture_intact()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
