#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import stat
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.preprocessing import StandardScaler

RAW = Path('/home/user/data/raw_users.csv')
PIPELINE = Path('/home/user/src/pipeline.py')
SIMILARITY = Path('/home/user/src/similarity.py')
OUTDIR = Path('/home/user/data/processed')
TRAIN = OUTDIR / 'train.csv'
TEST = OUTDIR / 'test.csv'
SIM_OUT = OUTDIR / 'most_similar_user.txt'
FEATURES = ['age', 'income', 'activity_score']
COLUMNS = ['user_id', 'age', 'income', 'activity_score']

FAULTY_PIPELINE = '''import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler

df = pd.read_csv('/home/user/data/raw_users.csv')
features = ['age', 'income', 'activity_score']

# FAULTY: Leaking test data into the training preprocessing
imputer = SimpleImputer(strategy='mean')
df[features] = imputer.fit_transform(df[features])

scaler = StandardScaler()
df[features] = scaler.fit_transform(df[features])

# Splitting AFTER preprocessing
train, test = train_test_split(df, test_size=0.25, random_state=42, shuffle=False)

# TODO: Save train and test to /home/user/data/processed/
'''


def assert_regular_file(path):
    assert path.exists(), f'Missing required source script: {path}'
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode) and not path.is_symlink(), f'Expected a regular file: {path}'


def clear_outputs():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    for path in (TRAIN, TEST, SIM_OUT):
        if path.exists() or path.is_symlink():
            path.unlink()


def run_script(path):
    result = subprocess.run(
        [sys.executable, str(path)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{path} failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def expected_processed(raw):
    # For 100 rows, the required non-shuffled 25% split is rows 0:75 and 75:100.
    train_raw = raw.iloc[:75].copy()
    test_raw = raw.iloc[75:].copy()

    low = train_raw['income'].quantile(0.05)
    high = train_raw['income'].quantile(0.95)
    train_raw['income'] = train_raw['income'].clip(lower=low, upper=high)
    test_raw['income'] = test_raw['income'].clip(lower=low, upper=high)

    imputer = SimpleImputer(strategy='mean')
    train_imputed = imputer.fit_transform(train_raw[FEATURES])
    test_imputed = imputer.transform(test_raw[FEATURES])

    scaler = StandardScaler()
    train_scaled = scaler.fit_transform(train_imputed)
    test_scaled = scaler.transform(test_imputed)

    expected_train = pd.DataFrame(train_scaled, columns=FEATURES)
    expected_test = pd.DataFrame(test_scaled, columns=FEATURES)
    expected_train.insert(0, 'user_id', train_raw['user_id'].to_numpy())
    expected_test.insert(0, 'user_id', test_raw['user_id'].to_numpy())
    return expected_train, expected_test


def assert_processed(raw):
    # Preserve the original existence, header, and row-count assertions.
    assert TRAIN.is_file(), f'Processed train file missing: {TRAIN}'
    assert TEST.is_file(), f'Processed test file missing: {TEST}'

    with TRAIN.open(newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert set(header) == set(COLUMNS), f'Incorrect columns in train.csv: {header}'
        rows = list(reader)
        assert len(rows) == 75, f'Expected 75 rows in train.csv, found {len(rows)}'

    with TEST.open(newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert set(header) == set(COLUMNS), f'Incorrect columns in test.csv: {header}'
        rows = list(reader)
        assert len(rows) == 25, f'Expected 25 rows in test.csv, found {len(rows)}'

    actual_train = pd.read_csv(TRAIN)
    actual_test = pd.read_csv(TEST)
    assert list(actual_train.columns) == COLUMNS, 'train.csv columns are not in the required order'
    assert list(actual_test.columns) == COLUMNS, 'test.csv columns are not in the required order'

    expected_train, expected_test = expected_processed(raw)
    np.testing.assert_array_equal(
        actual_train['user_id'].to_numpy(), expected_train['user_id'].to_numpy()
    )
    np.testing.assert_array_equal(
        actual_test['user_id'].to_numpy(), expected_test['user_id'].to_numpy()
    )
    np.testing.assert_allclose(
        actual_train[FEATURES].to_numpy(),
        expected_train[FEATURES].to_numpy(),
        rtol=1e-8,
        atol=1e-8,
    )
    np.testing.assert_allclose(
        actual_test[FEATURES].to_numpy(),
        expected_test[FEATURES].to_numpy(),
        rtol=1e-8,
        atol=1e-8,
    )
    assert np.isfinite(actual_train[FEATURES].to_numpy()).all()
    assert np.isfinite(actual_test[FEATURES].to_numpy()).all()


def expected_similar_user(train, test):
    scores = cosine_similarity(test.loc[[0], FEATURES], train[FEATURES])[0]
    return int(train.iloc[int(np.argmax(scores))]['user_id'])


def assert_similarity(expected_id, require_original_answer=False):
    # Preserve the original output existence and integer assertions.
    assert SIM_OUT.is_file(), f'Similarity output missing: {SIM_OUT}'
    content = SIM_OUT.read_text().strip()
    assert content.isdigit(), f'Expected integer in {SIM_OUT}, got {content}'
    assert content == str(expected_id), (
        f'Expected most similar user_id to be {expected_id}, but got {content}'
    )
    if require_original_answer:
        assert content == '29', (
            'Expected most similar user_id to be 29, but got '
            f'{content}. Ensure data leakage is fixed and outlier handling is applied correctly.'
        )


def make_challenge_data():
    i = np.arange(100, dtype=float)
    age = 19.0 + (i % 23) * 1.7 + i * 0.03
    income = 28000.0 + (i % 19) * 3100.0 + i * 47.0
    activity = 0.8 + (i % 13) * 0.71 + i * 0.005

    # Missing values and train outliers exercise imputation and train-only clipping.
    age[[2, 11, 27, 48, 70, 78, 91]] = np.nan
    activity[[4, 18, 33, 57, 74, 76, 88, 99]] = np.nan
    income[0] = 9000000.0
    income[51] = -250000.0

    # Shift test-only distributions so fitting preprocessing on all rows is detectable.
    age[75:] += 140.0
    income[75:] += 1500000.0
    activity[75:] += 40.0
    income[80] = 8000000.0

    return pd.DataFrame({
        'user_id': np.arange(1001, 1101),
        'age': age,
        'income': income,
        'activity_score': activity,
    })


def test_end_to_end():
    assert_regular_file(PIPELINE)
    assert_regular_file(SIMILARITY)
    assert PIPELINE.read_text() != FAULTY_PIPELINE, 'pipeline.py is still the shipped faulty script'

    original_raw_bytes = RAW.read_bytes()
    original_raw = pd.read_csv(RAW)
    assert len(original_raw) == 100

    # Execute the pipeline on verifier-created data and compare every value with an
    # independently computed train-only preprocessing result.
    challenge = make_challenge_data()
    try:
        challenge.to_csv(RAW, index=False)
        clear_outputs()
        run_script(PIPELINE)
        assert_processed(challenge)

        # Exercise similarity.py on processed files whose answer is not the public
        # answer from the original dataset.
        rng = np.random.default_rng(20260911)
        sim_train = pd.DataFrame(rng.normal(size=(75, 3)), columns=FEATURES)
        sim_train.insert(0, 'user_id', np.arange(5001, 5076))
        sim_test = pd.DataFrame(rng.normal(size=(25, 3)), columns=FEATURES)
        sim_test.insert(0, 'user_id', np.arange(7001, 7026))
        target = np.array([1.25, -2.0, 0.75])
        sim_train.loc[11, FEATURES] = target
        sim_test.loc[0, FEATURES] = target
        sim_train.to_csv(TRAIN, index=False)
        sim_test.to_csv(TEST, index=False)
        if SIM_OUT.exists() or SIM_OUT.is_symlink():
            SIM_OUT.unlink()
        dynamic_expected = expected_similar_user(sim_train, sim_test)
        assert dynamic_expected != 29
        run_script(SIMILARITY)
        assert_similarity(dynamic_expected)
    finally:
        RAW.write_bytes(original_raw_bytes)

    # Run both submitted artifacts on the original input and retain all original
    # final-state assertions, including the known answer of 29.
    clear_outputs()
    run_script(PIPELINE)
    assert_processed(original_raw)
    run_script(SIMILARITY)
    final_train = pd.read_csv(TRAIN)
    final_test = pd.read_csv(TEST)
    derived_original_id = expected_similar_user(final_train, final_test)
    assert_similarity(derived_original_id, require_original_answer=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
