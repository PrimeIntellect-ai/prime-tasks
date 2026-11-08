#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import runpy
import sys

import h5py
import numpy as np
import pytest
from scipy.integrate import solve_ivp

PROJECT = "/home/user/project"
RESULTS = os.path.join(PROJECT, "results.txt")
FIT = os.path.join(PROJECT, "fit.py")
DATA = os.path.join(PROJECT, "data.h5")

@pytest.fixture(scope="module")
def executed_fit():
    assert os.path.isfile(FIT), f"Required script {FIT} is missing."
    assert os.path.isfile(DATA), f"Required observation file {DATA} is missing."

    # Ensure the verifier only accepts results produced by this execution.
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    calls = {"log_likelihood": 0, "solve_ode": 0}

    def profiler(frame, event, arg):
        if event == "call" and frame.f_code.co_name in calls:
            calls[frame.f_code.co_name] += 1
        return profiler

    old_cwd = os.getcwd()
    try:
        os.chdir(PROJECT)
        sys.setprofile(profiler)
        namespace = runpy.run_path(FIT, run_name="__main__")
    finally:
        sys.setprofile(None)
        os.chdir(old_cwd)

    return namespace, calls


def test_input_data_is_intact():
    def system(t, state):
        x, v = state
        return [v, -0.5 * v - 2.0 * x]

    expected_t = np.linspace(0, 10, 50)
    expected_sol = solve_ivp(system, [0, 10], [1.0, 0.0], t_eval=expected_t)
    rng = np.random.RandomState(42)
    expected_y = expected_sol.y[0] + rng.normal(0, 0.1, expected_sol.y[0].shape)

    with h5py.File(DATA, "r") as f:
        assert "t" in f and "y" in f, "data.h5 must contain /t and /y."
        np.testing.assert_allclose(f["t"][:], expected_t, rtol=0, atol=1e-12)
        np.testing.assert_allclose(f["y"][:], expected_y, rtol=0, atol=1e-12)


def test_script_executes_and_reads_hdf5(executed_fit):
    namespace, calls = executed_fit
    assert "t_obs" in namespace and "y_obs" in namespace, "fit.py did not load the observations."
    with h5py.File(DATA, "r") as f:
        np.testing.assert_array_equal(namespace["t_obs"], f["t"][:])
        np.testing.assert_array_equal(namespace["y_obs"], f["y"][:])

    # One initial likelihood plus one proposed likelihood per iteration.
    assert calls["log_likelihood"] >= 5001, "fit.py did not run the requested 5000-step MCMC."
    assert calls["solve_ode"] >= 5001, "The MCMC did not evaluate the forward ODE model."


def test_solve_ode_is_stable_and_accurate(executed_fit):
    namespace, _ = executed_fit
    assert "solve_ode" in namespace and callable(namespace["solve_ode"]), "solve_ode is missing."
    candidate = namespace["solve_ode"]

    cases = [
        (0.35, 3.7, np.linspace(0, 9, 73)),
        (1.4, 7.5, np.sort(np.r_[0.0, np.linspace(0.03, 12, 91)])),
        (0.12, 0.8, np.linspace(0, 18, 121)),
    ]
    for c, k, times in cases:
        def rhs(t, state):
            x, v = state
            return [v, -c * v - k * x]

        reference = solve_ivp(
            rhs, [0.0, float(times[-1])], [1.0, 0.0], t_eval=times,
            rtol=1e-10, atol=1e-12
        ).y[0]
        actual = np.asarray(candidate(c, k, times), dtype=float)
        assert actual.shape == times.shape
        assert np.all(np.isfinite(actual)), "solve_ode produced non-finite values."
        np.testing.assert_allclose(actual, reference, rtol=8e-3, atol=8e-3)


def test_mcmc_samples_and_burn_in_result(executed_fit):
    namespace, _ = executed_fit
    assert "samples" in namespace, "fit.py did not retain the MCMC samples."
    samples = np.asarray(namespace["samples"], dtype=float)
    assert samples.shape == (5000, 2), "Expected exactly 5000 samples of (c, k)."
    assert np.all(np.isfinite(samples))
    assert np.all(samples > 0), "MCMC samples violate the positive-parameter prior."

    unique = np.unique(samples, axis=0)
    assert len(unique) > 20, "The MCMC chain did not explore the parameter space."
    repeated_steps = np.sum(np.all(np.diff(samples, axis=0) == 0, axis=1))
    assert repeated_steps > 0, "The chain does not contain Metropolis-Hastings rejections."

    expected_c, expected_k = np.mean(samples[1000:], axis=0)
    expected_text = f"c_mean: {expected_c:.2f}\nk_mean: {expected_k:.2f}\n"
    with open(RESULTS, "r") as f:
        assert f.read() == expected_text, "results.txt is not the mean of samples 1000:5000 in the required format."


def test_results_file_exists(executed_fit):
    """Check if the results.txt file has been created."""
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."


def test_results_content_and_accuracy(executed_fit):
    """Parse results.txt and verify that c_mean and k_mean are within the expected ranges."""
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."

    with open(RESULTS, "r") as f:
        content = f.read()

    c_match = re.search(r'c_mean:\s*([0-9.]+)', content)
    k_match = re.search(r'k_mean:\s*([0-9.]+)', content)

    assert c_match is not None, "Could not find 'c_mean: X.XX' in results.txt."
    assert k_match is not None, "Could not find 'k_mean: Y.YY' in results.txt."

    try:
        c_mean = float(c_match.group(1))
        k_mean = float(k_match.group(1))
    except ValueError:
        pytest.fail("Found c_mean or k_mean, but the values are not valid numbers.")

    assert 0.4 <= c_mean <= 0.6, f"c_mean {c_mean} is not within the expected range [0.4, 0.6]."
    assert 1.9 <= k_mean <= 2.1, f"k_mean {k_mean} is not within the expected range [1.9, 2.1]."
TEST_EOF

if timeout 240s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
