#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import pytest

def get_expected_values():
    """
    Dynamically compute the expected values using the environment's libraries
    via a subprocess to adhere to the stdlib-only constraint for the test file.
    """
    script = """
import numpy as np
from scipy.spatial.distance import jensenshannon
from scipy.stats import ttest_ind
from sklearn.linear_model import LogisticRegression

# Load data
X_train = np.load('/home/user/kmer_train.npy')
y_train = np.load('/home/user/labels_train.npy')
X_test = np.load('/home/user/kmer_test.npy')
y_test = np.load('/home/user/labels_test.npy')

# Normalization
X_train_norm = X_train / X_train.sum(axis=1, keepdims=True)
X_test_norm = X_test / X_test.sum(axis=1, keepdims=True)

# Jensen-Shannon distance
mean_0 = X_train_norm[y_train == 0].mean(axis=0)
mean_1 = X_train_norm[y_train == 1].mean(axis=0)
js_dist = jensenshannon(mean_0, mean_1)
expected_js_dist = f"{js_dist:.4f}"

# Dimensionality Reduction
mean_train = X_train_norm.mean(axis=0)
X_train_centered = X_train_norm - mean_train
U, S, Vt = np.linalg.svd(X_train_centered, full_matrices=False)
V_top5 = Vt[:5, :]
X_train_proj = X_train_centered @ V_top5.T

# Modeling
clf = LogisticRegression(random_state=42)
clf.fit(X_train_proj, y_train)

# Prediction & Statistical Comparison
X_test_centered = X_test_norm - mean_train
X_test_proj = X_test_centered @ V_top5.T
probs = clf.predict_proba(X_test_proj)[:, 1]

probs_0 = probs[y_test == 0]
probs_1 = probs[y_test == 1]
t_stat, p_val = ttest_ind(probs_1, probs_0, equal_var=False)
expected_p_val = f"{p_val:.2e}"

print(expected_js_dist)
print(expected_p_val)
"""
    try:
        output = subprocess.check_output([sys.executable, "-c", script], text=True)
        return output.strip().split('\n')
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute expected values: {e}")

@pytest.fixture(scope="module")
def expected_results():
    return get_expected_values()

def test_js_distance_file(expected_results):
    js_file = '/home/user/js_distance.txt'
    assert os.path.exists(js_file), f"Required output file is missing: {js_file}"
    assert os.path.isfile(js_file), f"Path exists but is not a file: {js_file}"

    with open(js_file, 'r') as f:
        agent_js = f.read().strip()

    expected_js = expected_results[0]
    assert agent_js == expected_js, f"Jensen-Shannon distance is incorrect. Expected '{expected_js}', but got '{agent_js}'."

def test_ttest_pvalue_file(expected_results):
    pval_file = '/home/user/ttest_pvalue.txt'
    assert os.path.exists(pval_file), f"Required output file is missing: {pval_file}"
    assert os.path.isfile(pval_file), f"Path exists but is not a file: {pval_file}"

    with open(pval_file, 'r') as f:
        agent_pval = f.read().strip()

    expected_pval = expected_results[1]
    assert agent_pval == expected_pval, f"T-test p-value is incorrect. Expected '{expected_pval}', but got '{agent_pval}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
