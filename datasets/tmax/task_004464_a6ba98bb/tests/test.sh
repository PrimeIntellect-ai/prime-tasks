#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import numpy as np
import pandas as pd
import pytest
from sklearn.model_selection import KFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import PolynomialFeatures
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error

TRAIN_FILE = '/home/user/data/train.csv'
TEST_FILE = '/home/user/data/test.csv'
RESULTS_FILE = '/home/user/experiments/cv_results.csv'
PREDS_FILE = '/home/user/experiments/predictions.txt'
DEGREES = [1, 2, 3, 4]
ALPHAS = [0.1, 1.0, 10.0]


def load_and_validate_source_data():
    assert os.path.isfile(TRAIN_FILE), f"Missing training data: {TRAIN_FILE}"
    assert os.path.isfile(TEST_FILE), f"Missing test data: {TEST_FILE}"

    train = pd.read_csv(TRAIN_FILE)
    test = pd.read_csv(TEST_FILE)
    assert list(train.columns) == ['x', 'y'], f"Unexpected train columns: {list(train.columns)}"
    assert list(test.columns) == ['x'], f"Unexpected test columns: {list(test.columns)}"
    assert len(train) == 100, f"Expected 100 training rows, found {len(train)}"
    assert len(test) == 20, f"Expected 20 test rows, found {len(test)}"

    # Ensure the supplied datasets were not replaced to influence verification.
    rng = np.random.RandomState(123)
    expected_x_train = rng.uniform(-3, 3, 100)
    expected_y_train = (
        0.5 * expected_x_train**3
        - 1.2 * expected_x_train**2
        + 2 * expected_x_train
        + 1
        + rng.normal(0, 2, 100)
    )
    expected_x_test = np.linspace(-3, 3, 20)
    np.testing.assert_allclose(train['x'].to_numpy(), expected_x_train, rtol=0, atol=1e-12)
    np.testing.assert_allclose(train['y'].to_numpy(), expected_y_train, rtol=0, atol=1e-12)
    np.testing.assert_allclose(test['x'].to_numpy(), expected_x_test, rtol=0, atol=1e-12)
    return train, test


def compute_expected():
    train, test = load_and_validate_source_data()
    X = train[['x']].to_numpy()
    y = train['y'].to_numpy()
    X_test = test[['x']].to_numpy()

    expected_mses = {}
    raw_mses = {}
    for degree in DEGREES:
        for alpha in ALPHAS:
            fold_mses = []
            kfold = KFold(n_splits=5, shuffle=True, random_state=42)
            for train_idx, valid_idx in kfold.split(X):
                model = Pipeline([
                    ('polynomialfeatures', PolynomialFeatures(degree=degree)),
                    ('ridge', Ridge(alpha=alpha)),
                ])
                model.fit(X[train_idx], y[train_idx])
                fold_predictions = model.predict(X[valid_idx])
                fold_mses.append(mean_squared_error(y[valid_idx], fold_predictions))
            mean_mse = float(np.mean(fold_mses))
            raw_mses[(degree, alpha)] = mean_mse
            expected_mses[(degree, alpha)] = f'{mean_mse:.4f}'

    best_degree, best_alpha = min(raw_mses, key=raw_mses.get)
    best_model = Pipeline([
        ('polynomialfeatures', PolynomialFeatures(degree=best_degree)),
        ('ridge', Ridge(alpha=best_alpha)),
    ])
    best_model.fit(X, y)
    expected_predictions = [f'{value:.4f}' for value in best_model.predict(X_test)]
    return expected_mses, expected_predictions


EXPECTED_MSES, EXPECTED_PREDICTIONS = compute_expected()


def test_cv_results_file():
    """Verify cv_results.csv structure, sorting, formatting, and computed values."""
    assert os.path.isfile(RESULTS_FILE), f"Missing cv_results.csv file: {RESULTS_FILE}"

    with open(RESULTS_FILE, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['degree', 'alpha', 'mean_mse'], f"Incorrect header in cv_results.csv: {header}"

        rows = list(reader)
        assert len(rows) == 12, f"Expected 12 rows of results, found {len(rows)}"

        degrees_alphas = set()
        mses = []
        for row in rows:
            assert len(row) == 3, f"Expected 3 columns per row, found {len(row)} in row {row}"
            degree, alpha, mean_mse = row

            try:
                d = int(degree)
                a = float(alpha)
                m = float(mean_mse)
            except ValueError as e:
                pytest.fail(f"Invalid data type in row {row}: {e}")

            assert d in DEGREES, f"Unexpected degree {d}"
            assert a in ALPHAS, f"Unexpected alpha {a}"

            # Preserve the original formatting assertion and enforce exactly four places.
            assert len(mean_mse.split('.')[-1]) <= 4 or mean_mse.endswith('0'), f"mean_mse {mean_mse} not rounded to 4 decimal places"
            assert re.fullmatch(r'[+-]?\d+\.\d{4}', mean_mse), f"mean_mse {mean_mse} is not formatted to exactly 4 decimal places"
            assert np.isfinite(m), f"mean_mse {mean_mse} is not finite"
            assert mean_mse == EXPECTED_MSES[(d, a)], (
                f"Incorrect mean MSE for degree={d}, alpha={a}: "
                f"expected {EXPECTED_MSES[(d, a)]}, found {mean_mse}"
            )

            degrees_alphas.add((d, a))
            mses.append(m)

        assert len(degrees_alphas) == 12, "Duplicate or missing degree/alpha combinations"
        assert mses == sorted(mses), "cv_results.csv is not sorted by mean_mse in ascending order"


def test_predictions_file():
    """Verify predictions.txt format and recomputed prediction values."""
    assert os.path.isfile(PREDS_FILE), f"Missing predictions.txt file: {PREDS_FILE}"

    with open(PREDS_FILE, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 20, f"Expected 20 predictions, found {len(lines)}"

    for i, line in enumerate(lines):
        try:
            val = float(line)
        except ValueError:
            pytest.fail(f"Invalid prediction on line {i+1}: {line}")

        assert np.isfinite(val), f"Prediction {line} on line {i+1} is not finite"
        if '.' in line:
            decimals = line.split('.')[1]
            assert len(decimals) == 4, f"Prediction {line} on line {i+1} is not formatted to exactly 4 decimal places"
        else:
            pytest.fail(f"Prediction {line} on line {i+1} is missing decimal places")

        assert re.fullmatch(r'[+-]?\d+\.\d{4}', line), f"Prediction {line} on line {i+1} has invalid formatting"
        assert line == EXPECTED_PREDICTIONS[i], (
            f"Incorrect prediction on line {i+1}: expected {EXPECTED_PREDICTIONS[i]}, found {line}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
