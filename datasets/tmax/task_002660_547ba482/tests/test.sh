#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os

import numpy as np
from statsmodels.stats.proportion import proportions_ztest

EXPERIMENT_DIR = "/home/user/experiment"
OUTPUT_PATH = "/home/user/experiment_results.json"


def reconstruct_predictions(model_name, features):
    arch_path = os.path.join(EXPERIMENT_DIR, f"model_{model_name}_arch.json")
    weights_path = os.path.join(EXPERIMENT_DIR, f"model_{model_name}_weights.npz")

    with open(arch_path, "r") as f:
        architecture = json.load(f)

    activations = features.copy()
    linear_index = 0
    with np.load(weights_path) as weights:
        for layer in architecture["layers"]:
            layer_type = layer["type"]
            if layer_type == "linear":
                activations = (
                    activations @ weights[f"W{linear_index}"]
                    + weights[f"b{linear_index}"]
                )
                linear_index += 1
            elif layer_type == "relu":
                activations = np.maximum(0, activations)
            elif layer_type == "sigmoid":
                activations = 1.0 / (1.0 + np.exp(-activations))
            else:
                raise AssertionError(f"Unsupported layer type in artifact: {layer_type}")

    return (np.asarray(activations).reshape(-1) >= 0.5).astype(int)


def expected_results():
    ids = []
    rows = []
    with open(os.path.join(EXPERIMENT_DIR, "val_features.csv"), newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ids.append(row["id"])
            rows.append([float(row["f1"]), float(row["f2"]), float(row["f3"])])

    with open(os.path.join(EXPERIMENT_DIR, "val_labels.json"), "r") as f:
        labels_by_id = json.load(f)

    features = np.asarray(rows, dtype=float)
    labels = np.asarray([int(labels_by_id[row_id]) for row_id in ids], dtype=int)
    pred_A = reconstruct_predictions("A", features)
    pred_B = reconstruct_predictions("B", features)

    correct_A = int(np.sum(pred_A == labels))
    correct_B = int(np.sum(pred_B == labels))
    total = len(labels)
    _, p_value = proportions_ztest([correct_A, correct_B], [total, total])

    return {
        "total": total,
        "correct_A": correct_A,
        "correct_B": correct_B,
        "accuracy_A": round(correct_A / total, 4),
        "accuracy_B": round(correct_B / total, 4),
        "p_value": round(float(p_value), 4),
    }


def test_experiment_results_exist():
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} is missing."


def test_experiment_results_format_and_values():
    with open(OUTPUT_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {OUTPUT_PATH} is not valid JSON."

    expected = expected_results()

    # Check keys
    expected_keys = {"accuracy_A", "accuracy_B", "p_value_ztest", "bayesian_posterior"}
    assert set(results.keys()) == expected_keys, f"JSON keys do not match expected. Found: {list(results.keys())}"

    # Check Model A deterministic values
    assert math.isclose(results["accuracy_A"], 0.8000, abs_tol=1e-4), \
        f"accuracy_A should be exactly 0.8000, got {results['accuracy_A']}"
    assert results["accuracy_A"] == expected["accuracy_A"], \
        f"accuracy_A should be {expected['accuracy_A']}, got {results['accuracy_A']}"

    posterior = results["bayesian_posterior"]
    assert "model_A" in posterior and "model_B" in posterior, "bayesian_posterior missing model_A or model_B"

    model_A_post = posterior["model_A"]
    assert model_A_post.get("alpha") == 161, f"model_A alpha should be 161, got {model_A_post.get('alpha')}"
    assert model_A_post.get("beta") == 41, f"model_A beta should be 41, got {model_A_post.get('beta')}"

    # Check Model B structural invariants (N=200, uniform prior alpha=1, beta=1)
    model_B_post = posterior["model_B"]
    alpha_B = model_B_post.get("alpha")
    beta_B = model_B_post.get("beta")

    assert isinstance(alpha_B, int) and isinstance(beta_B, int), "Model B alpha and beta must be integers"
    assert alpha_B + beta_B == 202, f"Model B alpha + beta should equal 202 (200 samples + 2 prior), got {alpha_B + beta_B}"

    expected_acc_B = (alpha_B - 1) / 200.0
    assert math.isclose(results["accuracy_B"], expected_acc_B, abs_tol=1e-4), \
        f"accuracy_B ({results['accuracy_B']}) does not match the derived accuracy from alpha ({expected_acc_B})"

    # Exact Model B values independently reconstructed from the supplied artifacts.
    assert alpha_B == expected["correct_B"] + 1, \
        f"model_B alpha should be {expected['correct_B'] + 1}, got {alpha_B}"
    assert beta_B == expected["total"] - expected["correct_B"] + 1, \
        f"model_B beta should be {expected['total'] - expected['correct_B'] + 1}, got {beta_B}"
    assert results["accuracy_B"] == expected["accuracy_B"], \
        f"accuracy_B should be {expected['accuracy_B']}, got {results['accuracy_B']}"

    # Check p-value
    p_val = results["p_value_ztest"]
    assert isinstance(p_val, (float, int)), "p_value_ztest must be a number"
    assert 0.0 <= p_val <= 1.0, f"p_value_ztest must be between 0 and 1, got {p_val}"
    assert p_val == expected["p_value"], \
        f"p_value_ztest should be {expected['p_value']}, got {p_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
