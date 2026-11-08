#!/bin/bash
set -e
mkdir -p /logs/verifier
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export MKL_NUM_THREADS=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import stat
import subprocess
import sys
from functools import lru_cache

import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.impute import SimpleImputer
from sklearn.neighbors import KNeighborsClassifier

DATA_PATH = "/home/user/data.csv"
PIPELINE_PATH = "/home/user/leaky_pipeline.py"
RUN_PATH = "/home/user/run.sh"
OUTPUT_PATH = "/home/user/recommendations.csv"


@lru_cache(maxsize=1)
def canonical_data():
    """Regenerate the immutable input supplied by setup."""
    np.random.seed(42)
    n_samples = 1000
    n_features = 50

    X = np.random.randn(n_samples, n_features) * 10
    mask = np.random.rand(n_samples, n_features) < 0.1
    X[mask] = np.nan

    outlier_mask = np.random.rand(n_samples, n_features) < 0.05
    X[outlier_mask] = X[outlier_mask] * 100

    user_ids = [f'U{i:04d}' for i in range(n_samples)]
    items = ['ItemA', 'ItemB', 'ItemC', 'ItemD', 'ItemE']
    X_clean = np.nan_to_num(X, nan=0.0)
    X_clean = np.clip(X_clean, -30, 30)
    weights = np.random.randn(n_features, len(items))
    logits = X_clean.dot(weights)
    target_idx = np.argmax(logits, axis=1)
    target_items = [items[i] for i in target_idx]

    generated = pd.DataFrame(X, columns=[f'feat_{i}' for i in range(n_features)])
    generated.insert(0, 'user_id', user_ids)
    generated['target_item'] = target_items

    # Match the setup's CSV serialization/read round trip.
    return pd.read_csv(io.StringIO(generated.to_csv(index=False)))


@lru_cache(maxsize=1)
def expected_output():
    """Independently execute the required leakage-free pipeline."""
    df = canonical_data()
    X = df.drop(columns=['user_id', 'target_item'])
    y = df['target_item']

    X_train_raw = X.iloc[:800]
    X_test_raw = X.iloc[800:]
    y_train = y.iloc[:800]

    imputer = SimpleImputer(strategy='median')
    X_train_imputed = imputer.fit_transform(X_train_raw)
    X_test_imputed = imputer.transform(X_test_raw)

    p1 = np.percentile(X_train_imputed, 1, axis=0)
    p99 = np.percentile(X_train_imputed, 99, axis=0)
    X_train_clipped = np.clip(X_train_imputed, p1, p99)
    X_test_clipped = np.clip(X_test_imputed, p1, p99)

    pca = PCA(n_components=10, random_state=42)
    X_train_pca = pca.fit_transform(X_train_clipped)
    X_test_pca = pca.transform(X_test_clipped)

    knn = KNeighborsClassifier(n_neighbors=5, metric='euclidean')
    knn.fit(X_train_pca, y_train)
    predictions = knn.predict(X_test_pca)

    return pd.DataFrame({
        'user_id': df['user_id'].iloc[800:].to_numpy(),
        'recommended_item': predictions,
    })


def assert_recommendations_are_correct():
    assert os.path.isfile(OUTPUT_PATH), f"File not found: {OUTPUT_PATH}. The output file is missing."

    with open(OUTPUT_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['user_id', 'recommended_item'], f"Incorrect header in recommendations.csv: {header}"
        rows = list(reader)

    assert len(rows) == 200, f"Expected 200 rows in recommendations.csv, found {len(rows)}"
    for i, row in enumerate(rows):
        assert len(row) == 2, f"Row {i+1} does not have exactly 2 columns."

    expected_user_ids = [f'U{i:04d}' for i in range(800, 1000)]
    actual_user_ids = [row[0] for row in rows]
    assert actual_user_ids == expected_user_ids, "The user_id column does not match the expected test set users."

    valid_items = {'ItemA', 'ItemB', 'ItemC', 'ItemD', 'ItemE'}
    for i, row in enumerate(rows):
        assert row[1] in valid_items, f"Invalid recommended_item '{row[1]}' in row {i+1}."

    expected_items = expected_output()['recommended_item'].tolist()
    actual_items = [row[1] for row in rows]
    assert actual_items == expected_items, "Recommendations do not match the required leakage-free KNN pipeline."


def test_input_dataset_is_unchanged():
    assert os.path.isfile(DATA_PATH), f"File not found: {DATA_PATH}"
    actual = pd.read_csv(DATA_PATH)
    pd.testing.assert_frame_equal(actual, canonical_data(), check_exact=True)


def test_run_sh_exists_and_executable():
    """Test that run.sh exists and is executable."""
    assert os.path.isfile(RUN_PATH), f"File not found: {RUN_PATH}. The run script is missing."
    st = os.stat(RUN_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {RUN_PATH} is not executable."


def test_run_sh_contents():
    """Test that run.sh sets the correct environment variables."""
    with open(RUN_PATH, 'r') as f:
        content = f.read()

    assert "OMP_NUM_THREADS=1" in content, "run.sh is missing OMP_NUM_THREADS=1"
    assert "OPENBLAS_NUM_THREADS=1" in content, "run.sh is missing OPENBLAS_NUM_THREADS=1"
    assert "MKL_NUM_THREADS=1" in content, "run.sh is missing MKL_NUM_THREADS=1"
    assert "leaky_pipeline.py" in content, "run.sh does not execute the fixed Python pipeline"


def test_run_sh_executes_pipeline_correctly():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [RUN_PATH], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
    )
    assert result.returncode == 0, f"run.sh failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert_recommendations_are_correct()


def test_python_pipeline_executes_correctly():
    assert os.path.isfile(PIPELINE_PATH), f"File not found: {PIPELINE_PATH}. The fixed Python script is missing."
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    env = os.environ.copy()
    env.update({
        'OMP_NUM_THREADS': '1',
        'OPENBLAS_NUM_THREADS': '1',
        'MKL_NUM_THREADS': '1',
    })
    result = subprocess.run(
        [sys.executable, PIPELINE_PATH], cwd='/home/user', env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
    )
    assert result.returncode == 0, f"Python pipeline failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert_recommendations_are_correct()


def test_recommendations_csv_structure():
    """Retain the original structure and value checks on the final artifact."""
    assert_recommendations_are_correct()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
