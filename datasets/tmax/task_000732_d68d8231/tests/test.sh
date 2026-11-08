#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import sqlite3
import pytest
from collections import defaultdict, deque

DB_PATH = "/home/user/graph_data.db"
CSV_PATH = "/home/user/ownership_report.csv"

def compute_expected_results():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Fetch nodes
    cursor.execute("SELECT id, node_type, group_name, asset_value FROM nodes;")
    nodes = {}
    users = []
    for row in cursor.fetchall():
        node_id, node_type, group_name, asset_value = row
        nodes[node_id] = {
            'type': node_type,
            'group': group_name,
            'value': asset_value
        }
        if node_type == 'User':
            users.append(node_id)

    # Fetch OWNS edges
    cursor.execute("SELECT source_id, target_id FROM edges WHERE relation_type = 'OWNS';")
    graph = defaultdict(list)
    for src, tgt in cursor.fetchall():
        graph[src].append(tgt)

    conn.close()

    # Calculate total asset value for each user
    user_totals = []
    for user_id in users:
        visited = set()
        queue = deque([user_id])
        total_value = 0.0

        while queue:
            curr = queue.popleft()
            if curr not in visited:
                visited.add(curr)
                if nodes[curr]['type'] == 'Asset':
                    total_value += nodes[curr]['value']
                for neighbor in graph[curr]:
                    if neighbor not in visited:
                        queue.append(neighbor)

        if total_value > 0:
            user_totals.append({
                'user_id': user_id,
                'group_name': nodes[user_id]['group'],
                'total_asset_value': total_value
            })

    # Rank within groups
    groups = defaultdict(list)
    for ut in user_totals:
        groups[ut['group_name']].append(ut)

    expected_rows = []
    for group_name, members in groups.items():
        # Sort by total_asset_value descending, then user_id ascending for stable ranking
        members.sort(key=lambda x: (-x['total_asset_value'], x['user_id']))

        rank = 1
        for i, member in enumerate(members):
            # Standard dense or row_number ranking? The problem says "Highest total value in a group gets rank 1"
            # Assuming row_number or rank. If values are distinct, it's the same.
            if i > 0 and members[i]['total_asset_value'] < members[i-1]['total_asset_value']:
                rank = i + 1
            elif i > 0 and members[i]['total_asset_value'] == members[i-1]['total_asset_value']:
                pass # ties get same rank in standard rank, but let's just use rank = i + 1 if we assume strict row_number
                # Actually, standard SQL RANK() gives same rank for ties.

            expected_rows.append({
                'user_id': member['user_id'],
                'group_name': member['group_name'],
                'total_asset_value': member['total_asset_value'],
                'group_rank': rank
            })

    # Sort primarily by group_name asc, secondarily by group_rank asc
    expected_rows.sort(key=lambda x: (x['group_name'], x['group_rank']))
    return expected_rows

def test_csv_exists():
    assert os.path.exists(CSV_PATH), f"Expected output file not found at {CSV_PATH}"
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file"

def test_csv_content():
    expected = compute_expected_results()

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty")

        expected_headers = ['user_id', 'group_name', 'total_asset_value', 'group_rank']
        assert headers == expected_headers, f"CSV headers {headers} do not match expected {expected_headers}"

        rows = list(reader)
        assert len(rows) == len(expected), f"Expected {len(expected)} rows, found {len(rows)}"

        for i, (actual_row, expected_row) in enumerate(zip(rows, expected)):
            try:
                actual_user_id = int(actual_row[0])
                actual_group_name = actual_row[1]
                actual_total_val = float(actual_row[2])
                actual_rank = int(actual_row[3])
            except ValueError as e:
                pytest.fail(f"Row {i+1} has invalid data types: {actual_row} - {e}")

            assert actual_user_id == expected_row['user_id'], f"Row {i+1}: expected user_id {expected_row['user_id']}, got {actual_user_id}"
            assert actual_group_name == expected_row['group_name'], f"Row {i+1}: expected group_name {expected_row['group_name']}, got {actual_group_name}"
            assert actual_total_val == expected_row['total_asset_value'], f"Row {i+1}: expected total_asset_value {expected_row['total_asset_value']}, got {actual_total_val}"
            assert actual_rank == expected_row['group_rank'], f"Row {i+1}: expected group_rank {expected_row['group_rank']}, got {actual_rank}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
