#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
import pytest


def test_go_program_generates_output():
    source_path = "/app/reduce.go"
    output_path = "/app/reduced.csv"

    assert os.path.exists(source_path), f"Missing required Go program: {source_path}"
    assert os.path.isfile(source_path), f"Path is not a file: {source_path}"
    assert os.path.getsize(source_path) > 0, f"Go program is empty: {source_path}"

    if os.path.lexists(output_path):
        os.remove(output_path)

    try:
        result = subprocess.run(
            ["go", "run", source_path],
            cwd="/app",
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Go program timed out")

    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(output_path), "Go program did not generate /app/reduced.csv"


def test_reduced_csv_exists():
    path = "/app/reduced.csv"
    assert os.path.exists(path), f"Missing required output file: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"
    assert os.path.getsize(path) > 0, f"File is empty: {path}"


def test_pca_projection_metric():
    agent_path = "/app/reduced.csv"
    data_path = "/app/data.csv"

    assert os.path.exists(agent_path), f"Missing output file: {agent_path}"
    assert os.path.exists(data_path), f"Missing input file: {data_path}"

    # Compute reference
    data = pd.read_csv(data_path, header=None).values
    # MaxAbs scaling
    scaled_data = data / np.max(np.abs(data), axis=0)

    # PCA
    pca = PCA(n_components=3)
    ref = pca.fit_transform(scaled_data)

    # Read agent output
    try:
        agent = np.loadtxt(agent_path, delimiter=',')
    except Exception as e:
        pytest.fail(f"Failed to load agent output as CSV: {e}")

    assert ref.shape == agent.shape, f"Shape mismatch: expected {ref.shape}, got {agent.shape}"

    diffs = []
    for i in range(ref.shape[1]):
        col_ref = ref[:, i]
        col_agent = agent[:, i]
        diff_pos = np.max(np.abs(col_ref - col_agent))
        diff_neg = np.max(np.abs(col_ref - (-col_agent)))
        diffs.append(min(diff_pos, diff_neg))

    max_diff = max(diffs)
    threshold = 1e-4

    assert max_diff <= threshold, f"Maximum absolute difference {max_diff} exceeds threshold {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
