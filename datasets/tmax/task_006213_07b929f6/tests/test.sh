#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import sqlite3
import csv
import math
import pytest
import numpy as np
from scipy.stats import ttest_ind
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

def get_expected_data():
    # 1. Clean customers
    customers = {}
    with open('/home/user/data/customers.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                cid = int(row['CustomerID'])
                if cid <= 0:
                    continue
                age = int(row['Age'])
                if not (18 <= age <= 100):
                    continue
                region = row['Region'].strip()
                if region not in ('North', 'South', 'East', 'West'):
                    continue
                customers[cid] = {'Age': age, 'Region': region, 'Total_Spend': 0.0, 'Count': 0}
            except ValueError:
                continue

    # 2. Clean transactions and aggregate
    with open('/home/user/data/transactions.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                cid = int(row['CustomerID'])
                amount = float(row['Amount'])
                if amount < 0.0:
                    continue
                if cid in customers:
                    customers[cid]['Total_Spend'] += amount
                    customers[cid]['Count'] += 1
            except ValueError:
                continue

    # Filter out customers with no valid transactions
    valid_customers = {cid: data for cid, data in customers.items() if data['Count'] > 0}

    # 3. Clean tickets
    tickets = {}
    conn = sqlite3.connect('/home/user/data/support.db')
    cursor = conn.cursor()
    cursor.execute("SELECT CustomerID, TicketCount FROM tickets")
    for cid, count in cursor.fetchall():
        try:
            cid = int(cid)
            count = int(count)
            if count >= 0:
                tickets[cid] = count
        except (ValueError, TypeError):
            continue
    conn.close()

    # 4. Final aggregation
    final_data = {}
    for cid, data in valid_customers.items():
        avg_spend = data['Total_Spend'] / data['Count']
        t_count = tickets.get(cid, 0)
        final_data[cid] = {
            'Age': data['Age'],
            'Region': data['Region'],
            'Total_Spend': data['Total_Spend'],
            'Average_Spend': avg_spend,
            'TicketCount': t_count
        }
    return final_data

def get_expected_statistics(expected_data):
    north = [d['Average_Spend'] for d in expected_data.values() if d['Region'] == 'North']
    south = [d['Average_Spend'] for d in expected_data.values() if d['Region'] == 'South']
    pvalue = float(ttest_ind(north, south, equal_var=False).pvalue)

    features = np.array(
        [[d['Age'], d['TicketCount']] for d in expected_data.values()],
        dtype=float
    )
    target = np.array([d['Total_Spend'] for d in expected_data.values()], dtype=float)
    model = Ridge(alpha=1.0)
    model.fit(features, target)
    mse = float(mean_squared_error(target, model.predict(features)))

    return round(pvalue, 4), round(mse, 4)

def test_cleaned_customers_csv():
    expected_data = get_expected_data()
    csv_path = '/home/user/cleaned_customers.csv'
    assert os.path.isfile(csv_path), f"File not found: {csv_path}"

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows, got {len(rows)}"

    seen_customer_ids = set()
    for row in rows:
        cid = int(row['CustomerID'])
        assert cid not in seen_customer_ids, f"Duplicate CustomerID {cid} in output"
        seen_customer_ids.add(cid)
        assert cid in expected_data, f"Unexpected CustomerID {cid} in output"
        exp = expected_data[cid]
        assert int(row['Age']) == exp['Age']
        assert row['Region'] == exp['Region']
        assert int(row['TicketCount']) == exp['TicketCount']
        assert math.isclose(float(row['Total_Spend']), exp['Total_Spend'], rel_tol=1e-4)
        assert math.isclose(float(row['Average_Spend']), exp['Average_Spend'], rel_tol=1e-4)

    assert seen_customer_ids == set(expected_data), "Output does not contain every expected CustomerID"

def test_report_json():
    json_path = '/home/user/report.json'
    assert os.path.isfile(json_path), f"File not found: {json_path}"

    with open(json_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not valid JSON")

    expected_data = get_expected_data()
    expected_pvalue, expected_mse = get_expected_statistics(expected_data)

    assert 'num_valid_customers' in report, "Missing 'num_valid_customers' in report"
    assert report['num_valid_customers'] == len(expected_data), "Incorrect num_valid_customers"

    assert 'north_south_ttest_pvalue' in report, "Missing 'north_south_ttest_pvalue' in report"
    assert isinstance(report['north_south_ttest_pvalue'], float), "p-value must be a float"

    assert 'ridge_mse' in report, "Missing 'ridge_mse' in report"
    assert isinstance(report['ridge_mse'], float), "MSE must be a float"

    # Retain the original sanity checks and also verify the recomputed results.
    assert 0.0 <= report['north_south_ttest_pvalue'] <= 1.0, "p-value out of bounds"
    assert report['ridge_mse'] > 0.0, "MSE should be positive"
    assert report['north_south_ttest_pvalue'] == expected_pvalue, \
        f"Incorrect Welch t-test p-value: expected {expected_pvalue}"
    assert report['ridge_mse'] == expected_mse, \
        f"Incorrect Ridge MSE: expected {expected_mse}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
