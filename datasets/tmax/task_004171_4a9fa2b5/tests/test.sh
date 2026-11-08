#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import subprocess
from pathlib import Path

import pandas as pd
from pandas.testing import assert_frame_equal
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

TRAIN_CSV = '/home/user/train_clean.csv'
TEST_CSV = '/home/user/test_clean.csv'
SCRIPT = '/home/user/prepare_data.py'
USERS_CSV = '/home/user/users.csv'
INTERACTIONS_CSV = '/home/user/interactions.csv'


def read_csv(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def expected_outputs(users, interactions):
    merged = pd.merge(interactions, users, on='user_id')
    train, test = train_test_split(merged, test_size=0.2, random_state=42)
    scaler = StandardScaler()
    train = train.copy()
    test = test.copy()
    train[['age', 'income']] = scaler.fit_transform(train[['age', 'income']])
    test[['age', 'income']] = scaler.transform(test[['age', 'income']])
    train[['age', 'income']] = train[['age', 'income']].round(4)
    test[['age', 'income']] = test[['age', 'income']].round(4)
    return train.reset_index(drop=True), test.reset_index(drop=True)


def assert_matches_expected(expected_train, expected_test):
    assert os.path.isfile(TRAIN_CSV), f'Expected output file not found: {TRAIN_CSV}'
    assert os.path.isfile(TEST_CSV), f'Expected output file not found: {TEST_CSV}'
    actual_train = pd.read_csv(TRAIN_CSV)
    actual_test = pd.read_csv(TEST_CSV)
    assert list(actual_train.columns) == list(expected_train.columns)
    assert list(actual_test.columns) == list(expected_test.columns)
    assert_frame_equal(actual_train, expected_train, check_dtype=False, rtol=0, atol=1e-9)
    assert_frame_equal(actual_test, expected_test, check_dtype=False, rtol=0, atol=1e-9)


def test_output_files_exist():
    assert os.path.exists(TRAIN_CSV), f'Expected output file not found: {TRAIN_CSV}'
    assert os.path.exists(TEST_CSV), f'Expected output file not found: {TEST_CSV}'


def test_row_counts():
    train_data = read_csv(TRAIN_CSV)
    test_data = read_csv(TEST_CSV)
    assert len(train_data) == 8, f'Expected 8 rows in train_clean.csv, found {len(train_data)}'
    assert len(test_data) == 3, f'Expected 3 rows in test_clean.csv, found {len(test_data)}'


def test_rounding_to_4_decimal_places():
    for filepath in [TRAIN_CSV, TEST_CSV]:
        data = read_csv(filepath)
        for i, row in enumerate(data):
            for col in ['age', 'income']:
                val_str = row[col]
                if '.' in val_str:
                    decimals = len(val_str.split('.')[1])
                    assert decimals <= 4, f"Value '{val_str}' in {col} (row {i}) is not rounded to 4 decimal places in {filepath}"


def test_train_mean_is_zero():
    train_data = read_csv(TRAIN_CSV)
    age_mean = sum(float(row['age']) for row in train_data) / len(train_data)
    income_mean = sum(float(row['income']) for row in train_data) / len(train_data)
    assert math.isclose(age_mean, 0.0, abs_tol=1e-3), f"Mean of 'age' in train set is {age_mean}, expected ~0.0. Scaler was likely not fit correctly."
    assert math.isclose(income_mean, 0.0, abs_tol=1e-3), f"Mean of 'income' in train set is {income_mean}, expected ~0.0. Scaler was likely not fit correctly."


def test_test_mean_is_not_zero():
    test_data = read_csv(TEST_CSV)
    age_mean = sum(float(row['age']) for row in test_data) / len(test_data)
    assert not math.isclose(age_mean, 0.0, abs_tol=1e-3), f"Mean of 'age' in test set is {age_mean}, which is too close to 0.0. Scaler might have been fit on the test set (data leakage)."


def test_outputs_exactly_match_inputs_and_train_only_scaling():
    users = pd.read_csv(USERS_CSV)
    interactions = pd.read_csv(INTERACTIONS_CSV)
    expected_train, expected_test = expected_outputs(users, interactions)
    assert_matches_expected(expected_train, expected_test)


def test_script_generalizes_to_unseen_input():
    users_path = Path(USERS_CSV)
    interactions_path = Path(INTERACTIONS_CSV)
    original_users = users_path.read_bytes()
    original_interactions = interactions_path.read_bytes()
    offset = secrets.randbelow(100000) + 1000

    users = pd.DataFrame({
        'user_id': [offset + i for i in range(1, 15)],
        'age': [19, 27, 36, 44, 53, 31, 62, 24, 48, 39, 57, 22, 46, 34],
        'income': [31001, 48777, 62345, 81819, 97531, 55443, 120007, 40221, 88991, 69777, 105113, 36119, 93227, 58661],
    })
    interactions = pd.DataFrame({
        'user_id': [offset + i for i in [1, 1, 2, 3, 3, 4, 5, 6, 7, 7, 8, 9, 10, 10, 11, 12, 13, 14, 14]],
        'item_id': [701, 702, 703, 701, 704, 705, 706, 702, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717],
        'rating': [2, 5, 3, 4, 1, 5, 2, 4, 5, 3, 1, 4, 2, 5, 3, 4, 1, 5, 2],
    })

    try:
        users.to_csv(USERS_CSV, index=False)
        interactions.to_csv(INTERACTIONS_CSV, index=False)
        expected_train, expected_test = expected_outputs(users, interactions)
        Path(TRAIN_CSV).unlink(missing_ok=True)
        Path(TEST_CSV).unlink(missing_ok=True)
        subprocess.run(['python3', SCRIPT], check=True, timeout=30)
        assert_matches_expected(expected_train, expected_test)
    finally:
        users_path.write_bytes(original_users)
        interactions_path.write_bytes(original_interactions)
        Path(TRAIN_CSV).unlink(missing_ok=True)
        Path(TEST_CSV).unlink(missing_ok=True)
        subprocess.run(['python3', SCRIPT], check=True, timeout=30)
TEST_EOF

if [ -f /home/user/prepare_data.py ] && [ ! -L /home/user/prepare_data.py ]; then
    rm -f /home/user/train_clean.csv /home/user/test_clean.csv
    timeout 30s python3 /home/user/prepare_data.py
    run_status=$?
else
    run_status=1
fi

if [ "$run_status" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
