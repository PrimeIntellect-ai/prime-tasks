#!/bin/bash
mkdir -p /logs/verifier

if [ ! -d /home/user/venv ] || [ ! -f /home/user/venv/bin/python ]; then
    echo '0' > /logs/verifier/reward.txt
    exit 0
fi

if /home/user/venv/bin/python - <<'TEST_EOF'
import csv
import json
import math
import os
import pickle
import subprocess

import pandas as pd
from pandas.testing import assert_frame_equal
from scipy.stats import ttest_ind

venv_path = '/home/user/venv'
python_bin = os.path.join(venv_path, 'bin', 'python')
assert os.path.isdir(venv_path), f'Virtual environment directory {venv_path} is missing.'
assert os.path.isfile(python_bin), f'Python executable not found in {venv_path}/bin/.'

etl_path = '/home/user/etl.py'
assert os.path.isfile(etl_path), f'ETL script {etl_path} is missing.'
subprocess.run([python_bin, etl_path], cwd='/home/user', check=True)

path = '/home/user/processed_data.csv'
assert os.path.isfile(path), f'Processed data file {path} is missing.'

with open(path, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
    fieldnames = reader.fieldnames

assert len(rows) == 10, f'Expected 10 rows in processed_data.csv, found {len(rows)}.'
expected_columns = {'tx_id', 'user_id', 'amount', 'test_group', 'age_score'}
assert set(fieldnames) == expected_columns, f'Columns in processed_data.csv do not match expected. Found: {fieldnames}'
assert fieldnames == ['tx_id', 'user_id', 'amount', 'test_group', 'age_score'], f'Columns are in the wrong order: {fieldnames}'

original_meta = '/home/user/user_metadata.csv'
with open(original_meta, 'r', encoding='utf-8') as f:
    meta_reader = csv.DictReader(f)
    age_scores = [int(r['age_score']) for r in meta_reader if r['age_score'].strip()]
age_scores.sort()
n = len(age_scores)
if n % 2 == 1:
    median = age_scores[n // 2]
else:
    median = (age_scores[n // 2 - 1] + age_scores[n // 2]) / 2.0
median = int(median)
assert median == 33, f'Expected source-data median to be 33, got {median}.'

for row in rows:
    age_str = row['age_score']
    assert '.' not in age_str, f'age_score {age_str} is not an integer string.'
    age_val = int(age_str)
    if row['user_id'] in ['103', '107', '109']:
        assert age_val == median, f'User {row["user_id"]} should have imputed age_score {median}, but got {age_val}.'

tx = pd.read_csv('/home/user/transactions.csv')
meta = pd.read_csv('/home/user/user_metadata.csv')
expected = tx.merge(meta, on='user_id', how='left', sort=False)
available_median = expected['age_score'].dropna().median()
assert math.isfinite(float(available_median)), 'No valid age_score values were available for imputation.'
assert float(available_median).is_integer(), 'The median cannot be represented as the required integer age_score.'
expected['age_score'] = expected['age_score'].fillna(available_median).astype('int64')
expected = expected[['tx_id', 'user_id', 'amount', 'test_group', 'age_score']]
actual = pd.read_csv(path)
assert_frame_equal(actual, expected, check_dtype=True, check_exact=True)

results_path = '/home/user/results.json'
assert os.path.isfile(results_path), f'Results file {results_path} is missing.'
with open(results_path, 'r', encoding='utf-8') as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{results_path} does not contain valid JSON.') from exc

expected_keys = {'imputed_median', 'num_anomalies', 't_statistic', 'p_value'}
assert set(data.keys()) == expected_keys, f'JSON keys do not match expected. Found: {list(data.keys())}'
assert isinstance(data['imputed_median'], int), 'imputed_median must be an integer.'
assert not isinstance(data['imputed_median'], bool), 'imputed_median must be an integer.'
assert data['imputed_median'] == 33, f'Expected imputed_median to be 33, got {data["imputed_median"]}.'
assert isinstance(data['num_anomalies'], int), 'num_anomalies must be an integer.'
assert not isinstance(data['num_anomalies'], bool), 'num_anomalies must be an integer.'
assert isinstance(data['t_statistic'], (int, float)), 't_statistic must be a number.'
assert not isinstance(data['t_statistic'], bool), 't_statistic must be a number.'
assert isinstance(data['p_value'], (int, float)), 'p_value must be a number.'
assert not isinstance(data['p_value'], bool), 'p_value must be a number.'
assert math.isfinite(float(data['t_statistic'])), 't_statistic must be finite.'
assert math.isfinite(float(data['p_value'])), 'p_value must be finite.'

t_stat_str = str(data['t_statistic'])
p_val_str = str(data['p_value'])
if '.' in t_stat_str:
    assert len(t_stat_str.split('.')[1]) <= 4, 't_statistic should be rounded to 4 decimal places.'
if '.' in p_val_str:
    assert len(p_val_str.split('.')[1]) <= 4, 'p_value should be rounded to 4 decimal places.'

with open('/home/user/anomaly_model.pkl', 'rb') as f:
    model = pickle.load(f)
features = actual[['amount', 'age_score']]
predictions = model.predict(features)
scores = model.decision_function(features)
expected_num_anomalies = int((predictions == -1).sum())
score_a = scores[actual['test_group'].to_numpy() == 'A']
score_b = scores[actual['test_group'].to_numpy() == 'B']
expected_t, expected_p = ttest_ind(score_a, score_b, equal_var=True)
expected_t = round(float(expected_t), 4)
expected_p = round(float(expected_p), 4)

assert data['num_anomalies'] == expected_num_anomalies, f'Expected num_anomalies {expected_num_anomalies}, got {data["num_anomalies"]}.'
assert math.isclose(float(data['t_statistic']), expected_t, rel_tol=0.0, abs_tol=1e-12), f'Expected t_statistic {expected_t}, got {data["t_statistic"]}.'
assert math.isclose(float(data['p_value']), expected_p, rel_tol=0.0, abs_tol=1e-12), f'Expected p_value {expected_p}, got {data["p_value"]}.'
TEST_EOF
then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
