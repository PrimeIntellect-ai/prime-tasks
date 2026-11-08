#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import sys
import tempfile
import pytest

def test_results_json_exists_and_valid():
    """Check that results.json exists and is valid JSON."""
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"Results file not found at {results_path}"

    with open(results_path, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not valid JSON")

def test_results_content():
    """Verify the contents of results.json match the expected output."""
    results_path = "/home/user/results.json"
    with open(results_path, "r") as f:
        student_results = json.load(f)

    # Generate expected results using the environment's installed libraries
    golden_script = """
import pandas as pd
import json
from scipy.stats import pearsonr
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

df = pd.read_csv("/home/user/dataset.csv")
target = df["target"]

selected_features = []
for i in range(1, 51):
    feat = f"f{i}"
    corr, p_val = pearsonr(df[feat], target)
    if abs(corr) > 0.2 and p_val < 0.05:
        selected_features.append(feat)

selected_features.sort()

X_selected = df[selected_features]
param_grid = {'alpha': [0.1, 1.0, 10.0]}
grid = GridSearchCV(Ridge(), param_grid, cv=5)
grid.fit(X_selected, target)

results = {
    "selected_features": selected_features,
    "best_alpha": float(grid.best_params_['alpha']),
    "best_cv_score": round(float(grid.best_score_), 4)
}

with open("/home/user/expected_results.json", "w") as f:
    json.dump(results, f)
"""
    expected_path = "/home/user/expected_results.json"

    with tempfile.NamedTemporaryFile(mode="w", suffix=".py", delete=False) as tmp:
        tmp.write(golden_script)
        tmp_path = tmp.name

    try:
        subprocess.run([sys.executable, tmp_path], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute expected results. Error: {e.stderr.decode()}")
    finally:
        os.remove(tmp_path)

    assert os.path.isfile(expected_path), "Expected results file was not generated"

    with open(expected_path, "r") as f:
        expected_results = json.load(f)

    # Check keys
    for key in ["selected_features", "best_alpha", "best_cv_score"]:
        assert key in student_results, f"Missing '{key}' in results.json"

    # Check selected_features
    assert isinstance(student_results["selected_features"], list), "'selected_features' must be a list"
    assert student_results["selected_features"] == expected_results["selected_features"], \
        f"Selected features do not match. Expected {expected_results['selected_features']}, got {student_results['selected_features']}"

    # Check best_alpha
    try:
        student_alpha = float(student_results["best_alpha"])
    except ValueError:
        pytest.fail("'best_alpha' must be a float")
    assert student_alpha == expected_results["best_alpha"], \
        f"Best alpha does not match. Expected {expected_results['best_alpha']}, got {student_alpha}"

    # Check best_cv_score
    try:
        student_cv_score = round(float(student_results["best_cv_score"]), 4)
    except ValueError:
        pytest.fail("'best_cv_score' must be a float")
    assert student_cv_score == expected_results["best_cv_score"], \
        f"Best CV score does not match. Expected {expected_results['best_cv_score']}, got {student_cv_score}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
