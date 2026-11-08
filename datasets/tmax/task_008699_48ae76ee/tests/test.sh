#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os

import numpy as np
import pytest
import torch
import torch.nn as nn
from scipy import stats

RESULTS_PATH = '/home/user/results.json'
DATA_DIR = '/home/user/data'
WEIGHTS_PATH = '/home/user/model/weights.pth'
BATCH_NAMES = ('batch_1', 'batch_2', 'batch_3')


class MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(4, 16)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 1)

    def forward(self, x):
        return self.fc2(self.relu(self.fc1(x)))


def load_results():
    with open(RESULTS_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail('results.json is not a valid JSON file.')


def verify_input_integrity():
    # Recreate the setup data independently so modifying the supplied inputs
    # cannot make a fabricated report self-consistent.
    rng = np.random.RandomState(42)
    shifts = {'clean': 0.0, 'batch_1': 0.0, 'batch_2': 2.0, 'batch_3': 0.0}
    loaded = {}
    for name, shift in shifts.items():
        x = rng.randn(500, 4) + shift
        y = np.sum(x, axis=1, keepdims=True) + rng.randn(500, 1) * 0.1
        expected_data = np.hstack((x, y))
        path = os.path.join(DATA_DIR, name + '.csv')
        assert os.path.isfile(path), f'Missing dataset: {path}'
        actual_data = np.loadtxt(path, delimiter=',')
        assert actual_data.shape == (500, 5), f'Unexpected shape for {path}'
        assert np.allclose(actual_data, expected_data, rtol=0, atol=1e-12), f'{path} was modified'
        loaded[name] = actual_data
    return loaded


def calculate_expected():
    datasets = verify_input_integrity()
    assert os.path.isfile(WEIGHTS_PATH), f'Missing weights file: {WEIGHTS_PATH}'

    model = MLP()
    try:
        state = torch.load(WEIGHTS_PATH, map_location='cpu', weights_only=True)
    except TypeError:
        state = torch.load(WEIGHTS_PATH, map_location='cpu')
    model.load_state_dict(state, strict=True)

    expected_parameters = {
        'fc1.weight': 0.5,
        'fc1.bias': 0.1,
        'fc2.weight': 0.5,
        'fc2.bias': 0.1,
    }
    actual_state = model.state_dict()
    assert set(actual_state) == set(expected_parameters), 'Unexpected model state dictionary'
    for key, value in expected_parameters.items():
        expected_tensor = torch.full_like(actual_state[key], value)
        assert torch.equal(actual_state[key], expected_tensor), f'{key} was modified'

    model.eval()
    predictions = {}
    mse = {}
    with torch.no_grad():
        for name, data in datasets.items():
            features = torch.tensor(data[:, :4], dtype=torch.float32)
            targets = torch.tensor(data[:, 4], dtype=torch.float32)
            pred = model(features).squeeze(1)
            predictions[name] = pred.cpu().numpy()
            mse[name] = float(torch.mean((pred - targets) ** 2).item())

    corrupted = [name for name in BATCH_NAMES if mse[name] > 2.0]
    computed_stats = {}
    clean_pred = predictions['clean'].astype(np.float64)
    for name in corrupted:
        batch_pred = predictions[name].astype(np.float64)
        test = stats.ttest_ind(batch_pred, clean_pred, equal_var=False)
        difference = float(np.mean(batch_pred) - np.mean(clean_pred))
        batch_var = float(np.var(batch_pred, ddof=1))
        clean_var = float(np.var(clean_pred, ddof=1))
        batch_term = batch_var / len(batch_pred)
        clean_term = clean_var / len(clean_pred)
        standard_error = math.sqrt(batch_term + clean_term)
        degrees_freedom = (batch_term + clean_term) ** 2 / (
            batch_term ** 2 / (len(batch_pred) - 1)
            + clean_term ** 2 / (len(clean_pred) - 1)
        )
        z_margin = 1.96 * standard_error
        t_margin = float(stats.t.ppf(0.975, degrees_freedom)) * standard_error
        computed_stats[name] = {
            't_statistic': float(test.statistic),
            'p_value': float(test.pvalue),
            'z_ci': (difference - z_margin, difference + z_margin),
            't_ci': (difference - t_margin, difference + t_margin),
        }
    return mse, corrupted, computed_stats


def assert_rounded_value(actual, expected, label):
    assert isinstance(actual, float), f'{label} is not a float.'
    assert math.isfinite(actual), f'{label} must be finite.'
    rounded_expected = round(float(expected), 4)
    assert abs(actual - rounded_expected) <= 1e-7, (
        f'{label} should be {rounded_expected} after rounding to 4 decimal places, got {actual}'
    )


def test_results_file_exists():
    assert os.path.isfile(RESULTS_PATH), 'The results file /home/user/results.json does not exist.'


def test_results_structure():
    results = load_results()
    assert 'mse' in results, "Key 'mse' missing from results.json."
    assert 'corrupted_batches' in results, "Key 'corrupted_batches' missing from results.json."

    expected_mse_keys = {'clean', 'batch_1', 'batch_2', 'batch_3'}
    assert isinstance(results['mse'], dict), "'mse' must be a dictionary."
    assert set(results['mse'].keys()) == expected_mse_keys, (
        f"Expected mse keys {expected_mse_keys}, got {set(results['mse'].keys())}."
    )
    for key, value in results['mse'].items():
        assert isinstance(value, float), f'MSE value for {key} is not a float.'

    expected_mse, expected_corrupted, _ = calculate_expected()
    assert isinstance(results['corrupted_batches'], dict), "'corrupted_batches' must be a dictionary."
    assert set(results['corrupted_batches']) == set(expected_corrupted), (
        f'Expected corrupted batches {set(expected_corrupted)}, got '
        f"{set(results['corrupted_batches'])}."
    )

    expected_stat_keys = {'t_statistic', 'p_value', 'ci_lower', 'ci_upper'}
    for batch in expected_corrupted:
        batch_stats = results['corrupted_batches'][batch]
        assert isinstance(batch_stats, dict), f'Statistics for {batch} must be a dictionary.'
        assert set(batch_stats.keys()) == expected_stat_keys, (
            f'Expected stats keys {expected_stat_keys}, got {set(batch_stats.keys())}.'
        )
        for key, value in batch_stats.items():
            assert isinstance(value, float), f'Value for {key} in {batch} is not a float.'

    # Preserve the threshold classification check while deriving the true classes.
    for batch in BATCH_NAMES:
        if batch in expected_corrupted:
            assert expected_mse[batch] > 2.0
        else:
            assert expected_mse[batch] <= 2.0


def test_results_values():
    results = load_results()
    expected_mse, expected_corrupted, expected_stats = calculate_expected()

    for name, expected in expected_mse.items():
        assert_rounded_value(results['mse'][name], expected, f'MSE for {name}')

    for batch in expected_corrupted:
        reported = results['corrupted_batches'][batch]
        expected = expected_stats[batch]
        assert_rounded_value(reported['t_statistic'], expected['t_statistic'], f't_statistic for {batch}')
        assert_rounded_value(reported['p_value'], expected['p_value'], f'p_value for {batch}')

        ci_lower = reported['ci_lower']
        ci_upper = reported['ci_upper']
        assert isinstance(ci_lower, float) and isinstance(ci_upper, float)
        assert math.isfinite(ci_lower) and math.isfinite(ci_upper)
        assert ci_lower < ci_upper, 'ci_lower should be less than ci_upper.'

        z_lower, z_upper = expected['z_ci']
        t_lower, t_upper = expected['t_ci']
        matches_z = (
            abs(ci_lower - round(z_lower, 4)) <= 1e-7
            and abs(ci_upper - round(z_upper, 4)) <= 1e-7
        )
        matches_t = (
            abs(ci_lower - round(t_lower, 4)) <= 1e-7
            and abs(ci_upper - round(t_upper, 4)) <= 1e-7
        )
        assert matches_z or matches_t, (
            f'CI for {batch} must match either the permitted z=1.96 interval or Welch t interval.'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
