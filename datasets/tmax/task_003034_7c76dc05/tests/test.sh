#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import sys
import tempfile
import pytest

@pytest.fixture(scope="module")
def expected_values():
    """
    Recomputes the expected values using the environment's installed libraries
    by executing a temporary script. This ensures we derive the truth dynamically
    without relying on hardcoded opaque constants, while strictly using stdlib in pytest.
    """
    script = """
import pandas as pd
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.linear_model import LogisticRegression

df = pd.read_csv('/home/user/data/dataset.csv')

vectorizer = TfidfVectorizer(max_features=50, stop_words='english')
X = vectorizer.fit_transform(df['text']).toarray()

valid_idx = df['target'].dropna().index
missing_idx = df[df['target'].isna()].index

X_valid = X[valid_idx]
y_valid = df.loc[valid_idx, 'target'].values

y_imputed = df['target'].copy()

for idx in missing_idx:
    sims = cosine_similarity([X[idx]], X_valid)[0]
    best_valid_idx_relative = np.argmax(sims)
    best_valid_idx_absolute = valid_idx[best_valid_idx_relative]
    y_imputed[idx] = df.loc[best_valid_idx_absolute, 'target']

corrs = []
for i in range(X.shape[1]):
    corr = np.corrcoef(X_valid[:, i], y_valid)[0, 1]
    corrs.append(corr)

best_feature = np.argmax(corrs)

model = LogisticRegression(random_state=42)
model.fit(X, y_imputed)

np.random.seed(42)
n_samples = len(df)
accuracies = []
for _ in range(1000):
    indices = np.random.choice(n_samples, size=n_samples, replace=True)
    X_sample = X[indices]
    y_sample = y_imputed.iloc[indices].values
    acc = model.score(X_sample, y_sample)
    accuracies.append(acc)

low = np.percentile(accuracies, 2.5)
high = np.percentile(accuracies, 97.5)

print(f"{best_feature}")
print(f"{low:.3f},{high:.3f}")
"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(script)
        script_path = f.name

    try:
        result = subprocess.run([sys.executable, script_path], capture_output=True, text=True, check=True)
        lines = result.stdout.strip().split('\n')
        return lines[0].strip(), lines[1].strip()
    finally:
        os.remove(script_path)

def test_most_correlated_feature(expected_values):
    """Validate the most correlated feature index output."""
    expected_feature, _ = expected_values
    file_path = '/home/user/most_correlated_feature.txt'

    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you write the output?"

    with open(file_path, 'r') as f:
        actual_feature = f.read().strip()

    assert actual_feature == expected_feature, (
        f"Incorrect most correlated feature index.\n"
        f"Expected: '{expected_feature}'\n"
        f"Actual: '{actual_feature}'"
    )

def test_bootstrap_ci(expected_values):
    """Validate the bootstrap confidence interval output."""
    _, expected_ci = expected_values
    file_path = '/home/user/bootstrap_ci.txt'

    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you write the output?"

    with open(file_path, 'r') as f:
        actual_ci = f.read().strip()

    assert actual_ci == expected_ci, (
        f"Incorrect bootstrap confidence interval.\n"
        f"Expected: '{expected_ci}'\n"
        f"Actual: '{actual_ci}'\n"
        f"Ensure you used the correct random seeds and bootstrap sampling logic."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
