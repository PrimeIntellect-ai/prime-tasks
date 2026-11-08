#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile

import pytest

TRAIN_SCRIPT = '/home/user/src/train.py'
METRICS_FILE = '/home/user/metrics_fixed.json'
USERS_FILE = '/home/user/data/users.csv'
TX_FILE = '/home/user/data/transactions.csv'


def run_submission(timeout=60):
    if os.path.lexists(METRICS_FILE):
        os.remove(METRICS_FILE)
    return subprocess.run(
        [sys.executable, TRAIN_SCRIPT],
        cwd='/home/user/src',
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def read_metrics():
    assert os.path.isfile(METRICS_FILE), f'The file {METRICS_FILE} was not created.'
    with open(METRICS_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {METRICS_FILE} does not contain valid JSON.')
    assert 'accuracy' in data, f"The JSON in {METRICS_FILE} is missing the 'accuracy' key."
    assert isinstance(data['accuracy'], (int, float)), 'The accuracy value must be a number.'
    return data


def get_expected_accuracy():
    """Compute the canonical result for the data currently at the required paths."""
    script = """
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression

users = pd.read_csv('/home/user/data/users.csv')
tx = pd.read_csv('/home/user/data/transactions.csv')
df = pd.merge(tx, users, on='user_id')

df = df.dropna(subset=['age'])
df = df[df['amount'] >= 0]

X = df[['amount', 'age', 'location_id']]
y = df['is_fraud']
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

scaler = StandardScaler()
X_train_scaled = X_train.copy()
X_test_scaled = X_test.copy()
X_train_scaled[['amount', 'age']] = scaler.fit_transform(X_train[['amount', 'age']])
X_test_scaled[['amount', 'age']] = scaler.transform(X_test[['amount', 'age']])

model = LogisticRegression(random_state=42)
model.fit(X_train_scaled, y_train)
print(model.score(X_test_scaled, y_test))
"""
    try:
        result = subprocess.run(
            [sys.executable, '-c', script],
            capture_output=True,
            text=True,
            check=True,
            timeout=60,
        )
        return float(result.stdout.strip())
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Failed to compute expected accuracy. Subprocess error: {e.stderr}')


def test_00_script_exists_and_is_executed():
    assert os.path.exists(TRAIN_SCRIPT), f'{TRAIN_SCRIPT} does not exist.'
    assert not os.path.islink(TRAIN_SCRIPT), f'{TRAIN_SCRIPT} must be a regular Python file.'
    mode = os.stat(TRAIN_SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{TRAIN_SCRIPT} must be a regular Python file.'

    result = run_submission()
    assert result.returncode == 0, (
        f'{TRAIN_SCRIPT} failed when executed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(METRICS_FILE), f'The file {METRICS_FILE} was not created.'


def test_metrics_file_exists_and_valid():
    """Check that the metrics file exists and contains valid JSON with the accuracy key."""
    read_metrics()


def test_correct_accuracy():
    """Check the accuracy on the original supplied data."""
    data = read_metrics()
    actual_accuracy = data.get('accuracy')
    expected_accuracy = get_expected_accuracy()
    tolerance = 1e-7
    diff = abs(actual_accuracy - expected_accuracy)
    assert diff < tolerance, (
        f'The reported accuracy ({actual_accuracy}) does not match the expected accuracy '
        f'({expected_accuracy}). Ensure schema enforcement and leakage fixes are correct.'
    )


def build_discriminating_fixture():
    """Build secret data for which train-only and whole-data scaling give different scores."""
    import numpy as np
    import pandas as pd
    from sklearn.linear_model import LogisticRegression
    from sklearn.model_selection import train_test_split
    from sklearn.preprocessing import StandardScaler

    rng = np.random.default_rng(secrets.randbits(64))

    def score(users, tx, filter_negative=True, leak=False):
        df = pd.merge(tx, users, on='user_id')
        df = df.dropna(subset=['age'])
        if filter_negative:
            df = df[df['amount'] >= 0]
        X = df[['amount', 'age', 'location_id']]
        y = df['is_fraud']
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        scaler = StandardScaler()
        X_train_scaled = X_train.copy()
        X_test_scaled = X_test.copy()
        if leak:
            scaler.fit(X[['amount', 'age']])
        else:
            scaler.fit(X_train[['amount', 'age']])
        X_train_scaled[['amount', 'age']] = scaler.transform(X_train[['amount', 'age']])
        X_test_scaled[['amount', 'age']] = scaler.transform(X_test[['amount', 'age']])
        model = LogisticRegression(random_state=42)
        model.fit(X_train_scaled, y_train)
        return model.score(X_test_scaled, y_test)

    for _ in range(1500):
        n_clean = 72
        n_negative = 18
        n_missing = 8
        total = n_clean + n_negative + n_missing

        base_amount = rng.normal(0, 1, n_clean)
        base_age = rng.normal(0, 1, n_clean)
        amount = np.maximum(0.01, 100 + 14 * base_amount)
        age = 42 + 11 * base_age

        # The deterministic split lets the test distribution contain scale-shifting
        # observations, making fitting the scaler before the split observably wrong.
        _, test_positions = train_test_split(
            np.arange(n_clean), test_size=0.2, random_state=42
        )
        amount[test_positions] = np.maximum(
            0.01, 100 + rng.uniform(35, 110) * base_amount[test_positions]
        )
        age[test_positions] += rng.normal(0, 35, len(test_positions))

        logits = 0.8 * base_amount - 0.65 * base_age + rng.normal(0, 1.15, n_clean)
        clean_y = (logits > np.median(logits)).astype(int)

        users = pd.DataFrame({
            'user_id': np.arange(1, total + 1),
            'age': np.concatenate([
                age,
                rng.normal(40, 12, n_negative),
                np.full(n_missing, np.nan),
            ]),
            'location_id': rng.integers(1, 8, total),
        })
        tx = pd.DataFrame({
            'user_id': np.arange(1, total + 1),
            'amount': np.concatenate([
                amount,
                -rng.uniform(1, 250, n_negative),
                rng.uniform(20, 180, n_missing),
            ]),
            'is_fraud': np.concatenate([
                clean_y,
                rng.integers(0, 2, n_negative),
                rng.integers(0, 2, n_missing),
            ]),
        })
        tx = tx.iloc[rng.permutation(total)].reset_index(drop=True)

        try:
            expected = score(users, tx, filter_negative=True, leak=False)
            leaked = score(users, tx, filter_negative=True, leak=True)
            keeps_negative = score(users, tx, filter_negative=False, leak=False)
        except ValueError:
            continue

        if abs(expected - leaked) > 1e-12 and abs(expected - keeps_negative) > 1e-12:
            return users, tx, expected

    pytest.fail('Could not construct a discriminating validation dataset.')


def test_schema_and_scaling_on_secret_data():
    """Execute the submitted pipeline on unseen data and compare with canonical behavior."""
    users, tx, expected = build_discriminating_fixture()
    backup_dir = tempfile.mkdtemp(prefix='pipeline-data-backup-')
    users_backup = os.path.join(backup_dir, 'users.csv')
    tx_backup = os.path.join(backup_dir, 'transactions.csv')
    shutil.copy2(USERS_FILE, users_backup)
    shutil.copy2(TX_FILE, tx_backup)

    try:
        users.to_csv(USERS_FILE, index=False)
        tx.to_csv(TX_FILE, index=False)
        result = run_submission()
        assert result.returncode == 0, (
            'The modified script failed on data containing missing ages and negative amounts.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        data = read_metrics()
        actual = data['accuracy']
        assert abs(actual - expected) < 1e-7, (
            f'The script reported {actual} on unseen input, but the schema-correct, '
            f'train-only-scaling pipeline reports {expected}.'
        )
    finally:
        shutil.copy2(users_backup, USERS_FILE)
        shutil.copy2(tx_backup, TX_FILE)
        shutil.rmtree(backup_dir, ignore_errors=True)
        # Leave the requested output corresponding to the original supplied data.
        subprocess.run(
            [sys.executable, TRAIN_SCRIPT],
            cwd='/home/user/src',
            capture_output=True,
            text=True,
            timeout=60,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
