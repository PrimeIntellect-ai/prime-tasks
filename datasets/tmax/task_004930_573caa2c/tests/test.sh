#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

import networkx as nx
import pandas as pd
import pytest
from sklearn.metrics import mean_squared_error

SCRIPT_PATH = "/home/user/process_network.py"
PRED_PATH = "/home/user/final_metrics.json"
CSV_PATH = "/home/user/data/transactions.csv"


def test_process_network_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist. You must create it to automate the pipeline."


@pytest.fixture(scope="module")
def generated_output():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

    if os.path.exists(PRED_PATH):
        os.remove(PRED_PATH)

    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process_network.py did not finish within 300 seconds.")

    assert result.returncode == 0, (
        f"process_network.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    return PRED_PATH


def test_final_metrics_json_exists(generated_output):
    assert os.path.isfile(PRED_PATH), f"The output file {PRED_PATH} does not exist."


def test_final_metrics_accuracy(generated_output):
    assert os.path.isfile(PRED_PATH), f"Missing predictions file at {PRED_PATH}"

    with open(PRED_PATH, "r") as f:
        try:
            pred = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {PRED_PATH} is not valid JSON.")

    df = pd.read_csv(CSV_PATH)
    filtered = df[
        (df["tx_type"] == "international_transfer")
        & (df["amount"] > 500)
    ]
    agg = filtered.groupby(["sender_id", "receiver_id"], as_index=False)["amount"].sum()

    graph = nx.DiGraph()
    for row in agg.itertuples(index=False):
        graph.add_edge(row.sender_id, row.receiver_id, weight=float(row.amount))
    truth = nx.pagerank(graph, alpha=0.85, weight="weight")

    common_keys = set(pred.keys()).intersection(set(truth.keys()))

    assert len(truth) > 0, "Ground truth JSON is empty."

    coverage = len(common_keys) / len(truth)
    assert coverage >= 0.9, f"Missing too many keys. Found {len(common_keys)} out of {len(truth)} expected keys (coverage: {coverage:.2%})."

    y_true = [truth[k] for k in common_keys]
    y_pred = [pred[k] for k in common_keys]

    mse = mean_squared_error(y_true, y_pred)
    threshold = 0.0001

    assert mse <= threshold, f"Calculated MSE {mse:.6f} is greater than the threshold {threshold}. Your graph metrics are not accurate enough."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
