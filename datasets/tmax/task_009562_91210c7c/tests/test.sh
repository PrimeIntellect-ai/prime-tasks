#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
import torch
import torch.nn as nn
import torch.nn.functional as F

WORKSPACE_DIR = "/home/user/workspace"
RAW_DATA_PATH = os.path.join(WORKSPACE_DIR, "raw_data.csv")
SCHEMA_PATH = os.path.join(WORKSPACE_DIR, "schema.json")
WEIGHTS_PATH = os.path.join(WORKSPACE_DIR, "model_weights.pth")
SUMMARY_PATH = os.path.join(WORKSPACE_DIR, "summary.txt")
CLEANED_DATA_PATH = os.path.join(WORKSPACE_DIR, "cleaned_data.csv")
PREDICTIONS_PATH = os.path.join(WORKSPACE_DIR, "predictions.csv")
MODEL_PATH = os.path.join(WORKSPACE_DIR, "model.py")
INFER_PATH = os.path.join(WORKSPACE_DIR, "infer.py")


def expected_cleaned_data():
    import json
    with open(SCHEMA_PATH, "r") as f:
        schema = json.load(f)

    features = schema["features"]
    minimum = float(schema["constraints"]["min"])
    maximum = float(schema["constraints"]["max"])

    raw = pd.read_csv(RAW_DATA_PATH)
    assert list(raw.columns) == features, "raw_data.csv does not match schema features"
    clean = raw.apply(pd.to_numeric, errors="coerce").dropna()
    clean = clean[(clean >= minimum).all(axis=1) & (clean <= maximum).all(axis=1)]
    return clean.reset_index(drop=True)


def load_state_dict():
    try:
        return torch.load(WEIGHTS_PATH, map_location="cpu", weights_only=True)
    except TypeError:
        return torch.load(WEIGHTS_PATH, map_location="cpu")


def expected_predictions(clean):
    state = load_state_dict()
    required = {"fc1.weight", "fc1.bias", "fc2.weight", "fc2.bias"}
    assert set(state.keys()) == required, f"Unexpected state_dict keys: {set(state.keys())}"
    x = torch.tensor(clean.to_numpy(), dtype=torch.float32)
    with torch.no_grad():
        hidden = F.relu(F.linear(x, state["fc1.weight"], state["fc1.bias"]))
        output = F.linear(hidden, state["fc2.weight"], state["fc2.bias"])
    return output.detach().cpu().numpy().reshape(-1)


@pytest.fixture(scope="session", autouse=True)
def execute_inference_script():
    assert os.path.isfile(INFER_PATH), f"Required file missing: {INFER_PATH}"
    if os.path.exists(PREDICTIONS_PATH):
        os.remove(PREDICTIONS_PATH)
    result = subprocess.run(
        [sys.executable, INFER_PATH],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"infer.py failed:\n{result.stdout}"
    assert os.path.isfile(PREDICTIONS_PATH), "infer.py did not create predictions.csv"


def test_required_files_exist():
    """Ensure all required output scripts and files exist."""
    missing_files = []
    for path in [CLEANED_DATA_PATH, PREDICTIONS_PATH, SUMMARY_PATH, MODEL_PATH, INFER_PATH]:
        if not os.path.isfile(path):
            missing_files.append(path)
    assert not missing_files, f"The following required files are missing: {', '.join(missing_files)}"


def test_cleaned_data_format_and_values():
    """Ensure cleaned_data.csv has the required header, rows, and values."""
    expected = expected_cleaned_data()

    with open(CLEANED_DATA_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, "cleaned_data.csv is empty."
    assert lines[0] == "f1,f2,f3,f4,f5", f"Unexpected cleaned_data.csv header: {lines[0]}"
    assert len(lines) - 1 == len(expected), (
        f"cleaned_data.csv row count mismatch. Expected {len(expected)}, got {len(lines) - 1}"
    )

    actual = pd.read_csv(CLEANED_DATA_PATH)
    assert list(actual.columns) == list(expected.columns)
    assert actual.shape == expected.shape
    assert np.isfinite(actual.to_numpy(dtype=float)).all()
    np.testing.assert_allclose(
        actual.to_numpy(dtype=float), expected.to_numpy(dtype=float), rtol=0, atol=1e-12
    )


def test_reconstructed_model_loads_strictly_and_computes_expected_output():
    """Load an nn.Module defined by model.py strictly and verify its forward computation."""
    spec = importlib.util.spec_from_file_location("submitted_model", MODEL_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    candidates = []
    for value in vars(module).values():
        if isinstance(value, type) and issubclass(value, nn.Module) and value is not nn.Module:
            if value.__module__ == module.__name__:
                candidates.append(value)

    assert candidates, "model.py does not define a torch.nn.Module subclass"
    state = load_state_dict()
    clean = expected_cleaned_data()
    x = torch.tensor(clean.to_numpy(), dtype=torch.float32)
    expected = expected_predictions(clean)

    errors = []
    for cls in candidates:
        try:
            model = cls()
            model.load_state_dict(state, strict=True)
            model.eval()
            with torch.no_grad():
                actual = model(x).detach().cpu().numpy().reshape(-1)
            assert actual.shape == expected.shape
            np.testing.assert_allclose(actual, expected, rtol=1e-6, atol=1e-6)
            return
        except Exception as exc:
            errors.append(f"{cls.__name__}: {exc}")
    pytest.fail("No model class loaded the state_dict strictly and produced correct outputs: " + "; ".join(errors))


def test_predictions_format_and_values():
    """Ensure infer.py generated the exact predictions for every cleaned row."""
    expected = expected_predictions(expected_cleaned_data())

    with open(PREDICTIONS_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, "predictions.csv is empty."
    assert lines[0] == "prediction", f"Expected header 'prediction', got '{lines[0]}'"
    assert len(lines) - 1 == len(expected), (
        f"predictions.csv row count mismatch. Expected {len(expected)}, got {len(lines) - 1}"
    )

    predictions = pd.read_csv(PREDICTIONS_PATH)
    assert list(predictions.columns) == ["prediction"]
    actual = pd.to_numeric(predictions["prediction"], errors="coerce").to_numpy(dtype=float)
    assert np.isfinite(actual).all(), "predictions.csv contains non-numeric or non-finite values"
    np.testing.assert_allclose(actual, expected, rtol=1e-6, atol=1e-6)


def test_summary_contents():
    """Validate summary.txt from independently derived cleaned data and predictions."""
    expected_clean = expected_cleaned_data()
    expected_preds = expected_predictions(expected_clean)
    expected_valid_rows = len(expected_clean)
    expected_sum_preds = round(float(np.sum(expected_preds)), 4)

    with open(SUMMARY_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in summary.txt, found {len(lines)}"
    assert lines[0].startswith("VALID_ROWS:"), "First line must start with 'VALID_ROWS:'"
    assert lines[1].startswith("SUM_PREDICTIONS:"), "Second line must start with 'SUM_PREDICTIONS:'"

    try:
        actual_valid_rows = int(lines[0].split(":", 1)[1].strip())
    except ValueError:
        pytest.fail("Could not parse integer from VALID_ROWS line.")
    try:
        actual_sum_preds = float(lines[1].split(":", 1)[1].strip())
    except ValueError:
        pytest.fail("Could not parse float from SUM_PREDICTIONS line.")

    assert actual_valid_rows == expected_valid_rows, (
        f"VALID_ROWS mismatch. Expected {expected_valid_rows}, got {actual_valid_rows}"
    )
    assert abs(actual_sum_preds - expected_sum_preds) < 1e-4, (
        f"SUM_PREDICTIONS mismatch. Expected {expected_sum_preds}, got {actual_sum_preds}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
