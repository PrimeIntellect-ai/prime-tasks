#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys

import numpy as np

SAMPLER = Path('/home/user/mcmc_sampler.py')
ANALYSIS = Path('/home/user/analysis.py')
DATA = Path('/home/user/data.npy')
RESULTS = Path('/home/user/results.json')


def call_name(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return '.'.join(reversed(parts))


def reference_run_mcmc(data, iterations=6000):
    np.random.seed(123)
    cov = np.cov(data, rowvar=False)
    inv_cov = np.linalg.pinv(cov, rcond=1e-5)
    samples = []
    current_state = np.zeros(data.shape[1])
    accepted = 0

    for _ in range(iterations):
        proposal = current_state + np.random.multivariate_normal(
            np.zeros(data.shape[1]), np.eye(data.shape[1]) * 0.1
        )
        ll_prop = -0.5 * proposal.T @ inv_cov @ proposal
        ll_curr = -0.5 * current_state.T @ inv_cov @ current_state
        if np.log(np.random.rand()) < (ll_prop - ll_curr):
            current_state = proposal
            accepted += 1
        samples.append(current_state)

    return np.array(samples), accepted / iterations


def reference_results(samples):
    post = samples[1000:]
    assert post.shape == (5000, 3)
    np.random.seed(42)
    bootstrap_means = []
    for _ in range(1000):
        indices = np.random.choice(5000, size=5000, replace=True)
        bootstrap_means.append(post[indices].mean(axis=0))
    bootstrap_means = np.asarray(bootstrap_means)
    means = post.mean(axis=0)
    lower = np.percentile(bootstrap_means, 2.5, axis=0)
    upper = np.percentile(bootstrap_means, 97.5, axis=0)
    return {
        f'dim_{i}': {
            'mean': round(float(means[i]), 4),
            'ci_lower': round(float(lower[i]), 4),
            'ci_upper': round(float(upper[i]), 4),
        }
        for i in range(3)
    }


def load_results():
    assert RESULTS.exists(), '/home/user/results.json is missing.'
    try:
        with RESULTS.open() as f:
            value = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError('results.json is not a valid JSON file.') from exc
    assert set(value) == {'dim_0', 'dim_1', 'dim_2'}, 'results.json has incorrect top-level keys.'
    for dim in value:
        assert isinstance(value[dim], dict), f'{dim} must contain an object.'
        assert set(value[dim]) == {'mean', 'ci_lower', 'ci_upper'}, f'{dim} has incorrect metrics.'
        for metric, number in value[dim].items():
            assert isinstance(number, (int, float)) and not isinstance(number, bool), \
                f'Value for {dim}.{metric} is not a number.'
            assert math.isfinite(number), f'Value for {dim}.{metric} is not finite.'
    return value


def assert_results_match(actual, expected, tolerance=5e-5):
    for dim in expected:
        for metric in expected[dim]:
            assert math.isclose(actual[dim][metric], expected[dim][metric], abs_tol=tolerance), \
                f'Expected {dim}.{metric}={expected[dim][metric]}, got {actual[dim][metric]}.'


def run_analysis(expected_acceptance):
    if RESULTS.exists():
        RESULTS.unlink()
    proc = subprocess.run(
        [sys.executable, str(ANALYSIS)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert proc.returncode == 0, f'analysis.py failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}'
    numbers = [float(x) for x in re.findall(r'(?<![A-Za-z_])[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?', proc.stdout)]
    assert any(math.isclose(x, expected_acceptance, abs_tol=1e-9) for x in numbers), \
        f'analysis.py did not print the returned acceptance rate {expected_acceptance}. Output was: {proc.stdout!r}'
    assert expected_acceptance > 0.1, 'Acceptance rate did not pass the convergence check.'
    return load_results()


def test_complete_workflow():
    # Preserve the original verifier's source assertions, then ensure they are executable code.
    assert SAMPLER.exists(), '/home/user/mcmc_sampler.py is missing.'
    sampler_source = SAMPLER.read_text()
    assert 'np.linalg.pinv' in sampler_source, 'mcmc_sampler.py does not use np.linalg.pinv.'
    assert '1e-5' in sampler_source, 'mcmc_sampler.py does not use rcond=1e-5.'

    sampler_tree = ast.parse(sampler_source, filename=str(SAMPLER))
    correct_assignment = False
    for node in ast.walk(sampler_tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        value = node.value
        if not any(isinstance(t, ast.Name) and t.id == 'inv_cov' for t in targets):
            continue
        if not isinstance(value, ast.Call) or call_name(value.func) != 'np.linalg.pinv':
            continue
        if not value.args or not isinstance(value.args[0], ast.Name) or value.args[0].id != 'cov':
            continue
        rcond = next((kw.value for kw in value.keywords if kw.arg == 'rcond'), None)
        if isinstance(rcond, ast.Constant) and rcond.value == 1e-5:
            correct_assignment = True
    assert correct_assignment, 'inv_cov must be assigned np.linalg.pinv(cov, rcond=1e-5).'

    assert ANALYSIS.exists(), '/home/user/analysis.py is missing.'
    assert ANALYSIS.is_file(), '/home/user/analysis.py is not a regular file.'
    analysis_tree = ast.parse(ANALYSIS.read_text(), filename=str(ANALYSIS))

    mcmc_calls = [n for n in ast.walk(analysis_tree)
                  if isinstance(n, ast.Call) and call_name(n.func).endswith('run_mcmc')]
    assert any(any(kw.arg == 'iterations' and isinstance(kw.value, ast.Constant) and kw.value.value == 6000
                   for kw in call.keywords) for call in mcmc_calls), \
        'analysis.py must call run_mcmc with iterations=6000.'

    seed_calls = [n for n in ast.walk(analysis_tree)
                  if isinstance(n, ast.Call) and call_name(n.func).endswith('random.seed')]
    assert len(seed_calls) == 1, 'analysis.py must set the NumPy random seed exactly once.'
    assert len(seed_calls[0].args) == 1 and isinstance(seed_calls[0].args[0], ast.Constant) \
        and seed_calls[0].args[0].value == 42, 'The bootstrap seed must be 42.'

    seed_immediately_before_loop = False
    for parent in ast.walk(analysis_tree):
        body = getattr(parent, 'body', None)
        if not isinstance(body, list):
            continue
        for first, second in zip(body, body[1:]):
            if not isinstance(first, ast.Expr) or first.value is not seed_calls[0] or not isinstance(second, ast.For):
                continue
            iterator = second.iter
            if (isinstance(iterator, ast.Call) and call_name(iterator.func) == 'range'
                    and len(iterator.args) == 1 and isinstance(iterator.args[0], ast.Constant)
                    and iterator.args[0].value == 1000):
                seed_immediately_before_loop = True
    assert seed_immediately_before_loop, 'np.random.seed(42) must be immediately before the 1000-iteration bootstrap loop.'

    spec = importlib.util.spec_from_file_location('submitted_mcmc_sampler', SAMPLER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, 'run_mcmc', None)), 'run_mcmc is missing or not callable.'

    original_data_bytes = DATA.read_bytes()
    original_data = np.load(DATA)
    rng = np.random.RandomState(2026)
    a = rng.normal(size=80)
    b = rng.normal(size=80)
    alternate_data = np.column_stack((a, b, a + b))

    try:
        # A hidden alternate dataset prevents fixed JSON constants from passing.
        np.save(DATA, alternate_data)
        expected_samples, expected_acceptance = reference_run_mcmc(alternate_data)
        submitted_samples, submitted_acceptance = module.run_mcmc(alternate_data, 6000)
        assert isinstance(submitted_samples, np.ndarray) and submitted_samples.shape == (6000, 3)
        assert np.allclose(submitted_samples, expected_samples, rtol=0, atol=1e-12), \
            'run_mcmc does not execute the required pseudo-inverse sampler.'
        assert math.isclose(submitted_acceptance, expected_acceptance, abs_tol=1e-12)
        alternate_actual = run_analysis(expected_acceptance)
        assert_results_match(alternate_actual, reference_results(expected_samples))
    finally:
        DATA.write_bytes(original_data_bytes)

    # Execute the submitted analysis on the required dataset and validate its generated artifact.
    expected_samples, expected_acceptance = reference_run_mcmc(original_data)
    submitted_samples, submitted_acceptance = module.run_mcmc(original_data, 6000)
    assert np.allclose(submitted_samples, expected_samples, rtol=0, atol=1e-12)
    assert math.isclose(submitted_acceptance, expected_acceptance, abs_tol=1e-12)
    actual = run_analysis(expected_acceptance)
    assert_results_match(actual, reference_results(expected_samples))

    # Preserve the original verifier's fixed-value assertions.
    expected_fixed = {
        'dim_0': {'mean': -0.0150, 'ci_lower': -0.0469, 'ci_upper': 0.0163},
        'dim_1': {'mean': 0.0468, 'ci_lower': 0.0125, 'ci_upper': 0.0822},
        'dim_2': {'mean': -0.0076, 'ci_lower': -0.0359, 'ci_upper': 0.0211},
    }
    for dim in expected_fixed:
        assert dim in actual, f"Missing key '{dim}' in results.json."
        for metric in expected_fixed[dim]:
            assert metric in actual[dim], f"Missing metric '{metric}' in {dim}."
            assert isinstance(actual[dim][metric], (int, float)), f'Value for {dim}.{metric} is not a number.'
            assert math.isclose(actual[dim][metric], expected_fixed[dim][metric], abs_tol=1e-3), \
                f'Expected {dim}.{metric} near {expected_fixed[dim][metric]}, got {actual[dim][metric]}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
