#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy.optimize import minimize
from scipy.stats import wasserstein_distance

RAW = Path('/home/user/raw_latency.log')
CLEAN = Path('/home/user/clean_latency.csv')
SCRIPT = Path('/home/user/fit_mcmc.py')
RESULTS = Path('/home/user/profiling_results.json')


def extracted_values(raw_text):
    values = []
    for line in raw_text.splitlines():
        if 'Status: 200' in line and 'Endpoint: /api/v1/data' in line:
            match = re.search(r'Latency:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))ms', line)
            assert match, f'Could not extract latency from qualifying line: {line}'
            values.append(float(match.group(1)))
    return values


def read_clean():
    with CLEAN.open() as f:
        lines = [line.strip() for line in f if line.strip()]
    try:
        values = [float(x) for x in lines]
    except ValueError:
        assert False, f'Not all lines in {CLEAN} are valid numerical values.'
    return lines, values


def mle_means(data):
    x = np.asarray(data, dtype=float)
    log_c1 = math.log(0.7) - math.log(5.0 * math.sqrt(2.0 * math.pi))
    log_c2 = math.log(0.3) - math.log(10.0 * math.sqrt(2.0 * math.pi))

    def objective(mu):
        a = log_c1 - 0.5 * ((x - mu[0]) / 5.0) ** 2
        b = log_c2 - 0.5 * ((x - mu[1]) / 10.0) ** 2
        return -float(np.logaddexp(a, b).sum())

    fit = minimize(objective, np.array([25.0, 100.0]), method='L-BFGS-B',
                   bounds=[(0.0, 50.0), (50.0, 150.0)])
    assert fit.success, fit.message
    return float(fit.x[0]), float(fit.x[1])


def reference_distance(data, mu1, mu2):
    rng = np.random.default_rng(73421)
    choose_first = rng.random(200000) < 0.7
    sample = np.empty(200000)
    sample[choose_first] = rng.normal(mu1, 5.0, int(choose_first.sum()))
    sample[~choose_first] = rng.normal(mu2, 10.0, int((~choose_first).sum()))
    return float(wasserstein_distance(np.asarray(data, dtype=float), sample))


def execute_script(trace_file):
    if RESULTS.exists():
        RESULTS.unlink()

    runner = Path('/tmp/run_fit_with_trace.py')
    runner.write_text('''\
import json, runpy, sys
script, report = sys.argv[1], sys.argv[2]
count = 0
def tracer(frame, event, arg):
    global count
    if event == "line" and frame.f_code.co_filename == script:
        count += 1
    return tracer
sys.settrace(tracer)
try:
    try:
        runpy.run_path(script, run_name="__main__")
    except SystemExit as exc:
        if exc.code not in (None, 0):
            raise
finally:
    sys.settrace(None)
    with open(report, "w") as f:
        json.dump({"line_events": count}, f)
''')
    proc = subprocess.run(
        [sys.executable, str(runner), str(SCRIPT), str(trace_file)],
        cwd='/home/user', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=180
    )
    assert proc.returncode == 0, f'fit_mcmc.py failed when executed:\n{proc.stdout}'
    assert RESULTS.is_file(), 'Executing fit_mcmc.py did not create profiling_results.json.'
    with open(trace_file) as f:
        trace = json.load(f)
    assert trace['line_events'] >= 5000, (
        'fit_mcmc.py did not execute enough Python iterations to implement the required '
        '5,000-step Metropolis-Hastings chain.'
    )
    with RESULTS.open() as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f'The file {RESULTS} does not contain valid JSON.'


def validate_behavior(results, data, tolerance=3.0):
    required = {'mu1', 'mu2', 'wasserstein_distance', 'n_samples'}
    assert not (required - set(results)), f'Missing required keys: {required - set(results)}'
    assert results['n_samples'] == len(data)
    assert isinstance(results['mu1'], (int, float)) and not isinstance(results['mu1'], bool)
    assert isinstance(results['mu2'], (int, float)) and not isinstance(results['mu2'], bool)
    assert isinstance(results['wasserstein_distance'], (int, float)) and not isinstance(results['wasserstein_distance'], bool)
    assert all(math.isfinite(float(results[k])) for k in ('mu1', 'mu2', 'wasserstein_distance'))

    expected_mu1, expected_mu2 = mle_means(data)
    assert abs(float(results['mu1']) - expected_mu1) <= tolerance, (
        f"mu1={results['mu1']} is inconsistent with the supplied data (reference {expected_mu1:.3f})."
    )
    assert abs(float(results['mu2']) - expected_mu2) <= tolerance, (
        f"mu2={results['mu2']} is inconsistent with the supplied data (reference {expected_mu2:.3f})."
    )

    distance = float(results['wasserstein_distance'])
    assert distance > 0.0, 'wasserstein_distance must be calculated, not reported as zero.'
    expected_distance = reference_distance(data, float(results['mu1']), float(results['mu2']))
    assert abs(distance - expected_distance) <= 0.8, (
        f'wasserstein_distance={distance} is inconsistent with the empirical data and fitted GMM '
        f'(reference approximately {expected_distance:.3f}).'
    )


def test_clean_latency_csv():
    assert CLEAN.exists(), f'The file {CLEAN} is missing.'
    lines, actual = read_clean()
    assert len(lines) == 500, f'Expected exactly 500 lines in {CLEAN}, but found {len(lines)}.'
    expected = extracted_values(RAW.read_text())
    assert len(expected) == 500
    assert actual == expected, 'clean_latency.csv does not exactly contain the qualifying raw-log latencies in order.'


def test_fit_mcmc_script_exists():
    assert SCRIPT.exists(), f'The script {SCRIPT} is missing.'
    assert SCRIPT.is_file(), f'The path {SCRIPT} is not a valid file.'


def test_profiling_results():
    original_raw = RAW.read_bytes()
    original_clean = CLEAN.read_bytes()

    rng = np.random.default_rng(9917)
    challenge = np.concatenate((rng.normal(32.0, 5.0, 350), rng.normal(112.0, 10.0, 150)))
    rng.shuffle(challenge)
    challenge = np.round(challenge, 2)
    challenge_raw = ''.join(
        f'[2026-01-01T00:00:00Z] INFO - RequestID: {i} | Status: 200 | Latency: {x:.2f}ms | Endpoint: /api/v1/data\n'
        for i, x in enumerate(challenge)
    )

    challenge_error = None
    final_results = None
    try:
        RAW.write_text(challenge_raw)
        CLEAN.write_text(''.join(f'{x:.2f}\n' for x in challenge))
        challenge_results = execute_script('/tmp/challenge_trace.json')
        validate_behavior(challenge_results, challenge.tolist())
    except BaseException as exc:
        challenge_error = exc
    finally:
        RAW.write_bytes(original_raw)
        CLEAN.write_bytes(original_clean)
        final_results = execute_script('/tmp/final_trace.json')

    if challenge_error is not None:
        raise challenge_error

    assert RESULTS.exists(), f'The file {RESULTS} is missing.'
    required_keys = {'mu1', 'mu2', 'wasserstein_distance', 'n_samples'}
    missing_keys = required_keys - set(final_results.keys())
    assert not missing_keys, f'Missing required keys in {RESULTS}: {missing_keys}'

    assert final_results['n_samples'] == 500, f"Expected 'n_samples' to be 500, got {final_results['n_samples']}."
    assert isinstance(final_results['mu1'], (int, float)), "'mu1' must be a float."
    assert 17.0 <= final_results['mu1'] <= 23.0, f"'mu1' is out of the expected range (17.0 - 23.0): {final_results['mu1']}"
    assert isinstance(final_results['mu2'], (int, float)), "'mu2' must be a float."
    assert 74.0 <= final_results['mu2'] <= 86.0, f"'mu2' is out of the expected range (74.0 - 86.0): {final_results['mu2']}"
    assert isinstance(final_results['wasserstein_distance'], (int, float)), "'wasserstein_distance' must be a float."
    assert 0.0 <= final_results['wasserstein_distance'] <= 6.0, f"'wasserstein_distance' is out of expected bounds (0.0 - 6.0): {final_results['wasserstein_distance']}"

    _, original_data = read_clean()
    validate_behavior(final_results, original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
