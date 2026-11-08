#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import numpy as np
import pandas as pd

RESULTS = '/home/user/results.json'
NOTEBOOK = '/home/user/prepare_data.ipynb'
SENSOR = '/home/user/sensor_data.csv'
SECONDARY = '/home/user/secondary_sensors.csv'

EXPECTED_KEYS = {
    'integral_0_10',
    'derivative_at_5',
    'bootstrap_ci_lower',
    'bootstrap_ci_upper',
    'pc1_variance_explained',
    'first_row_projected',
}


def load_and_check_format(path=RESULTS):
    assert os.path.exists(path), f'File {path} does not exist. The notebook may not have been executed or saved the output correctly.'
    assert os.path.isfile(path), f'Expected {path} to be a file.'

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {path} is not a valid JSON file.'

    actual_keys = set(data.keys())
    missing_keys = EXPECTED_KEYS - actual_keys
    extra_keys = actual_keys - EXPECTED_KEYS
    assert not missing_keys, f'Missing expected keys in results.json: {missing_keys}'
    assert not extra_keys, f'Unexpected extra keys in results.json: {extra_keys}'

    assert isinstance(data['integral_0_10'], (int, float)), 'integral_0_10 must be a number'
    assert isinstance(data['derivative_at_5'], (int, float)), 'derivative_at_5 must be a number'
    assert isinstance(data['bootstrap_ci_lower'], (int, float)), 'bootstrap_ci_lower must be a number'
    assert isinstance(data['bootstrap_ci_upper'], (int, float)), 'bootstrap_ci_upper must be a number'
    assert isinstance(data['pc1_variance_explained'], (int, float)), 'pc1_variance_explained must be a number'

    assert isinstance(data['first_row_projected'], list), 'first_row_projected must be a list'
    assert len(data['first_row_projected']) == 2, 'first_row_projected must contain exactly 2 elements'
    assert isinstance(data['first_row_projected'][0], (int, float)), 'first_row_projected[0] must be a number'
    assert isinstance(data['first_row_projected'][1], (int, float)), 'first_row_projected[1] must be a number'

    assert 0.0 <= data['pc1_variance_explained'] <= 1.0, 'pc1_variance_explained must be a ratio between 0.0 and 1.0'
    assert data['bootstrap_ci_lower'] <= data['bootstrap_ci_upper'], 'bootstrap_ci_lower must be less than or equal to bootstrap_ci_upper'

    values = [data[k] for k in EXPECTED_KEYS if k != 'first_row_projected'] + data['first_row_projected']
    assert all(math.isfinite(float(v)) for v in values), 'All result values must be finite'
    return data


def compute_expected(sensor_path=SENSOR, secondary_path=SECONDARY):
    sensor = pd.read_csv(sensor_path)
    t = sensor['time'].to_numpy(dtype=float)
    temperature = sensor['temperature'].to_numpy(dtype=float)

    coefficients = np.polyfit(t, temperature, 3)
    integral = float(np.polyval(np.polyint(coefficients), 10.0) - np.polyval(np.polyint(coefficients), 0.0))
    derivative = float(np.polyval(np.polyder(coefficients), 5.0))

    np.random.seed(42)
    bootstrap_means = np.empty(10000, dtype=float)
    for i in range(10000):
        bootstrap_means[i] = np.mean(np.random.choice(temperature, size=len(temperature), replace=True))
    lower, upper = np.percentile(bootstrap_means, [2.5, 97.5])

    matrix = pd.read_csv(secondary_path, header=None).to_numpy(dtype=float)
    centered = matrix - matrix.mean(axis=0)
    _, singular_values, vt = np.linalg.svd(centered, full_matrices=False)
    ratio = float(singular_values[0] ** 2 / np.sum(singular_values ** 2))
    projected = centered @ vt[:2].T

    return {
        'integral_0_10': integral,
        'derivative_at_5': derivative,
        'bootstrap_ci_lower': float(lower),
        'bootstrap_ci_upper': float(upper),
        'pc1_variance_explained': ratio,
        'first_row_projected': [float(projected[0, 0]), float(projected[0, 1])],
    }


def assert_matches(data, expected):
    for key in ('integral_0_10', 'derivative_at_5', 'bootstrap_ci_lower',
                'bootstrap_ci_upper', 'pc1_variance_explained'):
        assert np.isclose(float(data[key]), expected[key], rtol=1e-7, atol=1e-7), \
            f'{key} is incorrect: got {data[key]!r}, expected {expected[key]!r}'

    # SVD component signs are mathematically arbitrary, so compare projection magnitudes.
    actual_projection = np.abs(np.asarray(data['first_row_projected'], dtype=float))
    expected_projection = np.abs(np.asarray(expected['first_row_projected'], dtype=float))
    assert np.allclose(actual_projection, expected_projection, rtol=1e-7, atol=1e-7), \
        f'first_row_projected is incorrect: got {data["first_row_projected"]!r}'


def execute_notebook():
    completed = subprocess.run(
        [
            'jupyter', 'nbconvert', '--to', 'notebook', '--execute', NOTEBOOK,
            '--output', '/tmp/verified_prepare_data.ipynb',
            '--ExecutePreprocessor.timeout=180',
        ],
        cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=240,
    )
    assert completed.returncode == 0, 'Notebook execution failed:\n' + completed.stdout[-4000:]


def test_results_json_exists():
    assert os.path.exists(RESULTS), f'File {RESULTS} does not exist. The notebook may not have been executed or saved the output correctly.'
    assert os.path.isfile(RESULTS), f'Expected {RESULTS} to be a file.'


def test_results_json_format_and_invariants():
    data = load_and_check_format()
    assert_matches(data, compute_expected())


def test_notebook_exists_was_executed_and_computes_results():
    assert os.path.isfile(NOTEBOOK), f'Expected notebook {NOTEBOOK} does not exist.'
    with open(NOTEBOOK, 'r') as f:
        notebook = json.load(f)
    code_cells = [c for c in notebook.get('cells', []) if c.get('cell_type') == 'code' and ''.join(c.get('source', [])).strip()]
    assert code_cells, 'The notebook must contain executable code cells.'
    assert all(isinstance(c.get('execution_count'), int) for c in code_cells), \
        'The submitted notebook must have been executed and saved with execution counts.'

    sensor_original = open(SENSOR, 'rb').read()
    secondary_original = open(SECONDARY, 'rb').read()

    sensor = pd.read_csv(SENSOR)
    secondary = pd.read_csv(SECONDARY, header=None)
    variant_sensor = sensor.copy()
    variant_sensor['temperature'] = (
        sensor['temperature'].to_numpy(dtype=float) * 1.173
        + np.sin(sensor['time'].to_numpy(dtype=float) * 0.731) * 2.4
        - 3.2
    )
    variant_secondary = secondary.to_numpy(dtype=float).copy()
    rows = np.arange(variant_secondary.shape[0], dtype=float)[:, None]
    scales = np.linspace(0.7, 1.6, variant_secondary.shape[1])[None, :]
    variant_secondary = variant_secondary * scales + 0.15 * np.sin(rows * 0.19 + np.arange(variant_secondary.shape[1]))

    try:
        variant_sensor.to_csv(SENSOR, index=False)
        pd.DataFrame(variant_secondary).to_csv(SECONDARY, index=False, header=False)
        expected_variant = compute_expected()
        execute_notebook()
        assert_matches(load_and_check_format(), expected_variant)
    finally:
        with open(SENSOR, 'wb') as f:
            f.write(sensor_original)
        with open(SECONDARY, 'wb') as f:
            f.write(secondary_original)

    # Restore results.json for the supplied input files and verify it once more.
    execute_notebook()
    assert_matches(load_and_check_format(), compute_expected())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
