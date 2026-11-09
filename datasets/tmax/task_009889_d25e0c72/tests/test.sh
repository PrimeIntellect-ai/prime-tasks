#!/bin/bash
set -e
mkdir -p /logs/verifier
export MPLBACKEND=Agg

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib
import json
import math
import os
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from scipy.integrate import solve_ivp

WORKSPACE = "/home/user/model_fitting"


def run_checked(command, timeout):
    try:
        result = subprocess.run(
            command,
            cwd=WORKSPACE,
            capture_output=True,
            text=True,
            timeout=timeout,
            env={**os.environ, "MPLBACKEND": "Agg"},
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"Command timed out: {' '.join(command)}\n{exc}")
    assert result.returncode == 0, (
        f"Command failed: {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session")
def generated_outputs():
    mcmc_file = os.path.join(WORKSPACE, "mcmc.py")
    plot_script = os.path.join(WORKSPACE, "plot_fit.py")
    assert os.path.isfile(mcmc_file), "mcmc.py is missing."
    assert os.path.isfile(plot_script), "plot_fit.py is missing."

    for name in ("posterior_samples.npy", "map_estimate.json", "fit_plot.png"):
        path = os.path.join(WORKSPACE, name)
        if os.path.lexists(path):
            os.remove(path)

    run_checked([sys.executable, mcmc_file], timeout=240)
    assert os.path.isfile(os.path.join(WORKSPACE, "posterior_samples.npy")), (
        "Running mcmc.py did not create posterior_samples.npy."
    )
    assert os.path.isfile(os.path.join(WORKSPACE, "map_estimate.json")), (
        "Running mcmc.py did not create map_estimate.json."
    )

    run_checked([sys.executable, plot_script], timeout=120)
    assert os.path.isfile(os.path.join(WORKSPACE, "fit_plot.png")), (
        "Running plot_fit.py did not create fit_plot.png."
    )


def test_integrator_test_passes():
    """Keep the supplied integrator regression check."""
    test_file = os.path.join(WORKSPACE, "test_integrator.py")
    assert os.path.isfile(test_file), f"Test file {test_file} is missing."
    result = subprocess.run(
        [sys.executable, "-m", "pytest", test_file],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"pytest on {test_file} failed. Output:\n{result.stdout}\n{result.stderr}"
    )


def test_mcmc_source_uses_required_proposal_construction():
    source_path = os.path.join(WORKSPACE, "mcmc.py")
    assert os.path.isfile(source_path), "mcmc.py is missing."
    source = open(source_path, "r", encoding="utf-8").read()
    tree = ast.parse(source)

    call_names = []
    has_matrix_multiply = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name):
                call_names.append(func.id)
            elif isinstance(func, ast.Attribute):
                call_names.append(func.attr)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.MatMult):
            has_matrix_multiply = True

    assert "cholesky" in call_names, "mcmc.py must compute a Cholesky factor."
    assert "multivariate_normal" not in call_names, (
        "Use the Cholesky factor and a standard-normal vector, not multivariate_normal."
    )
    assert has_matrix_multiply, "The proposal must use a matrix product such as L @ z."
    assert "log_likelihood" in call_names, "run_mcmc must evaluate log_likelihood."


def test_log_likelihood_matches_gaussian_model():
    """Exercise the submitted likelihood on answers independently derived with solve_ivp."""
    sys.path.insert(0, WORKSPACE)
    old_cwd = os.getcwd()
    try:
        os.chdir(WORKSPACE)
        sys.modules.pop("mcmc", None)
        module = importlib.import_module("mcmc")
    finally:
        os.chdir(old_cwd)
        if sys.path and sys.path[0] == WORKSPACE:
            sys.path.pop(0)

    assert callable(getattr(module, "log_likelihood", None))
    data = pd.read_csv(os.path.join(WORKSPACE, "data.csv"))
    times = data["t"].to_numpy(dtype=float)
    observed = data["y"].to_numpy(dtype=float)

    def reference_ll(params):
        omega, gamma = params

        def rhs(t, state):
            y, v = state
            return [v, -(omega ** 2) * y - gamma * v]

        solution = solve_ivp(
            rhs,
            (float(times[0]), float(times[-1])),
            [1.0, 0.0],
            t_eval=times,
            rtol=1e-10,
            atol=1e-12,
        )
        residual = observed - solution.y[0]
        return -0.5 * np.sum((residual / 0.5) ** 2)

    p = np.array([2.0, 0.1])
    q = np.array([1.6, 0.2])
    submitted_delta = float(module.log_likelihood(p) - module.log_likelihood(q))
    expected_delta = float(reference_ll(p) - reference_ll(q))
    assert math.isfinite(submitted_delta)
    assert submitted_delta == pytest.approx(expected_delta, abs=0.15), (
        "log_likelihood does not match the damped-oscillator Gaussian likelihood with sigma=0.5."
    )
    assert module.log_likelihood(np.array([-1.0, 0.1])) == -np.inf
    assert module.log_likelihood(np.array([2.0, -0.1])) == -np.inf


def test_posterior_samples_exist_shape_and_are_a_real_chain(generated_outputs):
    samples_file = os.path.join(WORKSPACE, "posterior_samples.npy")
    assert os.path.isfile(samples_file), (
        f"File {samples_file} is missing. MCMC script may not have saved it."
    )
    samples = np.load(samples_file, allow_pickle=False)

    # Preserve the original shape assertion.
    assert samples.shape == (5000, 2), f"Wrong shape: {samples.shape}"
    assert np.issubdtype(samples.dtype, np.number)
    assert np.all(np.isfinite(samples)), "Posterior samples contain NaN or infinity."
    assert np.all(samples[:, 0] > 0) and np.all(samples[:, 1] > 0), (
        "The chain contains parameters outside the likelihood support."
    )

    unique_count = np.unique(samples, axis=0).shape[0]
    assert unique_count > 50, "posterior_samples.npy is constant or nearly constant."
    assert np.std(samples[1000:, 0]) > 0.005
    assert np.std(samples[1000:, 1]) > 0.0005

    changed = np.count_nonzero(np.any(np.diff(samples, axis=0) != 0, axis=1))
    assert changed > 20, "The chain contains too few accepted proposals."
    assert changed < 4999, "The saved chain has no rejected Metropolis-Hastings proposals."


def test_map_estimate_json_matches_chain_and_data(generated_outputs):
    json_file = os.path.join(WORKSPACE, "map_estimate.json")
    assert os.path.isfile(json_file), f"File {json_file} is missing."
    with open(json_file, "r", encoding="utf-8") as handle:
        try:
            estimate = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_file} is not valid JSON.")

    assert "omega" in estimate, "Key 'omega' missing in map_estimate.json"
    assert "gamma" in estimate, "Key 'gamma' missing in map_estimate.json"
    omega = estimate["omega"]
    gamma = estimate["gamma"]
    assert isinstance(omega, (int, float)) and not isinstance(omega, bool)
    assert isinstance(gamma, (int, float)) and not isinstance(gamma, bool)
    assert math.isfinite(omega) and math.isfinite(gamma)

    # Preserve the original broad range assertions.
    assert 1.0 < omega < 3.0, f"omega value {omega} is too far from expected ~2.0"
    assert 0.0 < gamma < 0.5, f"gamma value {gamma} is too far from expected ~0.1"

    samples = np.load(os.path.join(WORKSPACE, "posterior_samples.npy"), allow_pickle=False)
    burnin_mean = samples[1000:].mean(axis=0)
    assert omega == pytest.approx(float(burnin_mean[0]), abs=1e-8)
    assert gamma == pytest.approx(float(burnin_mean[1]), abs=1e-8)

    data = pd.read_csv(os.path.join(WORKSPACE, "data.csv"))
    t = data["t"].to_numpy(dtype=float)
    y = data["y"].to_numpy(dtype=float)

    def analytic_ll(w, g):
        wd = math.sqrt(w * w - 0.25 * g * g)
        prediction = np.exp(-0.5 * g * t) * (
            np.cos(wd * t) + (g / (2.0 * wd)) * np.sin(wd * t)
        )
        return float(-0.5 * np.sum(((y - prediction) / 0.5) ** 2))

    submitted_ll = analytic_ll(float(omega), float(gamma))
    grid_best = max(
        analytic_ll(w, g)
        for w in np.linspace(1.6, 2.4, 81)
        for g in np.linspace(0.01, 0.35, 51)
    )
    assert submitted_ll >= grid_best - 3.0, (
        "The reported posterior mean does not provide a plausible fit to data.csv."
    )


def test_fit_plot_generated_and_valid(generated_outputs):
    plot_file = os.path.join(WORKSPACE, "fit_plot.png")
    assert os.path.isfile(plot_file), (
        f"File {plot_file} is missing. Visualization script may not have run."
    )
    assert os.path.getsize(plot_file) > 0, f"File {plot_file} is empty."

    with open(plot_file, "rb") as handle:
        assert handle.read(8) == b"\x89PNG\r\n\x1a\n", "fit_plot.png is not a PNG file."

    import matplotlib.image as mpimg
    image = mpimg.imread(plot_file)
    assert image.ndim in (2, 3)
    assert image.shape[0] >= 200 and image.shape[1] >= 300
    pixels = image.reshape(-1, image.shape[-1]) if image.ndim == 3 else image.reshape(-1, 1)
    assert np.unique(pixels, axis=0).shape[0] > 20, "The plot appears blank."

    source = open(os.path.join(WORKSPACE, "plot_fit.py"), "r", encoding="utf-8").read()
    tree = ast.parse(source)
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                calls.append(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                calls.append(node.func.attr)
    assert "read_csv" in calls, "plot_fit.py must load data.csv."
    assert "load" in calls, "plot_fit.py must load posterior_samples.npy."
    assert "scatter" in calls, "plot_fit.py must draw the experimental data as scatter points."
    assert "plot" in calls, "plot_fit.py must draw the fitted model as a line."
    assert "savefig" in calls, "plot_fit.py must save fit_plot.png."
    assert "map_estimate.json" in source
    assert "adaptive_rk4" in source or "solve_ivp" in source, (
        "plot_fit.py must simulate the fitted dynamical model."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
