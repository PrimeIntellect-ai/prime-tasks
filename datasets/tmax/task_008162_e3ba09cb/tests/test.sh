#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os

import pandas as pd
import pytest
import torch
import torch.nn as nn
from scipy.stats import binomtest

REPORT_PATH = "/home/user/report.json"
MODEL_DEF_PATH = "/home/user/model_def.py"
WEIGHTS_PATH = "/home/user/model_weights.pth"
DATA_PATH = "/home/user/data.csv"


def load_weights():
    try:
        return torch.load(WEIGHTS_PATH, map_location="cpu", weights_only=True)
    except TypeError:
        return torch.load(WEIGHTS_PATH, map_location="cpu")


def test_report_json_exists_and_correct():
    """Test that report.json exists and contains the correct values."""
    assert os.path.isfile(REPORT_PATH), f"Missing report file: {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    expected_keys = {"hidden_size", "positive_count", "p_value"}
    assert set(report.keys()) == expected_keys, (
        f"report.json keys mismatch. Expected {expected_keys}, got {set(report.keys())}"
    )

    assert report["hidden_size"] == 8, f"Expected hidden_size to be 8, got {report['hidden_size']}"
    assert report["positive_count"] == 43, f"Expected positive_count to be 43, got {report['positive_count']}"

    # Preserve the original expected-value assertion and tolerance.
    assert abs(report["p_value"] - 0.1933) < 1e-4, (
        f"Expected p_value to be ~0.1933, got {report['p_value']}"
    )


def test_model_def_fixed_and_executable():
    """Import the repaired model, strictly load its weights, and exercise inference."""
    assert os.path.isfile(MODEL_DEF_PATH), f"Missing {MODEL_DEF_PATH}"

    with open(MODEL_DEF_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "class SimpleMLP" in content, "model_def.py does not contain the SimpleMLP class."
    assert "nn.Linear(3, 8)" in content, (
        "model_def.py does not contain the corrected hidden size (8) for fc1."
    )
    assert "nn.Linear(8, 1)" in content, (
        "model_def.py does not contain the corrected hidden size (8) for fc2."
    )

    state = load_weights()
    assert isinstance(state, dict), "model_weights.pth does not contain a state dictionary."
    expected_state_keys = {"fc1.weight", "fc1.bias", "fc2.weight", "fc2.bias"}
    assert set(state.keys()) == expected_state_keys

    spec = importlib.util.spec_from_file_location("submitted_model_def", MODEL_DEF_PATH)
    assert spec is not None and spec.loader is not None, "Could not load model_def.py."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    assert hasattr(module, "SimpleMLP"), "model_def.py does not define SimpleMLP."
    model = module.SimpleMLP()
    assert isinstance(model, nn.Module), "SimpleMLP must be a torch.nn.Module."
    assert isinstance(model.fc1, nn.Linear), "SimpleMLP.fc1 must be nn.Linear."
    assert model.fc1.in_features == 3 and model.fc1.out_features == 8
    assert isinstance(model.fc2, nn.Linear), "SimpleMLP.fc2 must be nn.Linear."
    assert model.fc2.in_features == 8 and model.fc2.out_features == 1

    result = model.load_state_dict(state, strict=True)
    assert not result.missing_keys and not result.unexpected_keys
    loaded_state = model.state_dict()
    assert set(loaded_state.keys()) == expected_state_keys
    for key in expected_state_keys:
        assert torch.equal(loaded_state[key].detach().cpu(), state[key].detach().cpu()), (
            f"Parameter {key} was not loaded from model_weights.pth."
        )

    data = pd.read_csv(DATA_PATH)
    assert list(data.columns) == ["f1", "f2", "f3"]
    assert len(data) == 100
    inputs = torch.tensor(data[["f1", "f2", "f3"]].to_numpy(), dtype=torch.float32)

    model.eval()
    assert not model.training
    with torch.no_grad():
        outputs = model(inputs)
        reference_outputs = torch.sigmoid(
            torch.relu(inputs @ state["fc1.weight"].T + state["fc1.bias"])
            @ state["fc2.weight"].T
            + state["fc2.bias"]
        )

    assert isinstance(outputs, torch.Tensor), "SimpleMLP.forward must return a tensor."
    assert outputs.shape == (100, 1), f"Expected output shape (100, 1), got {tuple(outputs.shape)}"
    assert torch.isfinite(outputs).all(), "Model outputs contain non-finite values."
    assert torch.allclose(outputs.detach().cpu(), reference_outputs.detach().cpu(), atol=1e-6, rtol=1e-6), (
        "SimpleMLP.forward does not implement the required Linear-ReLU-Linear-Sigmoid architecture."
    )

    predictions = (outputs > 0.5).to(torch.int64)
    positive_count = int(predictions.sum().item())
    expected_p_value = round(float(binomtest(positive_count, n=len(inputs), p=0.5, alternative="two-sided").pvalue), 4)

    with open(REPORT_PATH, "r") as f:
        report = json.load(f)
    assert report["hidden_size"] == state["fc1.weight"].shape[0]
    assert report["positive_count"] == positive_count
    assert report["p_value"] == expected_p_value
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
