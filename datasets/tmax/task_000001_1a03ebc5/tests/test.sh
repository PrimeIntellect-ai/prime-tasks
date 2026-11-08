#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import sys

def get_expected_output():
    """
    Since we are restricted to the standard library in the test code, but the 
    environment has pandas, numpy, sklearn, and scipy installed (as required 
    by the task setup and verification), we can dynamically compute the expected 
    values by invoking a short Python script.
    """
    script = """
import pandas as pd
import numpy as np
from sklearn.decomposition import PCA
from scipy.spatial.distance import cdist

df = pd.read_csv("/home/user/data.csv")

# 1. Correlation
corr = df[["f1", "f2", "f3", "f4", "f5"]].corr().abs()
np.fill_diagonal(corr.values, 0)
max_idx = np.unravel_index(np.argmax(corr.values), corr.shape)
pair = sorted([corr.columns[max_idx[0]], corr.columns[max_idx[1]]])
expected_pair = f"{pair[0]}, {pair[1]}"

# 2 & 3. PCA and Similarity
pca = PCA(n_components=2)
coords = pca.fit_transform(df[["f1", "f2", "f3", "f4", "f5"]])
dists = cdist([coords[0]], coords)[0]
dists[0] = np.inf # ignore item_0 itself
closest_item = df.iloc[np.argmin(dists)]["id"]

print(f"Highest correlated pair: {expected_pair}")
print(f"Closest item to item_0: {closest_item}")
"""
    result = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True,
        check=True
    )
    return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]

def test_answer_file_exists():
    assert os.path.exists("/home/user/answer.txt"), "/home/user/answer.txt does not exist."

def test_answer_file_content():
    answer_file = "/home/user/answer.txt"
    assert os.path.exists(answer_file), f"File {answer_file} is missing."

    with open(answer_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"{answer_file} does not contain enough lines. Expected 2, got {len(lines)}."

    expected_lines = get_expected_output()

    assert lines[0] == expected_lines[0], f"Line 1 mismatch. Expected '{expected_lines[0]}', got '{lines[0]}'."
    assert lines[1] == expected_lines[1], f"Line 2 mismatch. Expected '{expected_lines[1]}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
