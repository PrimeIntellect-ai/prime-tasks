#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import sys
import subprocess
import numpy as np
import pytest

MCMC_PATH = '/home/user/mcmc.py'


def expected_log_likelihood(data, mu, sigma):
    if sigma <= 0:
        return -np.inf
    return np.sum(-0.5 * np.log(2 * np.pi * sigma**2) - ((data - mu)**2) / (2 * sigma**2))


def expected_sample(data, iters=5000, seed=42):
    np.random.seed(seed)
    mu, sigma = 0.0, 1.0
    chain = []
    ll_current = expected_log_likelihood(data, mu, sigma)
    for _ in range(iters):
        mu_prop = mu + np.random.normal(0, 0.1)
        sigma_prop = sigma + np.random.normal(0, 0.1)
        ll_prop = expected_log_likelihood(data, mu_prop, sigma_prop)
        if sigma_prop > 0:
            log_accept_ratio = ll_prop - ll_current
            accept_prob = np.exp(min(0, log_accept_ratio))
        else:
            accept_prob = 0.0
        if np.random.rand() < accept_prob:
            mu, sigma = mu_prop, sigma_prop
            ll_current = ll_prop
        chain.append((mu, sigma))
    return np.array(chain)


def clear_mcmc_bytecode():
    for path in glob.glob('/home/user/__pycache__/mcmc*.pyc'):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def install_temporary_mcmc(source):
    original = open(MCMC_PATH, 'rb').read()
    with open(MCMC_PATH, 'w') as f:
        f.write(source)
    clear_mcmc_bytecode()
    return original


def restore_mcmc(original):
    with open(MCMC_PATH, 'wb') as f:
        f.write(original)
    clear_mcmc_bytecode()


def test_mcmc_py_fixed():
    assert os.path.isfile(MCMC_PATH), f"{MCMC_PATH} is missing"
    with open(MCMC_PATH, 'r') as f:
        content = f.read()
    assert "set(" not in content, "The non-deterministic 'set()' bug is still present in mcmc.py"

    tree = ast.parse(content)
    functions = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == 'log_likelihood']
    assert functions, 'mcmc.py must define log_likelihood'
    loop_nodes = (ast.For, ast.AsyncFor, ast.While, ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)
    assert not any(isinstance(n, loop_nodes) for n in ast.walk(functions[0])), \
        'log_likelihood must use a vectorized NumPy reduction rather than Python iteration'


def test_mcmc_sample_matches_vectorized_reference():
    import importlib.util
    spec = importlib.util.spec_from_file_location('submitted_mcmc_behavior', MCMC_PATH)
    submitted = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(submitted)

    rng = np.random.default_rng()
    cases = [
        (rng.normal(-1.3, 0.7, size=17), 137, 918273),
        (rng.normal(4.2, 2.1, size=63), 211, 42),
        (rng.normal(0.0, 1.0, size=9), 89, 7001),
    ]
    for data, iters, seed in cases:
        expected = expected_sample(data.copy(), iters=iters, seed=seed)
        actual = submitted.sample(data.copy(), iters=iters, seed=seed)
        assert isinstance(actual, np.ndarray), 'sample must return a NumPy array'
        np.testing.assert_array_equal(actual, expected)


def test_run_sampler_exists_and_runs():
    script_path = '/home/user/run_sampler.py'
    assert os.path.isfile(script_path), f"{script_path} is missing"

    if os.path.exists('/home/user/results.csv'):
        os.remove('/home/user/results.csv')

    result = subprocess.run([sys.executable, script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_sampler.py failed to execute:\n{result.stderr}"
    assert os.path.isfile('/home/user/results.csv'), "run_sampler.py did not generate /home/user/results.csv"


def test_results_csv_correctness():
    data_path = '/home/user/data.npy'
    assert os.path.isfile(data_path), f"{data_path} is missing"

    data = np.load(data_path)
    chain = expected_sample(data, 5000, 42)
    expected_mu_mean = np.mean(chain[1000:, 0])
    expected_sigma_mean = np.mean(chain[1000:, 1])

    results_path = '/home/user/results.csv'
    assert os.path.isfile(results_path), f"{results_path} is missing"

    with open(results_path, 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 2, f"results.csv should contain exactly two comma-separated values, got: {content}"

    try:
        actual_mu_mean = float(parts[0])
        actual_sigma_mean = float(parts[1])
    except ValueError:
        pytest.fail(f"Could not parse results.csv values as floats: {content}")

    assert np.isclose(actual_mu_mean, expected_mu_mean, rtol=1e-4), f"mu_mean is incorrect. Expected approx {expected_mu_mean}, got {actual_mu_mean}"
    assert np.isclose(actual_sigma_mean, expected_sigma_mean, rtol=1e-4), f"sigma_mean is incorrect. Expected approx {expected_sigma_mean}, got {actual_sigma_mean}"


def test_run_sampler_actually_uses_sample_chain():
    log_path = '/tmp/run_sampler_calls.jsonl'
    results_path = '/home/user/results.csv'
    if os.path.exists(log_path):
        os.remove(log_path)
    old_results = open(results_path, 'rb').read() if os.path.exists(results_path) else None

    stub = '''import json
import numpy as np

def sample(data, iters=5000, seed=None):
    with open("/tmp/run_sampler_calls.jsonl", "a") as f:
        f.write(json.dumps({"iters": iters, "seed": seed, "shape": list(np.asarray(data).shape), "sum": float(np.sum(data))}) + "\\n")
    chain = np.zeros((iters, 2), dtype=float)
    chain[1000:, 0] = 123.25
    chain[1000:, 1] = 7.75
    return chain
'''
    original = install_temporary_mcmc(stub)
    try:
        if os.path.exists(results_path):
            os.remove(results_path)
        result = subprocess.run([sys.executable, '/home/user/run_sampler.py'], capture_output=True, text=True)
        assert result.returncode == 0, f"run_sampler.py failed with an instrumented sample:\n{result.stderr}"
        assert os.path.isfile(log_path), 'run_sampler.py did not call mcmc.sample'
        calls = [json.loads(line) for line in open(log_path) if line.strip()]
        assert len(calls) == 1, 'run_sampler.py must invoke sample once for the requested chain'
        assert calls[0]['iters'] == 5000 and calls[0]['seed'] == 42, 'run_sampler.py must call sample with iters=5000 and seed=42'
        data = np.load('/home/user/data.npy')
        assert calls[0]['shape'] == list(data.shape) and np.isclose(calls[0]['sum'], float(np.sum(data))), \
            'run_sampler.py must pass data.npy to sample'
        values = [float(x) for x in open(results_path).read().strip().split(',')]
        np.testing.assert_allclose(values, [123.25, 7.75], rtol=0, atol=0)
    finally:
        restore_mcmc(original)
        if old_results is None:
            if os.path.exists(results_path):
                os.remove(results_path)
        else:
            with open(results_path, 'wb') as f:
                f.write(old_results)


def test_reproducibility_script():
    script_path = '/home/user/test_reproducibility.py'
    assert os.path.isfile(script_path), f"{script_path} is missing"

    result = subprocess.run([sys.executable, script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"test_reproducibility.py failed or chains did not match:\n{result.stderr}"


def test_reproducibility_script_detects_different_chains():
    log_path = '/tmp/reproducibility_calls.jsonl'
    if os.path.exists(log_path):
        os.remove(log_path)
    stub = '''import json
import os
import numpy as np

def sample(data, iters=5000, seed=None):
    with open("/tmp/reproducibility_calls.jsonl", "a") as f:
        f.write(json.dumps({"iters": iters, "seed": seed}) + "\\n")
    count = 1
    if os.path.exists("/tmp/reproducibility_calls.jsonl"):
        count = sum(1 for _ in open("/tmp/reproducibility_calls.jsonl"))
    return np.full((iters, 2), count, dtype=float)
'''
    original = install_temporary_mcmc(stub)
    try:
        result = subprocess.run([sys.executable, '/home/user/test_reproducibility.py'], capture_output=True, text=True)
        assert os.path.isfile(log_path), 'test_reproducibility.py did not call mcmc.sample'
        calls = [json.loads(line) for line in open(log_path) if line.strip()]
        assert len(calls) == 2, 'test_reproducibility.py must call sample twice'
        assert all(c['iters'] == 100 and c['seed'] == 42 for c in calls), \
            'both reproducibility calls must use iters=100 and seed=42'
        assert result.returncode != 0, \
            'test_reproducibility.py did not assert that differing chains are unequal'
    finally:
        restore_mcmc(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
