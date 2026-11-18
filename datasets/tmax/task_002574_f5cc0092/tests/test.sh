#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pandas as pd
import numpy as np
import pytest

def test_employee_risk_scores_mae():
    csv_path = '/home/user/employee_risk_scores.csv'
    db_path = '/app/company_data.db'

    assert os.path.exists(csv_path), f"Output file {csv_path} does not exist."
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    # 1. Re-derive the ground truth
    conn = sqlite3.connect(db_path)

    employees_df = pd.read_sql_query("SELECT EmpID, ClearanceLevel FROM employees", conn)
    rooms_df = pd.read_sql_query("SELECT RoomID, RequiredClearance FROM rooms", conn)
    conn.close()

    emp_clearance = dict(zip(employees_df['EmpID'], employees_df['ClearanceLevel']))
    room_clearance = dict(zip(rooms_df['RoomID'], rooms_df['RequiredClearance']))

    # Known access logs from the video generation
    access_logs = [
        ("E001", "R101"), ("E001", "R201"), ("E001", "R301"),
        ("E002", "R101"), ("E002", "R102"),
        ("E003", "R301"), ("E003", "R201"), ("E003", "R101"),
        ("E004", "R101"),
        ("E005", "R401"), ("E005", "R101")
    ]

    expected_scores = {emp_id: 0.0 for emp_id in emp_clearance.keys()}

    # Calculate scores
    # Unique rooms accessed by each employee
    emp_accessed_rooms = {}
    for emp_id, room_id in access_logs:
        if emp_id not in emp_accessed_rooms:
            emp_accessed_rooms[emp_id] = set()
        emp_accessed_rooms[emp_id].add(room_id)

    for emp_id, rooms in emp_accessed_rooms.items():
        e_clearance = emp_clearance.get(emp_id, 0)
        for room_id in rooms:
            r_clearance = room_clearance.get(room_id, 0)
            if e_clearance < r_clearance:
                expected_scores[emp_id] += 1.0
            else:
                expected_scores[emp_id] += 0.5

    expected_df = pd.DataFrame(list(expected_scores.items()), columns=['EmpID', 'RiskScore_true'])

    # 2. Load agent's predictions
    try:
        pred_df = pd.read_csv(csv_path)
    except Exception as e:
        pytest.fail(f"Could not read {csv_path} as a CSV: {e}")

    assert 'EmpID' in pred_df.columns and 'RiskScore' in pred_df.columns, \
        f"CSV must contain 'EmpID' and 'RiskScore' columns. Found: {pred_df.columns.tolist()}"

    # 3. Compute MAE
    merged_df = pd.merge(expected_df, pred_df, on='EmpID', how='inner')

    assert len(merged_df) == len(expected_df), \
        f"Expected {len(expected_df)} employees in the output, but found {len(merged_df)} matching EmpIDs."

    mae = np.mean(np.abs(merged_df['RiskScore_true'] - merged_df['RiskScore']))

    threshold = 0.15
    assert mae <= threshold, \
        f"Mean Absolute Error (MAE) is {mae:.4f}, which exceeds the threshold of {threshold}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
