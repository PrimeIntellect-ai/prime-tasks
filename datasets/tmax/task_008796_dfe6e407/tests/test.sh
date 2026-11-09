#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import LogisticRegression, Ridge

PIPELINE_PATH = '/home/user/pipeline.py'
DATA_PATH = '/home/user/data.csv'
RESULTS_PATH = '/home/user/results.json'


def compute_expected(data_path):
    df = pd.read_csv(data_path)
    feature_cols = [c for c in df.columns if c.startswith('feature_')]

    correlated_pair = None
    correlations = df[feature_cols].corr().abs()
    for i in range(len(feature_cols)):
        for j in range(i + 1, len(feature_cols)):
            if correlations.iloc[i, j] > 0.999:
                correlated_pair = (feature_cols[i], feature_cols[j])
                break
        if correlated_pair:
            break

    assert correlated_pair is not None, 'Could not find a highly correlated feature pair.'
    idx_a = int(correlated_pair[0].split('_')[1])
    idx_b = int(correlated_pair[1].split('_')[1])
    dropped = correlated_pair[0] if idx_a > idx_b else correlated_pair[1]
    remaining_features = [c for c in feature_cols if c != dropped]

    known_mask = df['target_reg'].notna()
    missing_mask = ~known_mask
    ridge = Ridge(alpha=1.0, random_state=42)
    ridge.fit(df.loc[known_mask, remaining_features], df.loc[known_mask, 'target_reg'])
    predictions = ridge.predict(df.loc[missing_mask, remaining_features])

    cleaned = df.copy()
    cleaned.loc[missing_mask, 'target_reg'] = predictions
    classification_features = remaining_features + ['target_reg']
    classifier = LogisticRegression(random_state=42)
    classifier.fit(cleaned[classification_features], cleaned['failure'])
    accuracy = classifier.score(cleaned[classification_features], cleaned['failure'])

    return {
        'dropped_feature': dropped,
        'imputed_target_reg_mean': float(f'{np.mean(predictions):.4f}'),
        'classification_accuracy': float(f'{accuracy:.4f}'),
    }


def make_challenge_dataset(path):
    rng = np.random.default_rng(secrets.randbits(128))
    n_samples = 257
    values = rng.normal(size=(n_samples, 10))
    values[:, 7] = 2.5 * values[:, 2] + 0.1
    df = pd.DataFrame(values, columns=[f'feature_{i}' for i in range(10)])

    target = (
        2.4 * df['feature_0']
        - 1.7 * df['feature_4']
        + 0.8 * df['feature_8']
        + rng.normal(scale=0.6, size=n_samples)
    )
    missing_indices = rng.choice(n_samples, size=23, replace=False)
    target.iloc[missing_indices] = np.nan
    df['target_reg'] = target

    latent = (
        1.1 * df['feature_1']
        + 1.8 * df['feature_5']
        - 0.9 * df['feature_2']
        + rng.normal(scale=1.0, size=n_samples)
    )
    labels = (latent > 0).astype(int)
    if labels.nunique() < 2:
        labels.iloc[0] = 0
        labels.iloc[1] = 1
    df['failure'] = labels
    df.to_csv(path, index=False)


PIPELINE_EXISTED = os.path.isfile(PIPELINE_PATH)
EXECUTION_ERROR = None
EXECUTION_RESULT = None
EXPECTED = None

if PIPELINE_EXISTED:
    try:
        with open(DATA_PATH, 'rb') as f:
            original_data = f.read()
    except Exception as exc:
        original_data = None
        EXECUTION_ERROR = f'Could not preserve {DATA_PATH}: {exc}'

    if original_data is not None:
        try:
            make_challenge_dataset(DATA_PATH)
            # Re-read the serialized CSV so expected values use exactly the same
            # inputs that the submitted pipeline receives.
            EXPECTED = compute_expected(DATA_PATH)
            EXECUTION_RESULT = subprocess.run(
                ['python3', PIPELINE_PATH],
                cwd='/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
        except subprocess.TimeoutExpired:
            EXECUTION_ERROR = 'pipeline.py timed out after 120 seconds.'
        except Exception as exc:
            EXECUTION_ERROR = f'Could not exercise pipeline.py: {exc}'
        finally:
            with open(DATA_PATH, 'wb') as f:
                f.write(original_data)


def test_pipeline_exists_and_executes():
    assert PIPELINE_EXISTED, 'The file /home/user/pipeline.py was not found or is not a regular file.'
    assert EXECUTION_ERROR is None, EXECUTION_ERROR
    assert EXECUTION_RESULT is not None, 'pipeline.py was not executed.'
    assert EXECUTION_RESULT.returncode == 0, (
        'pipeline.py exited unsuccessfully.\n'
        f'stdout:\n{EXECUTION_RESULT.stdout}\n'
        f'stderr:\n{EXECUTION_RESULT.stderr}'
    )
    assert os.path.isfile(PIPELINE_PATH), 'pipeline.py did not remain present after execution.'


def test_results_json_exists():
    """Test that the results.json file exists."""
    assert os.path.isfile(RESULTS_PATH), 'The file /home/user/results.json was not found.'


def test_results_json_structure():
    """Test that results.json contains the correct keys and correctly formatted values."""
    with open(RESULTS_PATH, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('/home/user/results.json is not a valid JSON file.')

    expected_keys = {'dropped_feature', 'imputed_target_reg_mean', 'classification_accuracy'}
    assert set(results.keys()) == expected_keys, (
        f'JSON keys do not match. Expected {expected_keys}, got {set(results.keys())}.'
    )
    assert isinstance(results['dropped_feature'], str), 'dropped_feature must be a string.'

    try:
        float(results['imputed_target_reg_mean'])
    except (ValueError, TypeError):
        pytest.fail('imputed_target_reg_mean is not a valid number.')

    try:
        float(results['classification_accuracy'])
    except (ValueError, TypeError):
        pytest.fail('classification_accuracy is not a valid number.')


def test_reported_model_results():
    """Recompute and verify both model-derived report values."""
    assert EXPECTED is not None, 'Expected model results could not be computed.'
    with open(RESULTS_PATH, 'r') as f:
        results = json.load(f)

    reported_mean = float(results['imputed_target_reg_mean'])
    reported_accuracy = float(results['classification_accuracy'])
    assert math.isfinite(reported_mean), 'imputed_target_reg_mean must be finite.'
    assert math.isfinite(reported_accuracy), 'classification_accuracy must be finite.'
    assert reported_mean == EXPECTED['imputed_target_reg_mean'], (
        f"Expected imputed_target_reg_mean {EXPECTED['imputed_target_reg_mean']:.4f}, "
        f'got {reported_mean}.'
    )
    assert reported_accuracy == EXPECTED['classification_accuracy'], (
        f"Expected classification_accuracy {EXPECTED['classification_accuracy']:.4f}, "
        f'got {reported_accuracy}.'
    )


def test_dropped_feature_logic():
    """Verify the dropped feature by calculating correlation in pure Python."""
    data_path = '/home/user/data.csv'
    assert os.path.isfile(data_path), f'The file {data_path} is missing.'

    with open(data_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = [row for row in reader]

    feature_cols = [c for c in header if c.startswith('feature_')]
    col_indices = {c: header.index(c) for c in feature_cols}

    n = len(data)
    means = {}
    for c in feature_cols:
        idx = col_indices[c]
        means[c] = sum(float(row[idx]) for row in data) / n

    stds = {}
    for c in feature_cols:
        idx = col_indices[c]
        variance = sum((float(row[idx]) - means[c]) ** 2 for row in data) / n
        stds[c] = math.sqrt(variance)

    correlated_pair = None
    for i in range(len(feature_cols)):
        for j in range(i + 1, len(feature_cols)):
            c1 = feature_cols[i]
            c2 = feature_cols[j]
            idx1 = col_indices[c1]
            idx2 = col_indices[c2]
            cov = sum(
                (float(row[idx1]) - means[c1]) * (float(row[idx2]) - means[c2])
                for row in data
            ) / n
            corr = abs(cov / (stds[c1] * stds[c2]))
            if corr > 0.999:
                correlated_pair = (c1, c2)
                break
        if correlated_pair:
            break

    assert correlated_pair is not None, 'Could not find a highly correlated pair of features in the dataset.'
    idx_a = int(correlated_pair[0].split('_')[1])
    idx_b = int(correlated_pair[1].split('_')[1])
    expected_dropped = correlated_pair[0] if idx_a > idx_b else correlated_pair[1]

    with open(RESULTS_PATH, 'r') as f:
        results = json.load(f)

    assert results['dropped_feature'] == expected_dropped, (
        f"Expected dropped_feature to be {expected_dropped}, got {results['dropped_feature']}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
