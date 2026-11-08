#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import subprocess
import numpy as np
import pytest

def test_centroid_mse():
    # 1. Read dataset
    dataset_path = '/app/dataset.csv'
    assert os.path.exists(dataset_path), f"Dataset missing at {dataset_path}"

    texts = []
    with open(dataset_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            texts.append(row[1])

    # 2. Get embeddings using the embedder
    embedder_path = '/app/embedder'
    assert os.path.exists(embedder_path), f"Embedder missing at {embedder_path}"

    embeddings = []
    for text in texts:
        result = subprocess.run([embedder_path, text], capture_output=True, text=True, check=True)
        vec = [float(x) for x in result.stdout.strip().split(',')]
        embeddings.append(vec)

    embeddings = np.array(embeddings)

    # 3. Compute distances and find anomalies
    n = len(embeddings)
    clean_indices = []
    for i in range(n):
        diffs = embeddings - embeddings[i]
        dists = np.linalg.norm(diffs, axis=1)
        # Sort distances
        sorted_dists = np.sort(dists)
        # 5th nearest neighbor is index 4 (0 is itself)
        if sorted_dists[4] <= 2.5:
            clean_indices.append(i)

    assert len(clean_indices) > 0, "No clean records found in truth calculation."

    # 4. Compute truth centroid
    clean_embeddings = embeddings[clean_indices]
    truth_centroid = np.mean(clean_embeddings, axis=0)

    # 5. Read prediction
    pred_path = '/app/output_centroid.txt'
    assert os.path.exists(pred_path), f"Output missing at {pred_path}"

    with open(pred_path, 'r') as f:
        content = f.read().strip()

    try:
        pred_centroid = np.array([float(x) for x in content.split(',')])
    except ValueError:
        pytest.fail(f"Could not parse floats from {pred_path}")

    assert len(pred_centroid) == 16, f"Expected 16 dimensions, got {len(pred_centroid)}"

    # 6. Compute MSE
    mse = np.mean((pred_centroid - truth_centroid)**2)

    assert mse <= 0.0001, f"MSE {mse:.6f} is greater than threshold 0.0001"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
