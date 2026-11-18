#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import subprocess
import tempfile

import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp
from scipy.stats import ks_2samp

SCRIPT_PATH = '/home/user/lorenz_ensemble.py'
TEST_PATH = '/home/user/test_regression.py'
OUTPUT_PATH = '/home/user/training_data.csv'
REFERENCE_PATH = '/home/user/reference_data.csv'
REPORT_PATH = '/home/user/regression_report.json'


def get_file_md5(filepath):
    hasher = hashlib.md5()
    with open(filepath, 'rb') as f:
        hasher.update(f.read())
    return hasher.hexdigest()


def expected_lorenz_output():
    def lorenz(t, state, sigma=10.0, rho=28.0, beta=8.0 / 3.0):
        x, y, z = state
        return [sigma * (y - x), x * (rho - z) - y, x * y - beta * z]

    np.random.seed(42)
    initial_states = np.random.rand(100, 3) * 10
    return np.asarray([
        solve_ivp(lorenz, [0, 5], state, t_eval=[5]).y[:, 0]
        for state in initial_states
    ])


def run_python(path):
    subprocess.run(['python3', path], check=True, timeout=180)


def load_report():
    assert os.path.isfile(REPORT_PATH), f'File {REPORT_PATH} does not exist.'
    with open(REPORT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f'{REPORT_PATH} is not a valid JSON file.'


def assert_report_matches(training_z, reference_z, report):
    assert set(report) == {
        'ks_statistic', 'p_value', 'is_deterministic', 'reference_mean_z'
    }, f'regression_report.json has incorrect keys: {set(report)}'

    expected = ks_2samp(training_z, reference_z)
    assert abs(float(report['ks_statistic']) - float(expected.statistic)) < 1e-12
    assert abs(float(report['p_value']) - float(expected.pvalue)) < 1e-12
    assert report['is_deterministic'] is True
    assert abs(float(report['reference_mean_z']) - float(np.mean(reference_z))) < 1e-12


def test_lorenz_ensemble_is_deterministic_and_correct():
    assert os.path.isfile(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'

    # The simulation generator must work without using the provided reference CSV
    # as its output source. Keep the reference only in verifier memory while running.
    assert os.path.isfile(REFERENCE_PATH), f'{REFERENCE_PATH} does not exist.'
    with open(REFERENCE_PATH, 'rb') as f:
        reference_bytes = f.read()
    reference_mode = os.stat(REFERENCE_PATH).st_mode
    os.unlink(REFERENCE_PATH)

    try:
        run_python(SCRIPT_PATH)
        assert os.path.isfile(OUTPUT_PATH), f'Output {OUTPUT_PATH} not generated after running script.'
        hash1 = get_file_md5(OUTPUT_PATH)
        first_bytes = open(OUTPUT_PATH, 'rb').read()

        run_python(SCRIPT_PATH)
        assert os.path.isfile(OUTPUT_PATH), f'Output {OUTPUT_PATH} not generated after second run.'
        hash2 = get_file_md5(OUTPUT_PATH)
        second_bytes = open(OUTPUT_PATH, 'rb').read()
    finally:
        with open(REFERENCE_PATH, 'wb') as f:
            f.write(reference_bytes)
        os.chmod(REFERENCE_PATH, reference_mode)

    assert hash1 == hash2, 'The output training_data.csv is not deterministic across multiple runs.'
    assert first_bytes == second_bytes, 'Consecutive CSV outputs differ byte-for-byte.'

    generated = pd.read_csv(OUTPUT_PATH)
    assert list(generated.columns) == ['x', 'y', 'z'], 'training_data.csv must contain exactly x, y, z columns.'
    assert generated.shape == (100, 3), f'Expected 100 simulation rows, got {generated.shape}.'
    assert np.isfinite(generated.to_numpy(dtype=float)).all(), 'Simulation output contains non-finite values.'
    np.testing.assert_allclose(
        generated.to_numpy(dtype=float), expected_lorenz_output(), rtol=1e-13, atol=1e-13,
        err_msg='training_data.csv does not contain the ordered Lorenz ensemble results.'
    )


def test_regression_script_executes_and_computes_values():
    assert os.path.isfile(TEST_PATH), f'Script {TEST_PATH} does not exist.'

    # Exercise the submitted regression script on verifier-selected data so that
    # hardcoded report values cannot pass.
    backups = {}
    for path in (OUTPUT_PATH, REFERENCE_PATH, REPORT_PATH):
        if os.path.exists(path):
            with open(path, 'rb') as f:
                backups[path] = f.read()

    training = pd.DataFrame({'x': [0, 0, 0, 0], 'y': [0, 0, 0, 0], 'z': [-3.0, -1.0, 2.0, 8.0]})
    reference = pd.DataFrame({'x': [0, 0, 0, 0, 0], 'y': [0, 0, 0, 0, 0], 'z': [10.0, 11.0, 12.0, 13.0, 20.0]})

    try:
        training.to_csv(OUTPUT_PATH, index=False)
        reference.to_csv(REFERENCE_PATH, index=False)
        if os.path.exists(REPORT_PATH):
            os.unlink(REPORT_PATH)
        run_python(TEST_PATH)
        assert_report_matches(training['z'].to_numpy(), reference['z'].to_numpy(), load_report())
    finally:
        for path in (OUTPUT_PATH, REFERENCE_PATH, REPORT_PATH):
            if path in backups:
                with open(path, 'wb') as f:
                    f.write(backups[path])
            elif os.path.exists(path):
                os.unlink(path)

    # Execute it again against the real generated and reference datasets, requiring
    # the final report to be freshly produced by the submitted script.
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    run_python(TEST_PATH)


def test_regression_report_exists_and_valid():
    report = load_report()

    assert 'ks_statistic' in report, "Missing 'ks_statistic' in regression_report.json"
    assert 'p_value' in report, "Missing 'p_value' in regression_report.json"
    assert 'is_deterministic' in report, "Missing 'is_deterministic' in regression_report.json"
    assert 'reference_mean_z' in report, "Missing 'reference_mean_z' in regression_report.json"

    assert abs(report['ks_statistic'] - 0.0) < 1e-5, f"ks_statistic should be 0.0, got {report['ks_statistic']}"
    assert abs(report['p_value'] - 1.0) < 1e-5, f"p_value should be 1.0, got {report['p_value']}"
    assert report['is_deterministic'] is True, f"is_deterministic should be true, got {report['is_deterministic']}"

    training_z = pd.read_csv(OUTPUT_PATH)['z'].to_numpy()
    reference_z = pd.read_csv(REFERENCE_PATH)['z'].to_numpy()
    assert_report_matches(training_z, reference_z, report)


def test_reference_mean_z():
    assert os.path.isfile(REFERENCE_PATH), f'{REFERENCE_PATH} does not exist.'
    assert os.path.isfile(REPORT_PATH), f'{REPORT_PATH} does not exist.'

    with open(REPORT_PATH, 'r') as f:
        report = json.load(f)

    z_values = []
    with open(REFERENCE_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            z_values.append(float(row['z']))

    expected_mean = sum(z_values) / len(z_values)
    reported_mean = report['reference_mean_z']
    assert abs(expected_mean - reported_mean) < 1e-5, f'reference_mean_z should be {expected_mean}, got {reported_mean}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
