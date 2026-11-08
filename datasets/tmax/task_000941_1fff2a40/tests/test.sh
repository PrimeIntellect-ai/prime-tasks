#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import sqlite3
import json
import pytest

CSV_PATH = "/home/user/long_term_backup_report.csv"
DB_PATH = "/home/user/backup_catalog.db"

def get_expected_results():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file missing at {DB_PATH}, cannot compute expected results.")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Get all configs
    cursor.execute("SELECT job_id, settings FROM configs")
    configs = cursor.fetchall()

    long_term_roots = []
    for job_id, settings_str in configs:
        try:
            settings = json.loads(settings_str)
            if settings.get("retention_policy") == "long_term":
                long_term_roots.append(job_id)
        except json.JSONDecodeError:
            continue

    # Get all jobs
    cursor.execute("SELECT id, parent_id, size_bytes FROM jobs")
    jobs = cursor.fetchall()

    # Build a parent -> children map and id -> size map
    children_map = {}
    size_map = {}
    for j_id, p_id, size in jobs:
        size_map[j_id] = size
        if p_id is not None:
            children_map.setdefault(p_id, []).append(j_id)

    results = []
    for root_id in long_term_roots:
        if root_id not in size_map:
            continue

        root_size = size_map[root_id]

        # BFS to find all descendants
        descendants = []
        queue = children_map.get(root_id, []).copy()
        while queue:
            curr = queue.pop(0)
            descendants.append(curr)
            queue.extend(children_map.get(curr, []))

        num_incrementals = len(descendants)
        total_chain_size = root_size + sum(size_map[d] for d in descendants)
        avg_incremental_size = sum(size_map[d] for d in descendants) / num_incrementals if num_incrementals > 0 else 0.0

        results.append({
            'root_job_id': root_id,
            'total_chain_size_bytes': total_chain_size,
            'num_incrementals': num_incrementals,
            'avg_incremental_size_bytes': round(avg_incremental_size, 2)
        })

    conn.close()

    # Sort by total_chain_size_bytes DESC, root_job_id ASC
    results.sort(key=lambda x: (-x['total_chain_size_bytes'], x['root_job_id']))

    # Pagination: Page 2, size 2
    page_2 = results[2:4]
    return page_2

def test_csv_exists():
    assert os.path.exists(CSV_PATH), f"Expected CSV file is missing at {CSV_PATH}"
    assert os.path.isfile(CSV_PATH), f"Path {CSV_PATH} is not a file"

def test_csv_content():
    assert os.path.exists(CSV_PATH), f"Expected CSV file is missing at {CSV_PATH}"

    expected_data = get_expected_results()

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty"

    expected_headers = ['root_job_id', 'total_chain_size_bytes', 'num_incrementals', 'avg_incremental_size_bytes']
    assert rows[0] == expected_headers, f"CSV headers are incorrect. Expected {expected_headers}, got {rows[0]}"

    assert len(rows) == len(expected_data) + 1, f"Expected {len(expected_data)} data rows, found {len(rows) - 1}"

    for i, expected_row in enumerate(expected_data):
        actual_row = rows[i + 1]
        assert len(actual_row) == 4, f"Row {i + 1} does not have exactly 4 columns"

        assert str(expected_row['root_job_id']) == actual_row[0].strip(), f"Row {i + 1}: expected root_job_id {expected_row['root_job_id']}, got {actual_row[0]}"
        assert str(expected_row['total_chain_size_bytes']) == actual_row[1].strip(), f"Row {i + 1}: expected total_chain_size_bytes {expected_row['total_chain_size_bytes']}, got {actual_row[1]}"
        assert str(expected_row['num_incrementals']) == actual_row[2].strip(), f"Row {i + 1}: expected num_incrementals {expected_row['num_incrementals']}, got {actual_row[2]}"

        actual_avg = float(actual_row[3].strip())
        expected_avg = expected_row['avg_incremental_size_bytes']
        assert abs(actual_avg - expected_avg) < 0.01, f"Row {i + 1}: expected avg_incremental_size_bytes {expected_avg}, got {actual_avg}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
