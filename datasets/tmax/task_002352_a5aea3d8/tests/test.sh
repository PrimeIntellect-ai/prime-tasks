#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import subprocess
from collections import Counter

import pyarrow as pa
import pyarrow.parquet as pq
import pytest

RAW_PATH = '/home/user/artifacts/raw_logs.csv'
PARQUET_PATH = '/home/user/artifacts/cleaned_logs.parquet'


def expected_raw_rows():
    rng = random.Random(42)
    rows = []

    for i in range(500):
        correct = i < 400
        y_true = rng.randint(0, 1)
        y_pred = y_true if correct else 1 - y_true
        rows.append({
            'req_id': f'req_A_{i}',
            'model': 'model_alpha',
            'y_pred': str(y_pred),
            'y_true': str(y_true),
        })

    for i in range(600):
        correct = i < 510
        y_true = rng.randint(0, 1)
        y_pred = y_true if correct else 1 - y_true
        rows.append({
            'req_id': f'req_B_{i}',
            'model': 'model_beta',
            'y_pred': str(y_pred),
            'y_true': str(y_true),
        })

    rows.extend([
        {'req_id': 'bad_1', 'model': 'model_alpha', 'y_pred': 'ERROR', 'y_true': '1'},
        {'req_id': 'bad_2', 'model': 'model_beta', 'y_pred': '0', 'y_true': 'NULL'},
        {'req_id': 'bad_3', 'model': '', 'y_pred': '1', 'y_true': '1'},
        {'req_id': 'bad_4', 'model': 'model_alpha', 'y_pred': '', 'y_true': '0'},
    ])
    return rows


def independently_clean_raw():
    with open(RAW_PATH, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['req_id', 'model', 'y_pred', 'y_true'], \
            'The raw CSV schema was modified.'
        raw_rows = list(reader)

    assert raw_rows == expected_raw_rows(), 'The source raw_logs.csv was modified.'

    cleaned = []
    for row in raw_rows:
        required = [row.get('req_id'), row.get('model'), row.get('y_pred'), row.get('y_true')]
        if any(value is None or value.strip() == '' for value in required):
            continue
        try:
            y_pred = int(row['y_pred'])
            y_true = int(row['y_true'])
        except (TypeError, ValueError):
            continue
        cleaned.append({
            'req_id': row['req_id'],
            'model': row['model'],
            'y_pred': y_pred,
            'y_true': y_true,
        })
    return cleaned


def read_and_validate_parquet():
    assert os.path.isfile(PARQUET_PATH), f'The file {PARQUET_PATH} does not exist.'
    try:
        table = pq.read_table(PARQUET_PATH)
    except Exception as exc:
        pytest.fail(f'{PARQUET_PATH} is not a readable Parquet file: {exc}')

    assert table.column_names == ['req_id', 'model', 'y_pred', 'y_true'], \
        'The cleaned Parquet file does not have exactly the required columns.'

    schema = table.schema
    assert pa.types.is_string(schema.field('req_id').type) or pa.types.is_large_string(schema.field('req_id').type)
    assert pa.types.is_string(schema.field('model').type) or pa.types.is_large_string(schema.field('model').type)
    assert pa.types.is_integer(schema.field('y_pred').type), 'y_pred must have an integer Parquet type.'
    assert pa.types.is_integer(schema.field('y_true').type), 'y_true must have an integer Parquet type.'

    rows = table.to_pylist()
    assert all(all(row[column] is not None for column in table.column_names) for row in rows), \
        'The cleaned Parquet file contains missing values.'

    expected = independently_clean_raw()
    key = lambda row: (row['req_id'], row['model'], row['y_pred'], row['y_true'])
    assert Counter(map(key, rows)) == Counter(map(key, expected)), \
        'The Parquet rows do not exactly match the valid rows from raw_logs.csv.'
    return rows


def test_cleaned_logs_parquet_exists():
    rows = read_and_validate_parquet()
    assert len(rows) == 1100


def test_posteriors_json():
    json_path = '/home/user/artifacts/posteriors.json'
    assert os.path.isfile(json_path), f'The file {json_path} does not exist.'

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {json_path} does not contain valid JSON.')

    expected_data = {
        'model_alpha': {'alpha': 402, 'beta': 102},
        'model_beta': {'alpha': 512, 'beta': 92}
    }
    assert data == expected_data, f'The contents of {json_path} do not match the expected posterior parameters.'

    rows = read_and_validate_parquet()
    derived = {}
    for model in ('model_alpha', 'model_beta'):
        model_rows = [row for row in rows if row['model'] == model]
        successes = sum(row['y_pred'] == row['y_true'] for row in model_rows)
        failures = len(model_rows) - successes
        derived[model] = {'alpha': 2 + successes, 'beta': 2 + failures}
    assert data == derived, 'Posterior parameters were not derived from the cleaned dataset.'


def test_bootstrap_ci_txt():
    txt_path = '/home/user/artifacts/bootstrap_ci.txt'
    assert os.path.isfile(txt_path), f'The file {txt_path} does not exist.'

    # Ensure the CI is only accepted alongside the exact cleaned source data.
    read_and_validate_parquet()

    script = """
import pandas as pd
import numpy as np

df_alpha = pd.DataFrame({'correct': [1]*400 + [0]*100, 'model': 'model_alpha'})
df_beta = pd.DataFrame({'correct': [1]*510 + [0]*90, 'model': 'model_beta'})
df_clean = pd.concat([df_alpha, df_beta]).reset_index(drop=True)

np.random.seed(123)
diffs = []
n_size = len(df_clean)

for _ in range(10000):
    idx = np.random.choice(n_size, size=n_size, replace=True)
    sample = df_clean.iloc[idx]

    acc_alpha = sample[sample['model'] == 'model_alpha']['correct'].mean()
    acc_beta = sample[sample['model'] == 'model_beta']['correct'].mean()

    if pd.isna(acc_alpha): acc_alpha = 0
    if pd.isna(acc_beta): acc_beta = 0

    diffs.append(acc_beta - acc_alpha)

lower = np.percentile(diffs, 2.5)
upper = np.percentile(diffs, 97.5)
print(f"{lower:.4f},{upper:.4f}")
"""
    try:
        result = subprocess.run(['python3', '-c', script], capture_output=True, text=True, check=True)
        expected_ci = result.stdout.strip()
    except subprocess.CalledProcessError:
        pytest.fail('Failed to compute expected bootstrap CI. Ensure numpy and pandas are installed.')

    with open(txt_path, 'r') as f:
        actual_ci = f.read().strip()

    assert actual_ci == expected_ci, \
        f"The bootstrap CI in {txt_path} ('{actual_ci}') does not match the expected value ('{expected_ci}')."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
