#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import importlib.util
import numpy as np
import pandas as pd
import pytest
import torch
import torch.nn as nn
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold

DATASET = "/home/user/dataset.csv"
CLEANED = "/home/user/cleaned_dataset.csv"
SUMMARY = "/home/user/summary.json"
MODEL_FILE = "/home/user/model.py"
WEIGHTS = "/home/user/weights.pth"


def read_csv(filepath):
    with open(filepath, 'r', newline='') as f:
        reader = csv.DictReader(f)
        return list(reader)


class ReferenceMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(3, 16)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 8)
        self.fc3 = nn.Linear(8, 1)

    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.relu(self.fc2(x))
        return self.fc3(x)


def canonical_inputs():
    np.random.seed(42)
    n_samples = 500
    x1 = np.random.normal(0, 1, n_samples)
    x2 = np.random.normal(2, 1.5, n_samples)
    x3 = np.random.normal(-1, 0.5, n_samples)
    target = 3.0 * x1 + 1.5 * x2 - 2.0 * x3 + 5.0 + np.random.normal(0, 1, n_samples)

    nan_indices = np.random.choice(n_samples, 40, replace=False)
    target_with_nans = target.copy()
    target_with_nans[nan_indices] = np.nan
    anomaly_indices = np.random.choice(
        [i for i in range(n_samples) if i not in nan_indices], 30, replace=False
    )
    target_with_nans[anomaly_indices] = -5.0 - np.random.uniform(1, 5, 30)
    valid_mask = (target_with_nans >= 0) | np.isnan(target_with_nans)
    target_with_nans[~valid_mask] = -10.0

    frame = pd.DataFrame({
        'x1': x1,
        'x2': x2,
        'x3': x3,
        'target': target_with_nans,
    })

    torch.manual_seed(42)
    reference_model = ReferenceMLP()
    return frame, reference_model


def load_state(path):
    try:
        return torch.load(path, map_location='cpu', weights_only=True)
    except TypeError:
        return torch.load(path, map_location='cpu')


def expected_results():
    original, reference_model = canonical_inputs()
    features = original[['x1', 'x2', 'x3']].to_numpy(dtype=np.float32)
    targets = original['target'].to_numpy(dtype=float).copy()
    nan_mask = np.isnan(targets)

    reference_model.eval()
    with torch.no_grad():
        predictions = reference_model(torch.tensor(features, dtype=torch.float32)).cpu().numpy().reshape(-1)
    targets[nan_mask] = predictions[nan_mask]

    anomaly_mask = targets < 0
    clean_mask = ~anomaly_mask
    alphas = [0.1, 1.0, 10.0]
    candidates = []

    # Both ordinary five-fold CV and the explicitly reproducible shuffled form
    # permitted by the instruction are accepted.
    cv_options = [
        5,
        KFold(n_splits=5, shuffle=True, random_state=42),
    ]
    for cv in cv_options:
        search = GridSearchCV(Ridge(), {'alpha': alphas}, cv=cv)
        search.fit(features[clean_mask], targets[clean_mask])
        final_targets = targets.copy()
        final_targets[anomaly_mask] = search.best_estimator_.predict(features[anomaly_mask])
        candidates.append((float(search.best_params_['alpha']), final_targets))

    return original, reference_model, nan_mask, anomaly_mask, candidates


def test_cleaned_dataset_exists():
    assert os.path.isfile(CLEANED), "/home/user/cleaned_dataset.csv does not exist."


def test_summary_json_exists():
    assert os.path.isfile(SUMMARY), "/home/user/summary.json does not exist."


def test_cleaned_dataset_validity():
    cleaned_data = read_csv(CLEANED)

    for i, row in enumerate(cleaned_data):
        target_str = row.get('target', '')
        assert target_str.strip() != '', f"Row {i} in cleaned_dataset.csv has a missing target."
        assert target_str.lower() != 'nan', f"Row {i} in cleaned_dataset.csv has a NaN target."

        try:
            target_val = float(target_str)
        except ValueError:
            pytest.fail(f"Row {i} in cleaned_dataset.csv has non-numeric target: {target_str}")

        assert target_val >= 0, f"Row {i} in cleaned_dataset.csv has a negative target: {target_val}"


def test_summary_json_keys_and_values():
    with open(SUMMARY, "r") as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("summary.json is not a valid JSON file.")

    expected_keys = {"best_alpha", "imputed_nan_count", "replaced_anomaly_count", "final_target_mean"}
    assert set(summary.keys()) == expected_keys, f"summary.json keys do not match. Expected {expected_keys}, got {set(summary.keys())}"

    assert summary["best_alpha"] in [0.1, 1.0, 10.0], f"best_alpha must be one of [0.1, 1.0, 10.0], got {summary['best_alpha']}"

    orig_data = read_csv(DATASET)
    orig_nans = sum(1 for row in orig_data if row.get('target', '').strip() == '' or row.get('target', '').lower() == 'nan')
    assert summary["imputed_nan_count"] == orig_nans, f"imputed_nan_count should be {orig_nans}, got {summary['imputed_nan_count']}"

    cleaned_data = read_csv(CLEANED)
    targets = [float(row['target']) for row in cleaned_data]
    actual_mean = sum(targets) / len(targets)
    expected_mean_rounded = round(actual_mean, 4)
    assert round(summary["final_target_mean"], 4) == expected_mean_rounded, \
        f"final_target_mean should be {expected_mean_rounded}, got {summary['final_target_mean']}"

    assert isinstance(summary["replaced_anomaly_count"], int), "replaced_anomaly_count must be an integer."
    assert summary["replaced_anomaly_count"] > 0, "replaced_anomaly_count should be greater than 0."


def test_model_py_updated():
    with open(MODEL_FILE, "r") as f:
        content = f.read()

    assert "nn.Linear(3, 16)" in content or "nn.Linear(in_features=3, out_features=16)" in content, \
        "model.py does not seem to have the correct updated dimensions for fc1 (3 -> 16)."
    assert "nn.Linear(16, 8)" in content or "nn.Linear(in_features=16, out_features=8)" in content, \
        "model.py does not seem to have the correct updated dimensions for fc2 (16 -> 8)."
    assert "nn.Linear(8, 1)" in content or "nn.Linear(in_features=8, out_features=1)" in content, \
        "model.py does not seem to have the correct updated dimensions for fc3 (8 -> 1)."


def test_original_inputs_are_intact():
    expected_df, expected_model = canonical_inputs()
    actual_df = pd.read_csv(DATASET)
    assert list(actual_df.columns) == ['x1', 'x2', 'x3', 'target']
    assert actual_df.shape == expected_df.shape
    assert np.allclose(actual_df.to_numpy(dtype=float), expected_df.to_numpy(dtype=float), rtol=1e-12, atol=1e-12, equal_nan=True), \
        "The original dataset was modified."

    actual_state = load_state(WEIGHTS)
    expected_state = expected_model.state_dict()
    assert set(actual_state.keys()) == set(expected_state.keys()), "weights.pth has been modified."
    for key in expected_state:
        assert torch.equal(actual_state[key].cpu(), expected_state[key].cpu()), f"weights.pth tensor {key} has been modified."


def test_model_class_executes_with_saved_weights():
    spec = importlib.util.spec_from_file_location("submitted_model", MODEL_FILE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, 'SimpleMLP'), "model.py does not define SimpleMLP."

    model = module.SimpleMLP()
    assert isinstance(model.fc1, nn.Linear) and (model.fc1.in_features, model.fc1.out_features) == (3, 16)
    assert isinstance(model.fc2, nn.Linear) and (model.fc2.in_features, model.fc2.out_features) == (16, 8)
    assert isinstance(model.fc3, nn.Linear) and (model.fc3.in_features, model.fc3.out_features) == (8, 1)
    model.load_state_dict(load_state(WEIGHTS), strict=True)
    model.eval()

    original, reference_model = canonical_inputs()
    sample = torch.tensor(original[['x1', 'x2', 'x3']].to_numpy(dtype=np.float32), dtype=torch.float32)
    with torch.no_grad():
        actual = model(sample)
        expected = reference_model(sample)
    assert actual.shape == (len(original), 1)
    assert torch.allclose(actual, expected, rtol=1e-6, atol=1e-6), "SimpleMLP.forward does not implement the trained architecture."


def test_cleaned_rows_match_required_mlp_and_ridge_pipeline():
    original, _, nan_mask, anomaly_mask, candidates = expected_results()
    cleaned = pd.read_csv(CLEANED)
    assert list(cleaned.columns) == list(original.columns), "The original column order was not maintained."
    assert cleaned.shape == original.shape, "The cleaned dataset must contain exactly the original rows."

    assert np.allclose(
        cleaned[['x1', 'x2', 'x3']].to_numpy(dtype=float),
        original[['x1', 'x2', 'x3']].to_numpy(dtype=float),
        rtol=1e-12,
        atol=1e-12,
    ), "Feature values or row order differ from the original dataset."

    actual_targets = cleaned['target'].to_numpy(dtype=float)
    assert np.isfinite(actual_targets).all(), "All final targets must be finite."

    with open(SUMMARY, 'r') as f:
        summary = json.load(f)

    matching = [
        expected_targets for alpha, expected_targets in candidates
        if float(summary['best_alpha']) == alpha
        and np.allclose(actual_targets, expected_targets, rtol=1e-6, atol=1e-5)
    ]
    assert matching, "Cleaned targets do not match MLP imputation followed by the required Ridge/GridSearchCV replacement."

    assert summary['imputed_nan_count'] == int(nan_mask.sum())
    assert summary['replaced_anomaly_count'] == int(anomaly_mask.sum())
    assert summary['final_target_mean'] == round(float(actual_targets.mean()), 4), \
        "final_target_mean must be the cleaned target mean rounded to four decimal places."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
