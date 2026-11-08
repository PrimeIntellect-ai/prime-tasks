#!/bin/bash
mkdir -p /logs/verifier
status=0

# Exercise the required pipeline, and independently run the submitted regression suite.
timeout 240s /bin/bash /home/user/run_pipeline.sh >/tmp/pipeline.log 2>&1 || status=1
timeout 120s python3 -m pytest /home/user/test_analyze.py -q >/tmp/submitted_pytest.log 2>&1 || status=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import math
import os
import stat
import uuid

import numpy as np
import pytest
import scipy.optimize


def load_analyze():
    name = "submitted_analyze_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(name, "/home/user/analyze.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reference_mcmc(times, gcs, steps, seed):
    times = np.asarray(times, dtype=float)
    gcs = np.asarray(gcs, dtype=float)
    gc0 = gcs[0]

    def log_posterior(c, k):
        if not (0.0 <= c <= 1.0 and 0.0 <= k <= 5.0):
            return -np.inf
        mu = c + (gc0 - c) * np.exp(-k * times)
        return -0.5 * np.sum(((gcs - mu) / 0.02) ** 2)

    np.random.seed(seed)
    c, k = 0.5, 1.0
    current_lp = log_posterior(c, k)
    chain = []
    for _ in range(steps):
        proposal_c = np.random.normal(c, 0.05)
        proposal_k = np.random.normal(k, 0.05)
        proposal_lp = log_posterior(proposal_c, proposal_k)
        if np.log(np.random.random()) < proposal_lp - current_lp:
            c, k = proposal_c, proposal_k
            current_lp = proposal_lp
        chain.append((c, k))
    kept = np.asarray(chain[5000:], dtype=float)
    return tuple(np.mean(kept, axis=0))


def test_files_exist_and_permissions():
    analyze_path = "/home/user/analyze.py"
    test_analyze_path = "/home/user/test_analyze.py"
    run_pipeline_path = "/home/user/run_pipeline.sh"

    assert os.path.isfile(analyze_path), f"Missing {analyze_path}"
    assert os.path.isfile(test_analyze_path), f"Missing {test_analyze_path}"
    assert os.path.isfile(run_pipeline_path), f"Missing {run_pipeline_path}"
    st = os.stat(run_pipeline_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{run_pipeline_path} is not executable"


def test_results_json_keys_and_values():
    results_path = "/home/user/results.json"
    assert os.path.isfile(results_path), f"Missing {results_path}"
    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} is not a valid JSON file.")

    expected_keys = {"opt_C", "opt_k", "factor_x", "mcmc_C", "mcmc_k"}
    assert set(results.keys()) == expected_keys, f"Expected keys {expected_keys}, got {set(results.keys())}"

    opt_C = results["opt_C"]
    opt_k = results["opt_k"]
    factor_x = results["factor_x"]
    mcmc_C = results["mcmc_C"]
    mcmc_k = results["mcmc_k"]

    for name, value in results.items():
        assert isinstance(value, (int, float)), f"{name} must be a number"
        assert math.isfinite(value), f"{name} must be finite"

    assert 0.45 < opt_C < 0.65, f"opt_C {opt_C} is out of expected range (0.45, 0.65)"
    assert 0.2 < opt_k < 0.4, f"opt_k {opt_k} is out of expected range (0.2, 0.4)"
    equation_val = factor_x**3 + 2 * factor_x - opt_C
    assert abs(equation_val) < 1e-3, f"factor_x {factor_x} does not satisfy the equation for C={opt_C}"
    assert 0.45 < mcmc_C < 0.65, f"mcmc_C {mcmc_C} is out of expected range (0.45, 0.65)"
    assert 0.2 < mcmc_k < 0.4, f"mcmc_k {mcmc_k} is out of expected range (0.2, 0.4)"


def test_optimize_params_uses_curve_fit_and_recovers_hidden_cases(monkeypatch):
    called = {"value": False}
    original = scipy.optimize.curve_fit

    def wrapped(*args, **kwargs):
        called["value"] = True
        return original(*args, **kwargs)

    monkeypatch.setattr(scipy.optimize, "curve_fit", wrapped)
    analyze = load_analyze()
    times = np.array([0.0, 0.17, 0.8, 1.9, 3.4, 5.2, 8.1])
    true_c, true_k, gc0 = 0.731, 0.417, 0.286
    gcs = true_c + (gc0 - true_c) * np.exp(-true_k * times)
    c, k = analyze.optimize_params(times, gcs)
    assert called["value"], "optimize_params did not call scipy.optimize.curve_fit"
    assert isinstance(c, (int, float, np.floating))
    assert isinstance(k, (int, float, np.floating))
    assert abs(float(c) - true_c) < 1e-4
    assert abs(float(k) - true_k) < 1e-4


def test_structural_solver_uses_scipy_and_solves_multiple_inputs(monkeypatch):
    calls = {"fsolve": 0, "root": 0}
    original_fsolve = scipy.optimize.fsolve
    original_root = scipy.optimize.root

    def wrapped_fsolve(*args, **kwargs):
        calls["fsolve"] += 1
        return original_fsolve(*args, **kwargs)

    def wrapped_root(*args, **kwargs):
        calls["root"] += 1
        return original_root(*args, **kwargs)

    monkeypatch.setattr(scipy.optimize, "fsolve", wrapped_fsolve)
    monkeypatch.setattr(scipy.optimize, "root", wrapped_root)
    analyze = load_analyze()
    for c in (0.137, 0.812, 3.0, -0.43):
        x = analyze.solve_structural_factor(c)
        assert isinstance(x, (int, float, np.floating))
        assert abs(float(x) ** 3 + 2.0 * float(x) - c) < 1e-8
    assert calls["fsolve"] + calls["root"] > 0, "solve_structural_factor did not use fsolve or root"


def test_mcmc_matches_independent_metropolis_hastings_calculation():
    analyze = load_analyze()
    times = np.linspace(0.0, 7.0, 18)
    gc0, true_c, true_k = 0.24, 0.77, 0.63
    base = true_c + (gc0 - true_c) * np.exp(-true_k * times)
    noise = np.array([0.0, .004, -.006, .003, -.002, .005, -.004, .001, -.003,
                      .002, -.001, .004, -.005, .003, -.002, .001, -.003, .002])
    gcs = base + noise
    steps, seed = 7500, 9137
    expected_c, expected_k = reference_mcmc(times, gcs, steps, seed)
    got_c, got_k = analyze.mcmc_sample(times, gcs, steps=steps, seed=seed)
    assert np.isfinite(got_c) and np.isfinite(got_k)
    assert abs(float(got_c) - expected_c) < 0.015
    assert abs(float(got_k) - expected_k) < 0.05

    repeated = analyze.mcmc_sample(times, gcs, steps=steps, seed=seed)
    assert float(repeated[0]) == pytest.approx(float(got_c), abs=1e-12)
    assert float(repeated[1]) == pytest.approx(float(got_k), abs=1e-12)


def test_pipeline_results_were_computed_by_submitted_functions():
    analyze = load_analyze()
    data = np.genfromtxt("/home/user/observations.csv", delimiter=",", names=True)
    times = np.asarray(data["time"], dtype=float)
    gcs = np.asarray(data["gc_content"], dtype=float)
    expected_c, expected_k = analyze.optimize_params(times, gcs)
    expected_x = analyze.solve_structural_factor(expected_c)
    expected_mc, expected_mk = analyze.mcmc_sample(times, gcs)
    with open("/home/user/results.json") as f:
        results = json.load(f)
    assert results["opt_C"] == pytest.approx(float(expected_c), abs=1e-8)
    assert results["opt_k"] == pytest.approx(float(expected_k), abs=1e-8)
    assert results["factor_x"] == pytest.approx(float(expected_x), abs=1e-8)
    assert results["mcmc_C"] == pytest.approx(float(expected_mc), abs=1e-8)
    assert results["mcmc_k"] == pytest.approx(float(expected_mk), abs=1e-8)


def test_test_analyze_py_contents():
    test_analyze_path = "/home/user/test_analyze.py"
    with open(test_analyze_path, "r") as f:
        content = f.read()
    assert "def test_solve_structural" in content, "Missing test_solve_structural() in test_analyze.py"
    assert "def test_optimize_params" in content, "Missing test_optimize_params() in test_analyze.py"
    assert "pytest" in content, "pytest is not imported or used in test_analyze.py"

    tree = ast.parse(content)
    functions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
    for name in ("test_solve_structural", "test_optimize_params"):
        assert name in functions
        assert any(isinstance(node, ast.Assert) for node in ast.walk(functions[name])), f"{name} has no assertion"
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                calls.append(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                calls.append(node.func.attr)
    assert "solve_structural_factor" in calls
    assert "optimize_params" in calls


def test_run_pipeline_contents():
    run_pipeline_path = "/home/user/run_pipeline.sh"
    with open(run_pipeline_path, "r") as f:
        content = f.read()
    assert "pip" in content and "install" in content, "run_pipeline.sh does not install dependencies"
    assert "pytest" in content, "run_pipeline.sh does not run pytest"
    assert "python" in content and "analyze.py" in content, "run_pipeline.sh does not execute analyze.py"
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short >/tmp/verifier_pytest.log 2>&1 || status=1

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
