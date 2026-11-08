#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/publications.db"
SCRIPT_PATH = "/home/user/build_graph.py"
UNOPTIMIZED_PLAN_PATH = "/home/user/plan_unoptimized.txt"
OPTIMIZED_PLAN_PATH = "/home/user/plan_optimized.txt"
COAUTHORS_JSON_PATH = "/home/user/coauthors.json"

QUERY = """
SELECT a1.author_id, a2.author_id, count(*)
FROM wrote a1
JOIN wrote a2 ON a1.paper_id = a2.paper_id
WHERE a1.author_id < a2.author_id
GROUP BY a1.author_id, a2.author_id;
"""

EXPECTED_UNOPTIMIZED_PLAN = None
EXPECTED_OPTIMIZED_PLAN = None
CREATED_INDEXES = []


def format_plan(rows):
    return "\n".join(str(tuple(row)) for row in rows)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    global EXPECTED_UNOPTIMIZED_PLAN, EXPECTED_OPTIMIZED_PLAN, CREATED_INDEXES

    assert os.path.isfile(SCRIPT_PATH), f"Missing Python script {SCRIPT_PATH}"
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a regular file, not a symlink"

    conn = sqlite3.connect(DB_PATH)
    try:
        # Restore the required pre-optimization state before exercising the script.
        for row in conn.execute("PRAGMA index_list('wrote')").fetchall():
            index_name = row[1]
            origin = row[3]
            if origin == "c":
                quoted_name = index_name.replace('"', '""')
                conn.execute(f'DROP INDEX "{quoted_name}"')
        conn.commit()

        unoptimized_rows = conn.execute("EXPLAIN QUERY PLAN " + QUERY).fetchall()
        EXPECTED_UNOPTIMIZED_PLAN = format_plan(unoptimized_rows)
    finally:
        conn.close()

    for path in (UNOPTIMIZED_PLAN_PATH, OPTIMIZED_PLAN_PATH, COAUTHORS_JSON_PATH):
        if os.path.lexists(path):
            os.remove(path)

    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=60,
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        index_rows = conn.execute("PRAGMA index_list('wrote')").fetchall()
        CREATED_INDEXES = [row[1] for row in index_rows if row[3] == "c"]
        optimized_rows = conn.execute("EXPLAIN QUERY PLAN " + QUERY).fetchall()
        EXPECTED_OPTIMIZED_PLAN = format_plan(optimized_rows)
    finally:
        conn.close()


def test_files_exist():
    assert os.path.exists(UNOPTIMIZED_PLAN_PATH), f"Missing {UNOPTIMIZED_PLAN_PATH}"
    assert os.path.exists(OPTIMIZED_PLAN_PATH), f"Missing {OPTIMIZED_PLAN_PATH}"
    assert os.path.exists(COAUTHORS_JSON_PATH), f"Missing {COAUTHORS_JSON_PATH}"


def test_index_created_and_used():
    assert CREATED_INDEXES, "The script did not create an index on the wrote table"
    plan_upper = EXPECTED_OPTIMIZED_PLAN.upper()
    assert any(name.upper() in plan_upper for name in CREATED_INDEXES), \
        "The optimized query plan does not use an index created on wrote"


def test_unoptimized_plan():
    with open(UNOPTIMIZED_PLAN_PATH, "r") as f:
        raw_content = f.read()
    content = raw_content.upper()
    assert "SCAN" in content, "Unoptimized plan should contain 'SCAN' indicating a full table scan."
    assert raw_content.rstrip("\n") == EXPECTED_UNOPTIMIZED_PLAN, \
        "plan_unoptimized.txt is not the exact EXPLAIN QUERY PLAN output from before index creation"


def test_optimized_plan():
    with open(OPTIMIZED_PLAN_PATH, "r") as f:
        raw_content = f.read()
    content = raw_content.upper()
    assert "SEARCH" in content or "COVERING INDEX" in content, "Optimized plan should use an index (SEARCH or COVERING INDEX)."
    assert raw_content.rstrip("\n") == EXPECTED_OPTIMIZED_PLAN, \
        "plan_optimized.txt is not the exact EXPLAIN QUERY PLAN output for the indexed database"


def test_coauthors_json():
    with open(COAUTHORS_JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("coauthors.json is not valid JSON")

    assert isinstance(data, list), "coauthors.json must contain a JSON array"

    # Recompute the expected graph directly from the database
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    query = """
    SELECT a1.author_id, a2.author_id, count(*) 
    FROM wrote a1 
    JOIN wrote a2 ON a1.paper_id = a2.paper_id 
    WHERE a1.author_id < a2.author_id 
    GROUP BY a1.author_id, a2.author_id;
    """
    c.execute(query)
    expected_edges = c.fetchall()
    conn.close()

    expected_dict = {(row[0], row[1]): row[2] for row in expected_edges}

    actual_dict = {}
    for item in data:
        assert isinstance(item, dict), "Each item in the JSON array must be an object"
        assert "source" in item, "Missing 'source' key"
        assert "target" in item, "Missing 'target' key"
        assert "weight" in item, "Missing 'weight' key"

        src = item["source"]
        tgt = item["target"]
        w = item["weight"]
        actual_dict[(src, tgt)] = w

    assert len(actual_dict) == len(expected_dict), f"Expected {len(expected_dict)} edges, but found {len(actual_dict)}"

    for edge, weight in expected_dict.items():
        assert edge in actual_dict, f"Missing edge {edge} in JSON output"
        assert actual_dict[edge] == weight, f"Expected weight {weight} for edge {edge}, got {actual_dict[edge]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
