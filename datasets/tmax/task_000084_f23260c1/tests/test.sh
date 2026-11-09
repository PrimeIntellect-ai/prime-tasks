#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
from collections import defaultdict

def test_bottleneck_table_result():
    json_path = "/home/user/slow_queries.json"
    csv_path = "/home/user/table_locks.csv"
    result_path = "/home/user/bottleneck_table.txt"

    assert os.path.isfile(json_path), f"Missing required file: {json_path}"
    assert os.path.isfile(csv_path), f"Missing required file: {csv_path}"
    assert os.path.isfile(result_path), f"The output file {result_path} was not created."

    # Derive the expected result
    with open(json_path, 'r') as f:
        queries = json.load(f)

    slow_qids = {q['qid'] for q in queries if q.get('exec_time_ms', 0) > 1000}

    table_counts = defaultdict(int)
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['query_id'] in slow_qids:
                table_counts[row['table_name']] += 1

    assert table_counts, "No slow queries found locking any tables."

    max_count = max(table_counts.values())
    # Find all tables with max count
    top_tables = [table for table, count in table_counts.items() if count == max_count]
    # Tie-breaker: alphabetically first
    expected_table = sorted(top_tables)[0]

    with open(result_path, 'r') as f:
        actual_table = f.read().strip()

    assert actual_table == expected_table, (
        f"Expected bottleneck table to be '{expected_table}', "
        f"but found '{actual_table}' in {result_path}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
