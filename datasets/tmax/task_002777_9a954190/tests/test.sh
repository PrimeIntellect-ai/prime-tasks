#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import ast
import subprocess


def test_venv_exists():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), "Virtual environment directory /home/user/venv does not exist."
    python_bin = os.path.join(venv_path, "bin", "python")
    assert os.path.isfile(python_bin), f"Python executable not found at {python_bin}."
    return python_bin


python_bin = test_venv_exists()
if os.environ.get("VERIFIER_IN_VENV") != "1":
    env = os.environ.copy()
    env["VERIFIER_IN_VENV"] = "1"
    os.execve(python_bin, [python_bin, __file__], env)

import numpy as np
import scipy.integrate
import emcee
import sklearn
from sklearn.neighbors import KernelDensity
from unittest import mock


def read_source(path):
    with open(path, "r") as f:
        return f.read()


def call_name(call):
    func = call.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return None


def test_vdp_mcmc_updated():
    path = "/home/user/vdp_mcmc.py"
    assert os.path.isfile(path), f"{path} does not exist."
    content = read_source(path)

    # Retain the original assertions.
    assert "solve_ivp" in content, "solve_ivp not found in vdp_mcmc.py."
    assert "BDF" in content, "method='BDF' not found in vdp_mcmc.py."

    tree = ast.parse(content, filename=path)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(call_name(c) == "solve_ivp" for c in calls), "simulate_vdp must call solve_ivp."
    assert any(call_name(c) == "EnsembleSampler" for c in calls), "The emcee EnsembleSampler call is missing."
    assert any(call_name(c) == "run_mcmc" for c in calls), "The MCMC run is missing."
    assert any(call_name(c) == "get_chain" for c in calls), "The sampler chain is not collected."

    # Import and exercise the submitted function rather than trusting source text.
    import importlib.util
    spec = importlib.util.spec_from_file_location("submitted_vdp_mcmc", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "simulate_vdp", None)), "simulate_vdp is not callable."

    captured = []

    class Result:
        def __init__(self, success, value=7.25):
            self.success = success
            self.y = np.array([[value], [0.0]], dtype=float)

    def fake_failure(*args, **kwargs):
        captured.append((args, kwargs))
        return Result(False)

    sentinel = object()
    old_alias = module.__dict__.get("solve_ivp", sentinel)
    module.__dict__["solve_ivp"] = fake_failure
    try:
        with mock.patch("scipy.integrate.solve_ivp", fake_failure):
            assert module.simulate_vdp(2.0) is None, "simulate_vdp must return None when solve_ivp reports failure."
    finally:
        if old_alias is sentinel:
            module.__dict__.pop("solve_ivp", None)
        else:
            module.__dict__["solve_ivp"] = old_alias

    assert captured, "simulate_vdp did not execute solve_ivp."
    args, kwargs = captured[-1]
    t_span = kwargs.get("t_span", args[1] if len(args) > 1 else None)
    y0 = kwargs.get("y0", args[2] if len(args) > 2 else None)
    assert np.allclose(np.asarray(t_span, dtype=float), [0.0, 10.0]), f"Expected t_span=(0, 10), got {t_span}."
    assert np.allclose(np.asarray(y0, dtype=float), [2.0, 0.0]), f"Expected initial state [2, 0], got {y0}."
    assert kwargs.get("method") == "BDF", "solve_ivp must be called with method='BDF'."
    assert np.array_equal(np.asarray(kwargs.get("t_eval"), dtype=float), np.array([10.0])), "solve_ivp must use t_eval=[10.0]."

    def fake_success(*args, **kwargs):
        return Result(True, 7.25)

    old_alias = module.__dict__.get("solve_ivp", sentinel)
    module.__dict__["solve_ivp"] = fake_success
    try:
        with mock.patch("scipy.integrate.solve_ivp", fake_success):
            got = module.simulate_vdp(2.0)
    finally:
        if old_alias is sentinel:
            module.__dict__.pop("solve_ivp", None)
        else:
            module.__dict__["solve_ivp"] = old_alias
    assert np.isclose(got, 7.25), "simulate_vdp must return y[0] at the requested final time."

    # Compare several actual trajectories to independently computed BDF results.
    def deriv(t, y, mu):
        return [y[1], mu * (1.0 - y[0] ** 2) * y[1] - y[0]]

    for mu in (0.23, 1.37, 3.11, 4.73):
        ref = scipy.integrate.solve_ivp(
            lambda t, y: deriv(t, y, mu),
            (0.0, 10.0),
            [2.0, 0.0],
            method="BDF",
            t_eval=[10.0],
        )
        assert ref.success
        actual = module.simulate_vdp(mu)
        assert actual is not None and np.isfinite(actual), f"simulate_vdp failed for mu={mu}."
        assert np.isclose(actual, ref.y[0, -1], rtol=2e-4, atol=2e-5), \
            f"simulate_vdp({mu}) does not match the required BDF integration."


def test_run_mcmc_and_samples():
    path = "/home/user/valid_mu_samples.npy"
    if os.path.exists(path):
        os.remove(path)

    proc = subprocess.run(
        [sys.executable, "/home/user/vdp_mcmc.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=300,
    )
    assert proc.returncode == 0, f"vdp_mcmc.py failed:\n{proc.stdout}\n{proc.stderr}"

    # Retain the original existence assertion, now after a fresh execution.
    assert os.path.isfile(path), f"{path} does not exist. Did the MCMC script run successfully?"
    samples = np.load(path, allow_pickle=False)
    assert samples.ndim in (1, 2), f"Samples must be a flattened one-dimensional chain, got shape {samples.shape}."
    if samples.ndim == 2:
        assert samples.shape[1] == 1, f"Expected one parameter per sample, got shape {samples.shape}."
    flat = samples.reshape(-1)
    assert flat.size == 4000, f"Expected 4000 post-burn-in samples, got {flat.size}."
    assert np.all(np.isfinite(flat)), "MCMC samples contain non-finite values."
    assert np.all((flat > 0.1) & (flat < 5.0)), "MCMC samples violate the unchanged prior bounds."
    assert np.unique(flat).size > 100, "Samples appear fabricated or the chain did not move."
    assert np.std(flat) > 0.01, "Samples are effectively constant; MCMC sampling did not succeed."
    return flat


def test_fit_density_exists_and_structure():
    path = "/home/user/fit_density.py"
    assert os.path.isfile(path), f"{path} does not exist."
    content = read_source(path)
    tree = ast.parse(content, filename=path)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    kde_calls = [c for c in calls if call_name(c) == "KernelDensity"]
    assert kde_calls, "fit_density.py must construct sklearn.neighbors.KernelDensity."
    assert any(call_name(c) == "score_samples" for c in calls), "fit_density.py must use score_samples."

    valid_config = False
    for call in kde_calls:
        keywords = {kw.arg: kw.value for kw in call.keywords if kw.arg is not None}
        kernel = keywords.get("kernel")
        bandwidth = keywords.get("bandwidth")
        if (isinstance(kernel, ast.Constant) and kernel.value == "gaussian" and
                isinstance(bandwidth, ast.Constant) and float(bandwidth.value) == 0.5):
            valid_config = True
    assert valid_config, "KernelDensity must use kernel='gaussian' and bandwidth=0.5."


def test_kde_results(samples):
    path = "/home/user/kde_results.json"
    if os.path.exists(path):
        os.remove(path)

    proc = subprocess.run(
        [sys.executable, "/home/user/fit_density.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, f"fit_density.py failed:\n{proc.stdout}\n{proc.stderr}"
    assert os.path.isfile(path), f"{path} does not exist."

    with open(path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{path} is not a valid JSON file."

    # Retain all original result-shape assertions.
    assert isinstance(results, list), f"Data in {path} must be a JSON list."
    assert len(results) == 5, f"Expected exactly 5 elements in {path}, got {len(results)}."
    for i, val in enumerate(results):
        assert isinstance(val, (int, float)), f"Element at index {i} is not a number: {val}"
        assert val < 0, f"Log-density values should generally be negative, got {val} at index {i}."

    actual = np.asarray(results, dtype=float)
    assert np.all(np.isfinite(actual)), "KDE results contain non-finite values."
    expected = KernelDensity(kernel="gaussian", bandwidth=0.5).fit(samples.reshape(-1, 1)).score_samples(
        np.array([1.0, 2.0, 3.0, 4.0, 5.0]).reshape(-1, 1)
    )
    assert np.allclose(actual, expected, rtol=1e-10, atol=1e-10), \
        f"kde_results.json does not contain the KDE scores derived from the generated samples. Expected {expected.tolist()}, got {results}."


if __name__ == "__main__":
    test_venv_exists()
    test_vdp_mcmc_updated()
    samples = test_run_mcmc_and_samples()
    test_fit_density_exists_and_structure()
    test_kde_results(samples)
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
