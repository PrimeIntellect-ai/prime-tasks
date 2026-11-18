#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os

import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.model_selection import GridSearchCV
from sklearn.naive_bayes import GaussianNB

SOURCE_DATA_PATH = '/home/user/data/unorganized_data.csv'
ORGANIZED_DATA_PATH = '/home/user/data/organized_data.csv'
MODEL_RESULTS_PATH = '/home/user/data/model_results.json'
VAR_SMOOTHING_VALUES = [1e-9, 1e-7, 1e-5, 1e-3, 1e-1]


def expected_clean_data():
    source = pd.read_csv(SOURCE_DATA_PATH)
    assert list(source.columns) == ['mass', 'volume', 'class']

    mass = pd.to_numeric(source['mass'], errors='coerce')
    volume = pd.to_numeric(source['volume'], errors='coerce')
    classes = pd.to_numeric(source['class'], errors='coerce')

    valid = (
        source.notna().all(axis=1)
        & mass.notna()
        & volume.notna()
        & classes.notna()
        & np.isfinite(mass)
        & np.isfinite(volume)
        & np.isfinite(classes)
        & (mass > 0)
        & (volume > 0)
        & (classes == np.floor(classes))
        & classes.isin([0, 1])
    )

    expected = pd.DataFrame({
        'mass': mass[valid].astype(float),
        'volume': volume[valid].astype(float),
        'class': classes[valid].astype(int),
    }, index=source.index[valid])
    expected.index.name = None
    return expected


def test_organized_data_exists_and_format():
    """Validate the complete cleaned CSV, including order and original indices."""
    assert os.path.exists(ORGANIZED_DATA_PATH), f"Missing cleaned data file at {ORGANIZED_DATA_PATH}"
    assert os.path.isfile(ORGANIZED_DATA_PATH), f"Path {ORGANIZED_DATA_PATH} is not a file"

    with open(ORGANIZED_DATA_PATH, 'r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) > 0, "organized_data.csv is empty"
    header = rows[0]
    assert 'mass' in header, "Column 'mass' missing from organized_data.csv header"
    assert 'volume' in header, "Column 'volume' missing from organized_data.csv header"
    assert 'class' in header, "Column 'class' missing from organized_data.csv header"
    assert len(header) == 4, "CSV must contain one preserved-index column and exactly three data columns"
    assert header[1:] == ['mass', 'volume', 'class'], "Data columns are not in the required order"

    data_rows = rows[1:]
    assert len(data_rows) == 200, f"Expected exactly 200 data rows, but found {len(data_rows)}"
    assert all(len(row) == 4 for row in data_rows), "Every CSV row must contain an index and three values"

    try:
        actual = pd.read_csv(ORGANIZED_DATA_PATH, index_col=0)
    except Exception as exc:
        pytest.fail(f"Could not parse organized_data.csv: {exc}")

    assert list(actual.columns) == ['mass', 'volume', 'class']
    assert not actual.isna().any().any(), "Cleaned data contains missing values"
    actual.index.name = None

    expected = expected_clean_data()
    try:
        assert_frame_equal(actual, expected, check_dtype=True, check_exact=False, rtol=1e-12, atol=1e-12)
    except AssertionError as exc:
        pytest.fail(f"organized_data.csv does not exactly match the required filtered rows: {exc}")


def test_model_results_json():
    """Recompute GridSearchCV and validate every reported value."""
    assert os.path.exists(MODEL_RESULTS_PATH), f"Missing results file at {MODEL_RESULTS_PATH}"
    assert os.path.isfile(MODEL_RESULTS_PATH), f"Path {MODEL_RESULTS_PATH} is not a file"

    with open(MODEL_RESULTS_PATH, 'r', encoding='utf-8') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {MODEL_RESULTS_PATH} is not valid JSON")

    expected_keys = {'best_var_smoothing', 'best_cv_score', 'cleaned_row_count'}
    actual_keys = set(results.keys())
    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f"Missing keys in model_results.json: {missing_keys}"
    extra_keys = actual_keys - expected_keys
    assert not extra_keys, f"Unexpected extra keys in model_results.json: {extra_keys}"

    assert isinstance(results['cleaned_row_count'], int) and not isinstance(results['cleaned_row_count'], bool), \
        "cleaned_row_count must be an integer"
    assert results['cleaned_row_count'] == 200, \
        f"Expected cleaned_row_count to be 200, got {results['cleaned_row_count']}"

    assert isinstance(results['best_var_smoothing'], float), "best_var_smoothing must be a float"
    assert math.isclose(results['best_var_smoothing'], 0.1, rel_tol=1e-5), \
        f"Expected best_var_smoothing to be 0.1, got {results['best_var_smoothing']}"

    assert isinstance(results['best_cv_score'], float), "best_cv_score must be a float"
    assert math.isclose(results['best_cv_score'], 1.0, rel_tol=1e-5), \
        f"Expected best_cv_score to be 1.0, got {results['best_cv_score']}"

    clean = expected_clean_data()
    search = GridSearchCV(
        GaussianNB(),
        {'var_smoothing': VAR_SMOOTHING_VALUES},
        cv=5,
    )
    search.fit(clean[['mass', 'volume']], clean['class'])

    expected_best = float(search.best_params_['var_smoothing'])
    expected_score = float(round(search.best_score_, 4))

    assert results['cleaned_row_count'] == len(clean), \
        "cleaned_row_count does not match the recomputed clean dataset"
    assert results['best_var_smoothing'] == expected_best, \
        f"best_var_smoothing does not match GridSearchCV: expected {expected_best}"
    assert math.isclose(results['best_cv_score'], expected_score, rel_tol=0.0, abs_tol=1e-12), \
        f"best_cv_score does not match the recomputed rounded score: expected {expected_score}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
