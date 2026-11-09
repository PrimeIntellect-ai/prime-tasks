#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os

import pandas as pd
import pytest
import torch
from scipy.stats import ttest_ind

SUMMARY_PATH = '/home/user/experiment_summary.json'
EXPERIMENTS_PATH = '/home/user/experiments.csv'


def test_experiment_summary_exists():
    """Test that the experiment_summary.json file exists."""
    assert os.path.exists(SUMMARY_PATH), f"File {SUMMARY_PATH} is missing."
    assert os.path.isfile(SUMMARY_PATH), f"Path {SUMMARY_PATH} is not a file."


def test_experiment_summary_contents():
    """Validate the summary against calculations derived from experiments.csv."""
    with open(SUMMARY_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {SUMMARY_PATH} is not valid JSON.")

    expected_keys = {"best_num_layers", "best_hidden_size", "p_value", "inference_sum"}
    actual_keys = set(data.keys())

    # Preserve the original key assertion and enforce the instruction's exact-key requirement.
    assert expected_keys.issubset(actual_keys), (
        f"Missing keys in JSON. Expected {expected_keys}, got {actual_keys}."
    )
    assert actual_keys == expected_keys, (
        f"JSON must contain exactly {expected_keys}, got {actual_keys}."
    )

    assert type(data["best_num_layers"]) is int, "best_num_layers must be an integer."
    assert type(data["best_hidden_size"]) is int, "best_hidden_size must be an integer."
    assert type(data["p_value"]) is float, "p_value must be a float."
    assert type(data["inference_sum"]) is float, "inference_sum must be a float."

    assert os.path.isfile(EXPERIMENTS_PATH), f"File {EXPERIMENTS_PATH} is missing."
    df = pd.read_csv(EXPERIMENTS_PATH)
    required_columns = {"num_layers", "hidden_size", "accuracy"}
    assert required_columns.issubset(df.columns), (
        f"experiments.csv is missing required columns: {required_columns - set(df.columns)}"
    )

    means = df.groupby(["num_layers", "hidden_size"])["accuracy"].mean()
    best_num_layers, best_hidden_size = means.idxmax()
    best_num_layers = int(best_num_layers)
    best_hidden_size = int(best_hidden_size)

    best_accuracies = df.loc[
        (df["num_layers"] == best_num_layers)
        & (df["hidden_size"] == best_hidden_size),
        "accuracy",
    ].to_numpy()
    baseline_accuracies = df.loc[
        (df["num_layers"] == 2) & (df["hidden_size"] == 64),
        "accuracy",
    ].to_numpy()
    assert len(best_accuracies) > 1, "Best configuration needs at least two runs."
    assert len(baseline_accuracies) > 1, "Baseline configuration needs at least two runs."
    expected_p_value = float(ttest_ind(
        best_accuracies, baseline_accuracies, equal_var=False
    ).pvalue)

    layers = []
    input_dim = 10
    for _ in range(best_num_layers - 1):
        layers.append(torch.nn.Linear(input_dim, best_hidden_size))
        layers.append(torch.nn.ReLU())
        input_dim = best_hidden_size
    layers.append(torch.nn.Linear(input_dim, 2))
    model = torch.nn.Sequential(*layers)

    with torch.no_grad():
        for module in model.modules():
            if isinstance(module, torch.nn.Linear):
                module.weight.fill_(0.01)
                module.bias.fill_(0.0)
        expected_inference_sum = float(model(torch.ones((1, 10))).sum().item())

    # Preserve the original assertions.
    assert data["best_num_layers"] == 3, (
        f"Expected best_num_layers to be 3, got {data['best_num_layers']}."
    )
    assert data["best_hidden_size"] == 128, (
        f"Expected best_hidden_size to be 128, got {data['best_hidden_size']}."
    )
    assert isinstance(data["p_value"], (int, float)), "p_value must be a float."
    assert round(data["p_value"], 4) == 0.0019, (
        f"Expected p_value to be 0.0019, got {data['p_value']}."
    )
    assert isinstance(data["inference_sum"], (int, float)), "inference_sum must be a float."
    assert round(data["inference_sum"], 4) == 0.3277, (
        f"Expected inference_sum to be 0.3277, got {data['inference_sum']}."
    )

    # Derive and verify every reported result from the supplied experiment data and
    # an independently reconstructed PyTorch model.
    assert data["best_num_layers"] == best_num_layers
    assert data["best_hidden_size"] == best_hidden_size
    assert data["p_value"] == round(expected_p_value, 4), (
        f"p_value does not match Welch's t-test result {round(expected_p_value, 4)}."
    )
    assert data["inference_sum"] == round(expected_inference_sum, 4), (
        f"inference_sum does not match reconstructed-model result "
        f"{round(expected_inference_sum, 4)}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
