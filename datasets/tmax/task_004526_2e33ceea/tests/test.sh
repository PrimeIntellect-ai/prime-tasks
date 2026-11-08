#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -rf /tmp/verifier_hook
mkdir -p /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os
import numpy as np

try:
    import struct_stats.hypothesis as _hypothesis

    _real_permutation_test = _hypothesis.permutation_test
    _module_path = os.path.realpath(_hypothesis.__file__)

    def _traced_permutation_test(dist_a, dist_b, n_permutations=5000):
        a = np.asarray(dist_a).copy()
        b = np.asarray(dist_b).copy()
        result = _real_permutation_test(dist_a, dist_b, n_permutations=n_permutations)
        trace_path = os.environ.get('STRUCT_STATS_TRACE')
        if trace_path:
            np.savez(
                trace_path,
                dist_a=a,
                dist_b=b,
                n_permutations=np.asarray(n_permutations),
                returned_stat=np.asarray(result[0]),
                returned_p=np.asarray(result[1]),
            )
            with open(trace_path + '.json', 'w') as f:
                json.dump({'module_path': _module_path}, f)
        return result

    _hypothesis.permutation_test = _traced_permutation_test
except Exception:
    pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import math
import os
import subprocess
import sys

import numpy as np
import pytest


def parse_pdb(filepath):
    coords = []
    with open(filepath, 'r') as f:
        for line in f:
            if line.startswith("ATOM") and line[12:16].strip() == "CA":
                x = float(line[30:38])
                y = float(line[38:46])
                z = float(line[46:54])
                coords.append([x, y, z])
    return np.array(coords)


def generate_ensembles(coords):
    np.random.seed(42)
    n_atoms = coords.shape[0]

    # WT Ensemble: 10,000 conformations, std = 0.2
    wt_noise = np.random.normal(0, 0.2, (10000, n_atoms, 3))
    wt_ensemble = coords + wt_noise

    # Mutant Ensemble: 10,000 conformations, std = 0.5
    mut_noise = np.random.normal(0, 0.5, (10000, n_atoms, 3))
    mut_ensemble = coords + mut_noise

    return wt_ensemble, mut_ensemble


def calc_rg(ensemble):
    centroids = np.mean(ensemble, axis=1, keepdims=True)
    diff = ensemble - centroids
    sq_dist = np.sum(diff**2, axis=2)
    return np.sqrt(np.mean(sq_dist, axis=1))


def get_expected_distributions():
    pdb_path = '/home/user/data/reference.pdb'
    assert os.path.exists(pdb_path), f"Reference PDB missing at {pdb_path}"

    coords = parse_pdb(pdb_path)
    assert len(coords) > 0, "No CA atoms found in reference PDB."

    wt_ens, mut_ens = generate_ensembles(coords)
    return calc_rg(wt_ens), calc_rg(mut_ens)


def independent_permutation_result(dist_a, dist_b, n_permutations):
    diff_obs = np.mean(dist_b) - np.mean(dist_a)
    combined = np.concatenate([dist_a, dist_b])
    n_a = len(dist_a)
    count = 0
    np.random.seed(123)
    for _ in range(n_permutations):
        np.random.shuffle(combined)
        diff_perm = np.mean(combined[n_a:]) - np.mean(combined[:n_a])
        if diff_perm >= diff_obs:
            count += 1
    return float(diff_obs), float(count / n_permutations)


def test_results_json_exists_and_correct():
    script_path = '/home/user/analyze.py'
    results_path = '/home/user/results.json'
    trace_path = '/tmp/struct_stats_trace.npz'

    assert os.path.isfile(script_path), f"Analysis script missing at {script_path}"

    try:
        installed_version = importlib.metadata.version('struct-stats')
    except importlib.metadata.PackageNotFoundError:
        pytest.fail("The struct-stats package is not installed in the Python environment.")
    assert installed_version == '1.1.0', f"Expected installed struct-stats 1.1.0, got {installed_version}"

    for path in (results_path, trace_path, trace_path + '.json'):
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/verifier_hook' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['STRUCT_STATS_TRACE'] = trace_path
    completed = subprocess.run(
        [sys.executable, script_path],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert completed.returncode == 0, (
        f"Running {script_path} failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    assert os.path.exists(results_path), f"Results file missing at {results_path}"
    assert os.path.exists(trace_path), (
        "analyze.py did not call struct_stats.hypothesis.permutation_test"
    )
    assert os.path.exists(trace_path + '.json'), "Missing struct_stats import trace metadata"

    with open(trace_path + '.json') as f:
        trace_meta = json.load(f)
    assert trace_meta.get('module_path'), "The imported struct_stats.hypothesis module has no path"

    with np.load(trace_path) as trace:
        called_a = trace['dist_a']
        called_b = trace['dist_b']
        called_n = int(trace['n_permutations'])
        returned_stat = float(trace['returned_stat'])
        returned_p = float(trace['returned_p'])

    expected_a, expected_b = get_expected_distributions()
    assert called_a.shape == (10000,), "Permutation test WT distribution must contain 10,000 Rg values"
    assert called_b.shape == (10000,), "Permutation test Mutant distribution must contain 10,000 Rg values"
    assert np.allclose(called_a, expected_a, rtol=1e-12, atol=1e-12), (
        "WT values passed to the package permutation test do not match the required simulation"
    )
    assert np.allclose(called_b, expected_b, rtol=1e-12, atol=1e-12), (
        "Mutant values passed to the package permutation test do not match the required simulation"
    )
    assert called_n == 5000, f"Expected 5000 permutations, got {called_n}"

    expected_stat, expected_p = independent_permutation_result(expected_a, expected_b, 5000)
    assert math.isclose(returned_stat, expected_stat, rel_tol=1e-12, abs_tol=1e-12)
    assert math.isclose(returned_p, expected_p, rel_tol=0, abs_tol=1e-12), (
        f"Package permutation test returned p-value {returned_p}, expected {expected_p}"
    )

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {results_path} is not valid JSON.")

    assert 'test_statistic' in data, f"Missing 'test_statistic' key in {results_path}"
    assert 'p_value' in data, f"Missing 'p_value' key in {results_path}"
    assert isinstance(data['test_statistic'], (int, float)) and math.isfinite(data['test_statistic'])
    assert isinstance(data['p_value'], (int, float)) and math.isfinite(data['p_value'])

    agent_stat = data['test_statistic']
    threshold = 0.01
    error = abs(agent_stat - expected_stat) / (abs(expected_stat) + 1e-9)
    assert error <= threshold, (
        f"test_statistic metric failure: agent value {agent_stat} differs from "
        f"expected {expected_stat} by {error*100:.3f}% (threshold is {threshold*100}%)."
    )

    assert math.isclose(agent_stat, returned_stat, rel_tol=1e-12, abs_tol=1e-12), (
        "results.json test_statistic is not the value returned by the package permutation test"
    )
    assert math.isclose(data['p_value'], returned_p, rel_tol=0, abs_tol=1e-12), (
        f"results.json p_value {data['p_value']} is not the package result {returned_p}"
    )
    assert math.isclose(data['p_value'], expected_p, rel_tol=0, abs_tol=1e-12), (
        f"p_value metric failure: agent value {data['p_value']} differs from expected {expected_p}"
    )


def test_vendored_package_fixed():
    setup_path = '/app/vendored/struct-stats-1.1.0/setup.py'
    assert os.path.exists(setup_path), f"Setup file missing at {setup_path}"

    with open(setup_path, 'r') as f:
        content = f.read()

    assert 'numpy==0.1.0' not in content, "The impossible dependency numpy==0.1.0 is still present in setup.py."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
