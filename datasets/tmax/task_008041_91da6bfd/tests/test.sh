#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import runpy
from unittest import mock

import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = '/home/user/bootstrap_pca.py'
DATA_PATH = '/home/user/sensor_data.csv'
OUTPUT_PATH = '/home/user/eigen_baseline.txt'


def reference_result(df):
    features = df.loc[df['sensor_state'] == 'ACTIVE', ['f1', 'f2', 'f3']].to_numpy(dtype=float)
    assert len(features) >= 2

    rng = np.random.RandomState(42)
    largest = []
    for _ in range(1000):
        indices = rng.choice(len(features), size=len(features), replace=True)
        covariance = np.cov(features[indices], rowvar=False, ddof=1)
        largest.append(np.linalg.eigvalsh(covariance)[-1])
    return f'{np.mean(largest):.4f}'


def execute_and_check(df):
    df.to_csv(DATA_PATH, index=False)
    loaded_df = pd.read_csv(DATA_PATH)
    expected = reference_result(loaded_df)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    original_seed = np.random.seed
    original_choice = np.random.choice
    seed_calls = []
    choice_calls = []

    def checked_seed(*args, **kwargs):
        seed_calls.append((args, kwargs, len(choice_calls)))
        return original_seed(*args, **kwargs)

    def checked_choice(a, size=None, replace=True, p=None):
        n = int((loaded_df['sensor_state'] == 'ACTIVE').sum())
        assert size is not None and np.isscalar(size) and int(size) == n, \
            'Every bootstrap sample must contain the same number of rows as the filtered dataset.'
        assert replace is True or bool(replace) is True, \
            'Bootstrap indices must be sampled with replacement.'
        if np.isscalar(a):
            assert int(a) == n, 'numpy.random.choice must sample valid filtered-row indices.'
        else:
            candidates = np.asarray(a)
            assert candidates.ndim == 1 and len(candidates) == n, \
                'numpy.random.choice must sample from all filtered-row indices.'
        choice_calls.append(1)
        return original_choice(a, size=size, replace=replace, p=p)

    with mock.patch.object(np.random, 'seed', checked_seed), \
         mock.patch.object(np.random, 'choice', checked_choice):
        runpy.run_path(SCRIPT_PATH, run_name='__main__')

    assert len(seed_calls) == 1, 'numpy.random.seed must be called exactly once before bootstrapping.'
    seed_args, seed_kwargs, choices_before_seed = seed_calls[0]
    seed_value = seed_args[0] if seed_args else seed_kwargs.get('seed')
    assert seed_value is not None and int(seed_value) == 42, 'The bootstrap RNG seed must be 42.'
    assert choices_before_seed == 0, 'numpy.random.seed(42) must be set before bootstrap sampling.'
    assert len(choice_calls) == 1000, 'The script must perform exactly 1000 numpy.random.choice bootstrap samples.'

    assert os.path.exists(OUTPUT_PATH), f'The file {OUTPUT_PATH} is missing after running the script.'
    assert os.path.isfile(OUTPUT_PATH), f'The path {OUTPUT_PATH} exists but is not a file.'
    with open(OUTPUT_PATH, 'r') as f:
        content = f.read().strip()
    assert re.fullmatch(r'[+-]?\d+\.\d{4}', content), \
        'The output must contain one numeric value formatted to exactly four decimal places.'
    assert content == expected, f'Expected {expected} for the supplied dataset, but found {content}.'


@pytest.fixture(scope='session', autouse=True)
def run_submission_on_original_and_unseen_data():
    assert os.path.exists(SCRIPT_PATH), f'The script {SCRIPT_PATH} is missing.'
    assert os.path.isfile(SCRIPT_PATH), f'The path {SCRIPT_PATH} exists but is not a file.'

    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    try:
        for _ in range(2):
            rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))
            active_count = 9 + int(rng.integers(0, 5))
            inactive_count = 4
            base = rng.normal(0, 2, active_count + inactive_count)
            test_df = pd.DataFrame({
                'sensor_state': ['ACTIVE'] * active_count + ['IDLE'] * inactive_count,
                'f1': base,
                'f2': 1.7 * base + rng.normal(0, 0.4, len(base)),
                'f3': rng.normal(3, 4, len(base)),
            }).sample(frac=1, random_state=int(rng.integers(0, 2**31 - 1))).reset_index(drop=True)
            # Inactive outliers ensure the ETL filter affects the answer.
            test_df.loc[test_df['sensor_state'] != 'ACTIVE', ['f1', 'f2', 'f3']] *= 100
            execute_and_check(test_df)
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)

    # Leave the requested artifact generated from the original supplied dataset.
    execute_and_check(pd.read_csv(DATA_PATH))
    yield


def test_eigen_baseline_file_exists():
    """Verify that the output file eigen_baseline.txt is created."""
    file_path = '/home/user/eigen_baseline.txt'
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} exists but is not a file."


def test_eigen_baseline_content():
    """Verify the content of eigen_baseline.txt matches the expected mean largest eigenvalue."""
    file_path = '/home/user/eigen_baseline.txt'
    assert os.path.exists(file_path), f"The file {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content, "The file eigen_baseline.txt is empty."

    try:
        value = float(content)
    except ValueError:
        raise AssertionError(f"The content of eigen_baseline.txt ('{content}') is not a valid float.")

    expected_value = 9.0766
    tolerance = 0.005

    assert abs(value - expected_value) <= tolerance, \
        f"The calculated mean eigenvalue {value} is not within the acceptable range of {expected_value} +/- {tolerance}."


def test_bootstrap_pca_script_exists():
    """Verify that the student's script bootstrap_pca.py exists."""
    script_path = '/home/user/bootstrap_pca.py'
    assert os.path.exists(script_path), f"The script {script_path} is missing."
    assert os.path.isfile(script_path), f"The path {script_path} exists but is not a file."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
