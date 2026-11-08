#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re
import pytest
import numpy as np
import pandas as pd

PROCESSED_CSV = "/home/user/processed_cars.csv"
METRICS_TXT = "/home/user/metrics.txt"
RAW_CSV = "/home/user/raw_cars.csv"

def pristine_raw_data():
    np.random.seed(10)

    n_std = 150
    std_data = {
        'make': ['Standard'] * n_std,
        'year': np.random.randint(2010, 2024, n_std),
        'mileage': np.random.randint(20000, 150000, n_std),
        'price': np.random.randint(5000, 25000, n_std)
    }

    n_lux = 15
    lux_data = {
        'make': ['Luxury'] * n_lux,
        'year': np.random.randint(2015, 2024, n_lux),
        'mileage': np.random.randint(10000, 80000, n_lux),
        'price': np.random.randint(30000, 80000, n_lux)
    }

    return pd.concat([
        pd.DataFrame(std_data),
        pd.DataFrame(lux_data)
    ]).sample(frac=1, random_state=1).reset_index(drop=True)

def expected_processed_data():
    raw = pristine_raw_data()
    engineered = raw.copy()
    engineered['vehicle_age'] = 2024 - engineered['year'] + 1
    engineered['mileage_per_year'] = engineered['mileage'] / engineered['vehicle_age']
    engineered = engineered[['make', 'vehicle_age', 'mileage_per_year', 'price']]

    standard = engineered[engineered['make'] == 'Standard']
    luxury = engineered[engineered['make'] == 'Luxury']
    luxury_bootstrap = luxury.sample(
        n=len(standard), replace=True, random_state=42
    )
    return pd.concat([standard, luxury_bootstrap]).reset_index(drop=True)

def test_processed_cars_exists():
    assert os.path.exists(PROCESSED_CSV), f"Missing output file: {PROCESSED_CSV}"
    assert os.path.isfile(PROCESSED_CSV), f"Path is not a file: {PROCESSED_CSV}"

def test_metrics_txt_exists():
    assert os.path.exists(METRICS_TXT), f"Missing output file: {METRICS_TXT}"
    assert os.path.isfile(METRICS_TXT), f"Path is not a file: {METRICS_TXT}"

def test_processed_cars_structure():
    with open(PROCESSED_CSV, mode='r', encoding='utf-8') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers is not None, "processed_cars.csv is empty."

        expected_columns = ['make', 'vehicle_age', 'mileage_per_year', 'price']
        assert headers == expected_columns, f"Columns in processed_cars.csv do not match expected. Got {headers}, expected {expected_columns}"

        rows = list(reader)

    assert len(rows) == 300, f"Expected exactly 300 rows in processed_cars.csv, got {len(rows)}"

    make_idx = headers.index('make')
    standard_count = sum(1 for r in rows if r[make_idx] == 'Standard')
    luxury_count = sum(1 for r in rows if r[make_idx] == 'Luxury')

    assert standard_count == 150, f"Expected 150 'Standard' cars, got {standard_count}"
    assert luxury_count == 150, f"Expected 150 'Luxury' cars, got {luxury_count}"

def test_raw_input_is_original_and_processed_rows_are_correct():
    actual_raw = pd.read_csv(RAW_CSV)
    pd.testing.assert_frame_equal(
        actual_raw.reset_index(drop=True),
        pristine_raw_data(),
        check_dtype=True,
        obj="raw_cars.csv"
    )

    actual = pd.read_csv(PROCESSED_CSV)
    expected = expected_processed_data()
    pd.testing.assert_frame_equal(
        actual.reset_index(drop=True),
        expected,
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
        obj="processed_cars.csv"
    )

def test_metrics_value():
    with open(PROCESSED_CSV, mode='r', encoding='utf-8') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        price_idx = headers.index('price')
        prices = []
        for row in reader:
            prices.append(float(row[price_idx]))

    expected_mean = round(sum(prices) / len(prices), 2)

    with open(METRICS_TXT, mode='r', encoding='utf-8') as f:
        content = f.read().strip()

    assert content != "", "metrics.txt is empty"
    assert re.fullmatch(r'-?\d+\.\d{2}', content), "metrics.txt must contain one numeric value with exactly 2 decimal places"

    try:
        written_mean = float(content)
    except ValueError:
        pytest.fail(f"Could not parse a numeric value from metrics.txt. Content: '{content}'")

    assert written_mean == expected_mean, f"Expected mean price {expected_mean} based on processed_cars.csv, but metrics.txt contains {written_mean}"
    assert written_mean == 34559.81, f"Expected metrics.txt to contain exactly 34559.81 based on the random seed, got {written_mean}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
