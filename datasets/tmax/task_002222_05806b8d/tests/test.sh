#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import secrets
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

SCRIPT_PATH = Path('/home/user/prepare_data.py')
INPUT_PATH = Path('/home/user/sensor_data.csv')
OUTPUT_PATH = Path('/home/user/processed_features.csv')

CANONICAL_INPUT = '''s1,s2,s3,s4
2.5,1.1,5.4,0.3
3.1,1.5,4.9,0.5
2.8,1.2,5.1,0.4
3.5,1.8,4.5,0.7
2.9,1.3,5.0,0.4
3.2,1.6,4.7,0.6
2.6,1.2,5.3,0.3
3.0,1.4,4.8,0.5
'''


def test_processed_features_exists():
    file_path = '/home/user/processed_features.csv'
    assert os.path.exists(file_path), f'File {file_path} is missing.'
    assert os.path.isfile(file_path), f'Path {file_path} is not a file.'


def test_processed_features_format_and_shape():
    file_path = '/home/user/processed_features.csv'

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)

        assert header is not None, 'The processed_features.csv file is empty.'
        assert header == ['PC1', 'PC2'], f"Expected header ['PC1', 'PC2'], got {header}"

        row_count = 0
        for row in reader:
            row_count += 1
            assert len(row) == 2, f'Row {row_count} does not have exactly 2 columns.'

            try:
                float(row[0])
                float(row[1])
            except ValueError:
                pytest.fail(f'Row {row_count} contains non-numeric values: {row}')

            for val_str in row:
                if '.' in val_str:
                    decimals = len(val_str.split('.')[1])
                    assert decimals <= 4, f'Value {val_str} in row {row_count} is not rounded to 4 decimal places.'

        assert row_count == 10000, f'Expected exactly 10,000 data rows, got {row_count}'


def test_prepare_data_script_exists():
    script_path = '/home/user/prepare_data.py'
    assert os.path.exists(script_path), f'Script {script_path} is missing.'
    assert os.path.isfile(script_path), f'Path {script_path} is not a file.'


def test_prepare_data_does_not_import_sklearn():
    tree = ast.parse(SCRIPT_PATH.read_text(), filename=str(SCRIPT_PATH))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules = [alias.name for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            modules = [node.module or '']
        else:
            continue
        assert all(name.split('.')[0] != 'sklearn' for name in modules), \
            'prepare_data.py must not use scikit-learn.'


def expected_projection(source):
    bootstrapped = source.sample(n=10000, replace=True, random_state=42)
    standardized = (bootstrapped - bootstrapped.mean()) / bootstrapped.std(ddof=0)
    covariance = np.cov(standardized.to_numpy(), rowvar=False, bias=True)
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    order = np.argsort(eigenvalues)[::-1]
    return standardized.to_numpy().dot(eigenvectors[:, order[:2]])


def run_submission():
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    result = subprocess.run(
        ['python3', str(SCRIPT_PATH)],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'prepare_data.py failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT_PATH.exists(), 'Running prepare_data.py did not create processed_features.csv.'
    assert OUTPUT_PATH.is_file(), 'processed_features.csv is not a regular file.'


def assert_output_matches(source):
    with OUTPUT_PATH.open('r', newline='') as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ['PC1', 'PC2']
    assert len(rows) == 10001
    try:
        actual = np.asarray([[float(x), float(y)] for x, y in rows[1:]], dtype=float)
    except (ValueError, TypeError) as exc:
        pytest.fail(f'Output contains invalid numeric data: {exc}')

    assert actual.shape == (10000, 2)
    assert np.isfinite(actual).all(), 'Output contains NaN or infinite values.'
    expected = expected_projection(source)

    # Eigenvector direction is arbitrary, so accept either sign independently
    # for each principal component.
    for column in range(2):
        positive_error = np.max(np.abs(actual[:, column] - expected[:, column]))
        negative_error = np.max(np.abs(actual[:, column] + expected[:, column]))
        assert min(positive_error, negative_error) <= 5.1e-5, (
            f'PC{column + 1} does not match the required bootstrap/PCA projection.'
        )


def test_script_computes_required_bootstrap_pca():
    canonical = pd.read_csv(pd.io.common.StringIO(CANONICAL_INPUT))
    INPUT_PATH.write_text(CANONICAL_INPUT)
    run_submission()
    assert_output_matches(canonical)

    # Exercise the script on an unpredictable second dataset so a fixed or
    # hard-coded processed_features.csv cannot pass.
    rng = np.random.default_rng(secrets.randbits(64))
    alternate = pd.DataFrame(
        rng.normal(size=(19, 4)) * np.array([1.0, 2.5, 0.4, 4.0])
        + np.array([3.0, -2.0, 8.0, 0.5]),
        columns=['s1', 's2', 's3', 's4'],
    )
    try:
        alternate.to_csv(INPUT_PATH, index=False)
        run_submission()
        assert_output_matches(alternate)
    finally:
        # Leave the required artifact generated from the provided dataset.
        INPUT_PATH.write_text(CANONICAL_INPUT)
        run_submission()
        assert_output_matches(canonical)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
