#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import sqlite3
import subprocess

import pandas as pd
from sklearn.metrics import mean_squared_error


def test_batch_score_script_exists():
    script_path = "/home/user/batch_score.py"
    assert os.path.exists(script_path), f"Agent script {script_path} is missing."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."


def _derive_truth(input_csv):
    conn = sqlite3.connect("/app/datasets.db")
    try:
        rows = conn.execute("SELECT src, dst, cost FROM ds_links").fetchall()
    finally:
        conn.close()

    graph = {}
    for src, dst, cost in rows:
        graph.setdefault(src, []).append((dst, cost))

    def score(src, dst):
        queue = [(0.0, src)]
        distances = {src: 0.0}
        visited = set()
        while queue:
            distance, node = heapq.heappop(queue)
            if node == dst:
                return float(f"{1.0 / (1.0 + distance):.4f}")
            if node in visited:
                continue
            visited.add(node)
            for neighbor, weight in graph.get(node, []):
                if neighbor not in visited:
                    new_distance = distance + weight
                    if new_distance < distances.get(neighbor, float("inf")):
                        distances[neighbor] = new_distance
                        heapq.heappush(queue, (new_distance, neighbor))
        return 0.0

    pairs = pd.read_csv(input_csv, header=None, names=["A", "B"])
    return pd.DataFrame(
        [(int(row.A), int(row.B), score(int(row.A), int(row.B))) for row in pairs.itertuples()],
        columns=["A", "B", "score"],
    )


def test_batch_score_accuracy():
    script_path = "/home/user/batch_score.py"
    input_csv = "/app/hidden_test_pairs.csv"
    output_csv = "/home/user/predictions.csv"

    try:
        subprocess.run(
            ["python3", script_path, input_csv, output_csv],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        assert False, f"Agent script failed to run. Stderr: {e.stderr}"

    assert os.path.exists(output_csv), f"Output file {output_csv} was not created."

    try:
        preds = pd.read_csv(output_csv, header=None, names=["A", "B", "score"])
    except Exception as e:
        assert False, f"Failed to read output CSV {output_csv}: {e}"

    truth = _derive_truth(input_csv)

    # Merge to ensure alignment.
    merged = pd.merge(truth, preds, on=["A", "B"], suffixes=("_true", "_pred"))

    assert len(merged) == len(truth), (
        f"Output CSV does not contain all expected pairs. Expected {len(truth)}, "
        f"found {len(merged)} matching pairs."
    )

    mse = mean_squared_error(merged["score_true"], merged["score_pred"])

    threshold = 0.001
    assert mse < threshold, f"MSE {mse:.6f} is not less than the threshold {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
