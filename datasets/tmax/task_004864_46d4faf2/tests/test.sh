#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sys
import subprocess
import pytest


def run_python_script(script):
    """Run inline Python in a subprocess with the installed environment libraries."""
    return subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True
    )


def test_00_pipeline_exists_runs_and_produces_outputs():
    """Require the requested script itself to regenerate both output artifacts."""
    pipeline = '/home/user/pipeline.py'
    assert os.path.isfile(pipeline), "/home/user/pipeline.py does not exist or is not a regular file."

    # Remove any pre-existing artifacts so a no-op script cannot pass using stale files.
    for path in ['/home/user/clean_data.parquet', '/home/user/experiment.json']:
        if os.path.lexists(path):
            os.unlink(path)

    try:
        result = subprocess.run(
            [sys.executable, pipeline],
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=120
        )
    except subprocess.TimeoutExpired:
        pytest.fail('/home/user/pipeline.py timed out.')

    assert result.returncode == 0, (
        f"/home/user/pipeline.py failed with exit code {result.returncode}: "
        f"{result.stderr.strip() or result.stdout.strip()}"
    )
    assert os.path.isfile('/home/user/clean_data.parquet'), \
        "pipeline.py did not create /home/user/clean_data.parquet"
    assert os.path.isfile('/home/user/experiment.json'), \
        "pipeline.py did not create /home/user/experiment.json"


def test_files_exist():
    """Verify that the required output files were created."""
    assert os.path.isfile('/home/user/clean_data.parquet'), "/home/user/clean_data.parquet does not exist."
    assert os.path.isfile('/home/user/experiment.json'), "/home/user/experiment.json does not exist."


def test_experiment_json_format_and_values():
    """Verify the contents of experiment.json against expected computed values."""
    compute_script = """
import pandas as pd
import numpy as np
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV
import json

df = pd.read_csv('/home/user/data.csv')
df['Ratio'] = df['Feature_A'] / df['Feature_B']
df.replace([np.inf, -np.inf], np.nan, inplace=True)
df.dropna(inplace=True)

X = df[['Feature_A', 'Feature_B', 'Ratio']]
y = df['Target']

model = Ridge()
grid = GridSearchCV(model, param_grid={'alpha': [0.1, 1.0, 10.0]}, cv=5, scoring='neg_mean_squared_error')
grid.fit(X, y)

best_alpha = grid.best_params_['alpha']
best_mse = round(-grid.best_score_, 4)

print(json.dumps({'best_alpha': best_alpha, 'best_cv_mse': best_mse}))
"""
    result = run_python_script(compute_script)
    assert result.returncode == 0, f"Failed to compute expected values: {result.stderr}"

    expected_data = json.loads(result.stdout.strip())

    with open('/home/user/experiment.json', 'r') as f:
        try:
            student_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/experiment.json is not a valid JSON file.")

    assert "best_alpha" in student_data, "Missing 'best_alpha' key in experiment.json"
    assert "best_cv_mse" in student_data, "Missing 'best_cv_mse' key in experiment.json"

    assert abs(student_data["best_alpha"] - expected_data["best_alpha"]) < 1e-5, \
        f"Expected best_alpha {expected_data['best_alpha']}, got {student_data['best_alpha']}"

    assert abs(student_data["best_cv_mse"] - expected_data["best_cv_mse"]) < 1e-3, \
        f"Expected best_cv_mse {expected_data['best_cv_mse']}, got {student_data['best_cv_mse']}"


def test_parquet_schema_and_data():
    """Verify exact schema and all cleaned values in the Parquet output."""
    check_script = """
import pandas as pd
import numpy as np
import sys

try:
    expected = pd.read_csv('/home/user/data.csv')
    expected['Ratio'] = expected['Feature_A'] / expected['Feature_B']
    expected.replace([np.inf, -np.inf], np.nan, inplace=True)
    expected.dropna(inplace=True)
    expected = expected.astype({
        'ID': 'int64',
        'Feature_A': 'float64',
        'Feature_B': 'float64',
        'Target': 'float64',
        'Ratio': 'float64',
    })

    pq_df = pd.read_parquet('/home/user/clean_data.parquet')

    if len(pq_df) != len(expected):
        print(f"Row count mismatch: expected {len(expected)}, got {len(pq_df)}")
        sys.exit(1)

    expected_columns = ['ID', 'Feature_A', 'Feature_B', 'Target', 'Ratio']
    if len(pq_df.columns) != len(expected_columns) or set(pq_df.columns) != set(expected_columns):
        print(f"Column mismatch: expected {expected_columns}, got {list(pq_df.columns)}")
        sys.exit(2)

    if pq_df['ID'].dtype != np.dtype('int64'):
        print(f"ID column must be exactly int64. Got {pq_df['ID'].dtype}")
        sys.exit(3)

    for col in ['Feature_A', 'Feature_B', 'Ratio', 'Target']:
        if pq_df[col].dtype != np.dtype('float64'):
            print(f"{col} column must be exactly float64. Got {pq_df[col].dtype}")
            sys.exit(4)

    # Row ordering is not part of the requested schema, so compare by the unique ID.
    expected_cmp = expected[expected_columns].sort_values('ID').reset_index(drop=True)
    actual_cmp = pq_df[expected_columns].sort_values('ID').reset_index(drop=True)
    pd.testing.assert_frame_equal(
        actual_cmp,
        expected_cmp,
        check_dtype=True,
        check_exact=True,
        check_names=True,
    )

    sys.exit(0)
except Exception as e:
    print(str(e))
    sys.exit(5)
"""
    result = run_python_script(check_script)
    assert result.returncode == 0, f"Parquet validation failed: {result.stdout.strip() or result.stderr.strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
