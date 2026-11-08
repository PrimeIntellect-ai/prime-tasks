#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

JSON_PATH = '/home/user/pipeline_plan.json'
DB_PATH = '/home/user/etl_metadata.db'

def test_pipeline_plan_json_exists():
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} is missing."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."

def test_pipeline_plan_json_content():
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} is missing."

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be a list of objects."

    # We dynamically calculate the expected result from the DB to be robust against data changes
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    query = """
    WITH RECURSIVE
    paths(id, name, total_cost) AS (
        SELECT id, name, base_cost
        FROM jobs
        WHERE name = 'extract_sales_data'

        UNION ALL

        SELECT j.id, j.name, p.total_cost + j.base_cost
        FROM paths p
        JOIN dependencies d ON p.id = d.parent_id
        JOIN jobs j ON d.child_id = j.id
    ),
    leaves AS (
        SELECT id, name
        FROM jobs
        WHERE id NOT IN (SELECT parent_id FROM dependencies)
    )
    SELECT l.name, MAX(p.total_cost) AS max_cost
    FROM paths p
    JOIN leaves l ON p.id = l.id
    GROUP BY l.name
    ORDER BY max_cost DESC;
    """

    c.execute(query)
    expected_results = c.fetchall()
    conn.close()

    expected_json = [
        {"leaf_job": row[0], "total_path_cost": row[1]}
        for row in expected_results
    ]

    assert len(data) == len(expected_json), f"Expected {len(expected_json)} items in the JSON, got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_json)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert "leaf_job" in actual, f"Item at index {i} is missing 'leaf_job' key."
        assert "total_path_cost" in actual, f"Item at index {i} is missing 'total_path_cost' key."

        assert actual["leaf_job"] == expected["leaf_job"], f"Item at index {i} has incorrect leaf_job. Expected {expected['leaf_job']}, got {actual['leaf_job']}."
        assert actual["total_path_cost"] == expected["total_path_cost"], f"Item at index {i} has incorrect total_path_cost. Expected {expected['total_path_cost']}, got {actual['total_path_cost']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
