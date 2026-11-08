#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import json
import os
import re
import subprocess
import sys

import emcee
import matplotlib.image as mpimg
import numpy as np
from scipy.optimize import minimize
from scipy.stats import gaussian_kde

SIM = '/home/user/sim'
DATA = '/home/user/data/decay_data.csv'
ANALYSIS = os.path.join(SIM, 'run_analysis.py')
TEST_MODEL = os.path.join(SIM, 'test_model.py')
RESULTS = os.path.join(SIM, 'results.json')
IMAGE = os.path.join(SIM, 'posterior_A.png')
LOG = os.path.join(SIM, 'test_results.log')


def assert_original_artifacts():
    assert os.path.isfile(RESULTS), f'File {RESULTS} is missing.'
    with open(RESULTS) as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f'{RESULTS} is not valid JSON.') from exc

    for key in ['A_map', 'lambda_map', 'B_map', 'A_kde_peak']:
        assert key in results, f"Key '{key}' missing from results.json."
        assert isinstance(results[key], (int, float)), f"Value for '{key}' must be a float."

    assert abs(results['A_map'] - 4.88) < 0.2, \
        f"A_map value {results['A_map']} is not within expected range."
    assert abs(results['lambda_map'] - 0.47) < 0.1, \
        f"lambda_map value {results['lambda_map']} is not within expected range."

    assert os.path.isfile(IMAGE), f'Image file {IMAGE} is missing.'
    with open(IMAGE, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f'File {IMAGE} is not a valid PNG image.'

    assert os.path.isfile(LOG), f'Log file {LOG} is missing.'
    with open(LOG, errors='replace') as f:
        log_content = f.read()
    assert 'passed' in log_content.lower(), f'Pytest log {LOG} does not indicate a passed test.'

    assert os.path.isfile(ANALYSIS), 'Script run_analysis.py is missing.'
    assert os.path.isfile(TEST_MODEL), 'Test script test_model.py is missing.'


def load_results():
    assert os.path.isfile(RESULTS), 'run_analysis.py did not create results.json'
    with open(RESULTS) as f:
        result = json.load(f)
    assert set(['A_map', 'lambda_map', 'B_map', 'A_kde_peak']).issubset(result)
    for key in ['A_map', 'lambda_map', 'B_map', 'A_kde_peak']:
        assert isinstance(result[key], (int, float)) and not isinstance(result[key], bool)
        assert np.isfinite(result[key]), f'{key} is not finite'
    return result


def reference(t, y):
    def log_prob(theta):
        A, lam, B = theta
        if not (0 <= A <= 10 and 0 <= lam <= 5 and 0 <= B <= 5):
            return -np.inf
        model = A * np.exp(-lam * t) + B
        return -0.5 * np.sum(((y - model) / 0.5) ** 2)

    opt = minimize(lambda p: -log_prob(p), [4.0, 0.1, 0.1], method='Nelder-Mead')
    assert opt.success, opt.message
    map_value = np.asarray(opt.x, dtype=float)

    np.random.seed(42)
    initial = map_value + 1e-4 * np.random.randn(10, 3)
    sampler = emcee.EnsembleSampler(10, 3, log_prob)
    sampler.run_mcmc(initial, 500, progress=False)
    a_samples = sampler.get_chain(discard=100, flat=True)[:, 0]
    grid = np.linspace(0, 10, 1000)
    peak = float(grid[np.argmax(gaussian_kde(a_samples)(grid))])
    return map_value, peak


def run_analysis_and_check(t, y):
    for path in (RESULTS, IMAGE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    proc = subprocess.run(
        [sys.executable, ANALYSIS], cwd=SIM, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=180
    )
    assert proc.returncode == 0, 'run_analysis.py failed:\n' + proc.stdout

    result = load_results()
    expected_map, expected_peak = reference(t, y)
    actual_map = np.array([result['A_map'], result['lambda_map'], result['B_map']], dtype=float)
    assert np.allclose(actual_map, expected_map, atol=0.01, rtol=0), \
        f'MAP result {actual_map} does not match recomputed value {expected_map}'
    assert 0 <= result['A_kde_peak'] <= 10
    assert abs(result['A_kde_peak'] - expected_peak) < 0.35, \
        f"A_kde_peak {result['A_kde_peak']} does not match recomputed peak {expected_peak}"

    assert os.path.isfile(IMAGE), 'run_analysis.py did not create posterior_A.png'
    assert os.path.getsize(IMAGE) > 1000, 'posterior_A.png is only a header or is otherwise empty'
    image = mpimg.imread(IMAGE)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    assert np.isfinite(image).all() and float(np.std(image)) > 1e-4, \
        'posterior_A.png does not contain a rendered plot'
    return result


def main():
    # Preserve every assertion made by the original verifier before regenerating files.
    assert_original_artifacts()

    original_bytes = open(DATA, 'rb').read()
    original = np.genfromtxt(DATA, delimiter=',', names=True)
    original_t = np.asarray(original['t'], dtype=float)
    original_y = np.asarray(original['y'], dtype=float)
    probe_started = False

    try:
        original_result = run_analysis_and_check(original_t, original_y)

        # Execute the submitted regression test rather than trusting its saved log.
        test_proc = subprocess.run(
            [sys.executable, '-m', 'pytest', TEST_MODEL, '-q'], cwd=SIM,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=180
        )
        assert test_proc.returncode == 0, 'Submitted regression test failed:\n' + test_proc.stdout
        match = re.search(r'(\d+)\s+passed', test_proc.stdout.lower())
        assert match and int(match.group(1)) >= 1, \
            'test_model.py did not execute at least one passing pytest test:\n' + test_proc.stdout

        # Exercise the workflow on a second dataset to reject fixed result files/scripts.
        probe_y = 3.2 * np.exp(-0.85 * original_t) + 1.7
        np.savetxt(DATA, np.column_stack([original_t, probe_y]), delimiter=',',
                   header='t,y', comments='')
        probe_started = True
        probe_result = run_analysis_and_check(original_t, probe_y)
        assert abs(probe_result['A_map'] - original_result['A_map']) > 0.5, \
            'Analysis output did not respond to changed input data'
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_bytes)
        if probe_started:
            # Leave the requested artifacts corresponding to the real dataset.
            env = os.environ.copy()
            env['MPLBACKEND'] = 'Agg'
            subprocess.run([sys.executable, ANALYSIS], cwd=SIM, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=180)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
