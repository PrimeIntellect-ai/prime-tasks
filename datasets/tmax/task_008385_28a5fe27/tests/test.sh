#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def get_expected_data():
    users_file = '/home/user/data/users.csv'
    purchases_file = '/home/user/data/purchases.csv'
    activity_file = '/home/user/data/activity.csv'

    users = {}
    with open(users_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            users[int(row['user_id'])] = row['age']

    purchases = {}
    with open(purchases_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            purchases[int(row['user_id'])] = row['purchase_amount']

    activity = {}
    with open(activity_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            activity[int(row['user_id'])] = row['login_count']

    expected_rows = []
    valid_ages = []
    valid_purchases = []

    for uid in sorted(users.keys()):
        age = users[uid]
        purchase = purchases.get(uid, "NaN")
        login = activity.get(uid, "0")

        expected_rows.append({
            'user_id': str(uid),
            'age': age,
            'purchase_amount': purchase,
            'login_count': login
        })

        if purchase != "NaN":
            valid_ages.append(float(age))
            valid_purchases.append(float(purchase))

    # Calculate Pearson correlation
    n = len(valid_ages)
    mean_x = sum(valid_ages) / n
    mean_y = sum(valid_purchases) / n

    num = sum((x - mean_x) * (y - mean_y) for x, y in zip(valid_ages, valid_purchases))
    den_x = sum((x - mean_x) ** 2 for x in valid_ages)
    den_y = sum((y - mean_y) ** 2 for y in valid_purchases)

    correlation = num / math.sqrt(den_x * den_y)
    expected_corr_str = f"{correlation:.4f}"

    return expected_rows, expected_corr_str

def test_script_exists_and_executable():
    script_path = '/home/user/process_data.sh'
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_features_csv_correct():
    features_path = '/home/user/features.csv'
    assert os.path.exists(features_path), f"Output file {features_path} does not exist."

    expected_rows, _ = get_expected_data()

    with open(features_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['user_id', 'age', 'purchase_amount', 'login_count'], \
            f"Header in {features_path} is incorrect. Got {header}"

        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} data rows in {features_path}, got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual[0] == expected['user_id'], f"Row {i+1}: expected user_id {expected['user_id']}, got {actual[0]}"
        assert actual[1] == expected['age'], f"Row {i+1}: expected age {expected['age']}, got {actual[1]}"
        assert actual[2] == expected['purchase_amount'], f"Row {i+1}: expected purchase_amount {expected['purchase_amount']}, got {actual[2]}"
        assert actual[3] == expected['login_count'], f"Row {i+1}: expected login_count {expected['login_count']}, got {actual[3]}"

def test_correlation_txt_correct():
    corr_path = '/home/user/correlation.txt'
    assert os.path.exists(corr_path), f"Output file {corr_path} does not exist."

    _, expected_corr_str = get_expected_data()

    with open(corr_path, 'r') as f:
        actual_corr_str = f.read().strip()

    assert actual_corr_str == expected_corr_str, \
        f"Correlation mismatch in {corr_path}. Expected {expected_corr_str}, got {actual_corr_str}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
