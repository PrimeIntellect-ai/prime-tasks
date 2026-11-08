#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import pytest

def test_go_file_exists():
    """Verify that the student created the Go source file."""
    go_file = '/home/user/process_results.go'
    assert os.path.isfile(go_file), f"The Go source file {go_file} does not exist."

def test_unified_results_csv_correctness():
    """Verify that the output CSV exists and contains the correct derived data."""
    output_file = '/home/user/unified_results.csv'
    assert os.path.isfile(output_file), f"The output file {output_file} does not exist."

    # 1. Read input data to compute the expected truth
    relational = {}
    with open('/home/user/data/relational.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            relational[row['cust_id']] = {
                'ltv': float(row['ltv']),
                'region': row['region']
            }

    graph = {}
    with open('/home/user/data/graph.json', 'r') as f:
        data = json.load(f)
        for item in data:
            graph[item['node_id']] = {
                'page_rank': float(item['page_rank'])
            }

    docs = {}
    with open('/home/user/data/documents.jsonl', 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            item = json.loads(line)
            docs[item['_id']] = {
                'is_active': item['metadata']['is_active'],
                'loyalty_tier': item['metadata']['loyalty_tier']
            }

    # 2. Perform the inner join and apply filtering logic
    expected_rows = []
    for cid in relational:
        if cid in graph and cid in docs:
            ltv = relational[cid]['ltv']
            pr = graph[cid]['page_rank']
            is_active = docs[cid]['is_active']

            if ltv >= 500.0 and pr >= 0.15 and is_active:
                score = ltv * pr
                expected_rows.append({
                    'Customer_ID': cid,
                    'Region': relational[cid]['region'],
                    'Loyalty_Tier': docs[cid]['loyalty_tier'],
                    'Score': score
                })

    # 3. Sort by Score descending, then Customer_ID ascending
    expected_rows.sort(key=lambda x: (-x['Score'], x['Customer_ID']))

    # 4. Read the actual output file
    actual_rows = []
    with open(output_file, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"The output file {output_file} is empty.")

        assert header == ['Customer_ID', 'Region', 'Loyalty_Tier', 'Score'], \
            f"Header in output CSV is incorrect. Got: {header}"

        for row in reader:
            if any(row):  # skip empty lines
                actual_rows.append(row)

    # 5. Compare actual vs expected
    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} data rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert len(actual) == 4, f"Row {i+1} does not have exactly 4 columns."
        assert actual[0] == expected['Customer_ID'], f"Row {i+1}: Customer_ID mismatch. Expected {expected['Customer_ID']}, got {actual[0]}."
        assert actual[1] == expected['Region'], f"Row {i+1}: Region mismatch. Expected {expected['Region']}, got {actual[1]}."
        assert actual[2] == expected['Loyalty_Tier'], f"Row {i+1}: Loyalty_Tier mismatch. Expected {expected['Loyalty_Tier']}, got {actual[2]}."

        expected_score_str = f"{expected['Score']:.2f}"
        assert actual[3] == expected_score_str, f"Row {i+1}: Score mismatch. Expected {expected_score_str}, got {actual[3]}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
