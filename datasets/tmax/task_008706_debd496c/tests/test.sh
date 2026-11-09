#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import sqlite3
import math
import pytest
import numpy as np


def expected_clean_rows_and_predictions():
    expected_rows = []
    with open('/home/user/raw_data.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['f1'] == '' or row['f2'] == '' or row['f3'] == '':
                continue
            expected_rows.append({
                'id': int(row['id']),
                'category': row['category'],
                'f1': float(row['f1']),
                'f2': float(row['f2']),
                'f3': float(row['f3'])
            })

    with open('/home/user/weights.json', 'r') as f:
        w = json.load(f)

    W1 = w['W1']
    b1 = w['b1']
    W2 = w['W2']
    b2 = w['b2']

    for row in expected_rows:
        x = [row['f1'], row['f2'], row['f3']]
        hidden = []
        for j in range(len(b1)):
            val = sum(x[i] * W1[i][j] for i in range(3)) + b1[j]
            hidden.append(max(0.0, val))

        row['prediction'] = (
            sum(hidden[j] * W2[j][0] for j in range(len(hidden))) + b2[0]
        )

    return expected_rows


def test_database_and_predictions():
    db_path = '/home/user/sensor_data.db'
    assert os.path.exists(db_path), f"Database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("PRAGMA table_info(readings)")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}

    assert 'id' in columns, "Column 'id' missing in readings table."
    assert 'category' in columns, "Column 'category' missing in readings table."
    assert 'f1' in columns, "Column 'f1' missing in readings table."
    assert 'f2' in columns, "Column 'f2' missing in readings table."
    assert 'f3' in columns, "Column 'f3' missing in readings table."
    assert 'prediction' in columns, "Column 'prediction' missing in readings table."

    expected_rows = expected_clean_rows_and_predictions()

    cursor.execute("SELECT id, category, f1, f2, f3, prediction FROM readings ORDER BY id")
    db_rows = cursor.fetchall()

    assert len(db_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows in DB, got {len(db_rows)}"
    )

    for db_row, exp_row in zip(db_rows, expected_rows):
        assert db_row[0] == exp_row['id']
        assert db_row[1] == exp_row['category']
        assert math.isclose(db_row[2], exp_row['f1'], rel_tol=1e-5)

        pred = exp_row['prediction']
        assert math.isclose(db_row[5], pred, rel_tol=1e-4), (
            f"Prediction for id {db_row[0]} is incorrect. Expected {pred}, got {db_row[5]}"
        )

    conn.close()


def test_summary_json():
    summary_path = '/home/user/summary.json'
    assert os.path.exists(summary_path), f"Summary file {summary_path} is missing."

    with open(summary_path, 'r') as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json is not valid JSON")

    assert isinstance(summary, dict), "Summary should be a dictionary"

    for cat, bounds in summary.items():
        assert isinstance(bounds, list) and len(bounds) == 2, (
            f"Bounds for {cat} should be a list of 2 elements"
        )
        assert isinstance(bounds[0], (int, float)), "Lower bound must be a number"
        assert isinstance(bounds[1], (int, float)), "Upper bound must be a number"
        assert bounds[0] <= bounds[1], (
            f"Lower bound {bounds[0]} is greater than upper bound {bounds[1]} for {cat}"
        )

    rows = expected_clean_rows_and_predictions()
    by_category = {}
    for row in rows:
        by_category.setdefault(row['category'], []).append(row['prediction'])

    expected_summary = {}
    np.random.seed(42)
    for category in sorted(by_category):
        predictions = np.asarray(by_category[category], dtype=float)
        samples = np.random.choice(
            predictions,
            size=(10000, len(predictions)),
            replace=True
        )
        sample_means = samples.mean(axis=1)
        lower, upper = np.percentile(sample_means, [2.5, 97.5])
        expected_summary[category] = [round(float(lower), 4), round(float(upper), 4)]

    assert set(summary.keys()) == set(expected_summary.keys()), (
        f"Expected categories {sorted(expected_summary)}, got {sorted(summary)}"
    )
    for category, expected_bounds in expected_summary.items():
        assert summary[category] == expected_bounds, (
            f"Incorrect bootstrap interval for {category}: "
            f"expected {expected_bounds}, got {summary[category]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
