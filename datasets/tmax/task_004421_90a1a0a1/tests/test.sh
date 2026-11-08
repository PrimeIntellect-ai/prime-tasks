#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

EVALUATE = '/home/user/evaluate.py'
RUNNER = '/home/user/run_experiments.sh'
LOG = '/home/user/experiment_log.csv'
DATASETS = '/home/user/datasets'


def reference_result(path):
    df = pd.read_csv(path)
    features = ['feature1', 'feature2', 'feature3']
    for column in features:
        df[column] = df[column].fillna(df[column].median())

    lower = df['target'].quantile(0.01)
    upper = df['target'].quantile(0.99)
    df = df[(df['target'] > lower) & (df['target'] < upper)]

    search = GridSearchCV(
        Ridge(),
        {'alpha': [0.1, 1.0, 10.0]},
        cv=3,
        scoring='neg_mean_absolute_error',
    )
    search.fit(df[features], df['target'])
    return float(search.best_params_['alpha']), round(float(-search.best_score_), 3)


def make_probe(path, n=93):
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'big'))
    f1 = rng.normal(2.0, 4.0, n)
    f2 = rng.normal(-1.0, 8.0, n)
    f3 = rng.normal(0.5, 2.5, n)
    target = 2.7 * f1 - 0.8 * f2 + 1.3 * f3 + rng.normal(0, 3.0, n)
    target[0] -= 900
    target[1] += 1100
    df = pd.DataFrame({
        'feature1': f1,
        'feature2': f2,
        'feature3': f3,
        'target': target,
    })
    for offset, column in enumerate(['feature1', 'feature2', 'feature3']):
        indices = np.arange(4 + offset, n, 11 + offset)
        df.loc[indices, column] = np.nan
    df.to_csv(path, index=False)


def parse_evaluate_output(stdout):
    text = stdout.strip()
    assert re.fullmatch(r'(?:0\.1|1(?:\.0)?|10(?:\.0)?),[0-9]+\.[0-9]{3}', text), \
        f'Unexpected evaluate.py output: {stdout!r}'
    alpha, mae = text.split(',')
    return float(alpha), float(mae)


def test_evaluate_script_exists():
    """Check if the Python evaluation script exists."""
    assert os.path.isfile(EVALUATE), "/home/user/evaluate.py is missing"


def test_bash_script_exists():
    """Check if the Bash orchestration script exists."""
    assert os.path.isfile(RUNNER), "/home/user/run_experiments.sh is missing"


def test_log_file_exists():
    """Check if the experiment log file exists."""
    assert os.path.isfile(LOG), "/home/user/experiment_log.csv is missing"


def test_log_file_contents():
    """Check if the experiment log file has the correct contents."""
    assert os.path.isfile(LOG), f"{LOG} does not exist."

    expected_data = {
        'data_A.csv': ('10.0', '0.835'),
        'data_B.csv': ('10.0', '3.951'),
        'data_C.csv': ('10.0', '7.994')
    }

    with open(LOG, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['dataset', 'best_alpha', 'best_mae'], f"Incorrect header in {LOG}: {header}"

        rows = list(reader)
        assert len(rows) == 3, f"Expected 3 data rows in {LOG}, got {len(rows)}"

        for row in rows:
            assert len(row) == 3, f"Malformed row in {LOG}: {row}"
            dataset, best_alpha, best_mae = row
            assert dataset in expected_data, f"Unexpected dataset {dataset} in {LOG}"
            exp_alpha, exp_mae = expected_data[dataset]
            try:
                alpha_val = float(best_alpha)
                mae_val = float(best_mae)
                exp_alpha_val = float(exp_alpha)
                exp_mae_val = float(exp_mae)
            except ValueError:
                pytest.fail(f"Non-numeric value found in row: {row}")
            assert abs(alpha_val - exp_alpha_val) < 1e-3, f"Incorrect best_alpha for {dataset}: expected {exp_alpha}, got {best_alpha}"
            assert abs(mae_val - exp_mae_val) < 1e-2, f"Incorrect best_mae for {dataset}: expected {exp_mae}, got {best_mae}"


def test_evaluate_behavior_on_unseen_data(tmp_path):
    for index, size in enumerate((87, 104)):
        path = tmp_path / f'unseen_{index}_{secrets.token_hex(4)}.csv'
        make_probe(path, size)
        expected_alpha, expected_mae = reference_result(path)
        completed = subprocess.run(
            ['python3', EVALUATE, str(path)],
            cwd='/home/user',
            text=True,
            capture_output=True,
            timeout=60,
        )
        assert completed.returncode == 0, completed.stderr
        actual_alpha, actual_mae = parse_evaluate_output(completed.stdout)
        assert actual_alpha == expected_alpha
        assert actual_mae == pytest.approx(expected_mae, abs=0.0001)


def test_runner_executes_all_datasets_in_order_and_overwrites_log():
    probe_name = f'probe_{secrets.token_hex(6)}.csv'
    probe_path = os.path.join(DATASETS, probe_name)
    old_log = None
    if os.path.exists(LOG):
        with open(LOG, 'rb') as f:
            old_log = f.read()

    try:
        make_probe(probe_path, 96)
        csv_paths = sorted(
            os.path.join(DATASETS, name)
            for name in os.listdir(DATASETS)
            if name.endswith('.csv')
        )
        expected = {
            os.path.basename(path): reference_result(path)
            for path in csv_paths
        }

        with open(LOG, 'w', newline='') as f:
            f.write('stale,data,that must be overwritten\n')

        completed = subprocess.run(
            ['/bin/bash', RUNNER],
            cwd='/home/user',
            text=True,
            capture_output=True,
            timeout=180,
        )
        assert completed.returncode == 0, completed.stderr

        with open(LOG, 'r', newline='') as f:
            rows = list(csv.reader(f))

        assert rows[0] == ['dataset', 'best_alpha', 'best_mae']
        assert len(rows) == len(csv_paths) + 1
        assert [row[0] for row in rows[1:]] == [os.path.basename(path) for path in csv_paths]
        for row in rows[1:]:
            assert len(row) == 3, f'Malformed row: {row}'
            name, alpha_text, mae_text = row
            assert re.fullmatch(r'[0-9]+(?:\.[0-9]+)?', alpha_text)
            assert re.fullmatch(r'[0-9]+\.[0-9]{3}', mae_text)
            expected_alpha, expected_mae = expected[name]
            assert float(alpha_text) == expected_alpha
            assert float(mae_text) == pytest.approx(expected_mae, abs=0.0001)
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)
        if old_log is None:
            if os.path.exists(LOG):
                os.remove(LOG)
        else:
            with open(LOG, 'wb') as f:
                f.write(old_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
