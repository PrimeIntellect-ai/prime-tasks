#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import inspect
import os
import numpy as np
import pytest


def test_simulate_py_fixed():
    path = '/home/user/simulate.py'
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r') as f:
        content = f.read()

    assert 'def run_simulation' in content, "simulate.py is missing 'run_simulation' function"

    # Preserve the original source-level checks.
    has_bdf = 'BDF' in content
    has_radau = 'Radau' in content
    has_lsoda = 'LSODA' in content
    assert has_bdf or has_radau or has_lsoda, "simulate.py must use a stiff solver like 'BDF' or 'Radau'"
    assert '1e-6' in content or '10**-6' in content, "simulate.py is missing rtol=1e-6"
    assert '1e-9' in content or '10**-9' in content, "simulate.py is missing atol=1e-9"


def test_analysis_results_file_exists():
    path = '/home/user/analysis_results.h5'
    assert os.path.isfile(path), f"Missing file: {path}"


def test_simulations_and_analysis_results():
    import h5py
    import scipy.integrate

    results_path = '/home/user/analysis_results.h5'
    data_path = '/home/user/observational_data.h5'
    simulate_path = '/home/user/simulate.py'
    assert os.path.isfile(results_path), f"Missing file: {results_path}"
    assert os.path.isfile(data_path), f"Missing file: {data_path}"

    with h5py.File(data_path, 'r') as f:
        t_eval = np.asarray(f['time'], dtype=float)
        observed_y1 = np.asarray(f['y1'], dtype=float)

    assert t_eval.shape == (500,)
    assert observed_y1.shape == (500,)

    candidates = np.array([950, 990, 1000, 1010, 1050])
    real_solve_ivp = scipy.integrate.solve_ivp
    signature = inspect.signature(real_solve_ivp)
    calls = []

    def checked_solve_ivp(*args, **kwargs):
        bound = signature.bind_partial(*args, **kwargs)
        bound.apply_defaults()
        values = bound.arguments

        method = values['method']
        method_name = method if isinstance(method, str) else getattr(method, '__name__', '')
        assert method_name.upper() in {'BDF', 'RADAU', 'LSODA'}, \
            f"run_simulation used non-stiff method {method_name!r}"
        assert np.isclose(float(values['rtol']), 1e-6, rtol=0, atol=1e-15), \
            f"run_simulation used rtol={values['rtol']}, expected 1e-6"
        assert np.isclose(float(values['atol']), 1e-9, rtol=0, atol=1e-18), \
            f"run_simulation used atol={values['atol']}, expected 1e-9"

        supplied_times = np.asarray(values['t_eval'], dtype=float)
        np.testing.assert_array_equal(supplied_times, t_eval)
        np.testing.assert_allclose(values['t_span'], (t_eval[0], t_eval[-1]), rtol=0, atol=0)
        np.testing.assert_allclose(values['y0'], [2.0, 0.0], rtol=0, atol=0)

        ode_args = values.get('args')
        assert ode_args is not None and len(ode_args) == 1, "solve_ivp must receive mu as its ODE argument"
        mu = float(ode_args[0])

        # Verify that the function supplied to solve_ivp is the Van der Pol system.
        probe_y = np.array([0.5, -0.25])
        actual_rhs = np.asarray(values['fun'](12.345, probe_y, *ode_args), dtype=float)
        expected_rhs = np.array([
            probe_y[1],
            mu * (1.0 - probe_y[0] ** 2) * probe_y[1] - probe_y[0]
        ])
        np.testing.assert_allclose(actual_rhs, expected_rhs, rtol=1e-12, atol=1e-12)

        solution = real_solve_ivp(*args, **kwargs)
        assert solution.success, f"solve_ivp failed for mu={mu}: {solution.message}"
        calls.append((mu, solution))
        return solution

    # Patch before import so both module-level aliases and scipy.integrate calls are observed.
    scipy.integrate.solve_ivp = checked_solve_ivp
    try:
        spec = importlib.util.spec_from_file_location('submitted_simulate', simulate_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert hasattr(module, 'run_simulation'), "simulate.py is missing run_simulation"

        modeled = []
        for mu in candidates:
            before = len(calls)
            prediction = np.asarray(module.run_simulation(int(mu), t_eval), dtype=float)
            new_calls = calls[before:]
            matching = [(called_mu, sol) for called_mu, sol in new_calls if called_mu == float(mu)]
            assert matching, f"run_simulation({mu}) did not call solve_ivp with that mu"
            solution = matching[-1][1]

            assert prediction.shape == observed_y1.shape, \
                f"run_simulation({mu}) returned shape {prediction.shape}, expected {observed_y1.shape}"
            assert np.all(np.isfinite(prediction)), f"run_simulation({mu}) returned non-finite values"
            np.testing.assert_allclose(
                prediction, np.asarray(solution.y[0]), rtol=1e-10, atol=1e-12,
                err_msg=f"run_simulation({mu}) did not return solve_ivp's y1 prediction"
            )
            modeled.append(prediction)
    finally:
        scipy.integrate.solve_ivp = real_solve_ivp

    computed_chi_squared = np.array([
        np.sum((observed_y1 - prediction) ** 2 / 0.1) / (len(observed_y1) - 1)
        for prediction in modeled
    ])
    assert np.all(np.isfinite(computed_chi_squared))
    assert np.all(computed_chi_squared >= 0)
    computed_best_mu = int(candidates[np.argmin(computed_chi_squared)])

    with h5py.File(results_path, 'r') as f:
        # Preserve all original result assertions.
        assert 'mu_tested' in f, "Missing dataset 'mu_tested' in analysis_results.h5"
        mu_tested = np.array(f['mu_tested'])
        np.testing.assert_array_equal(mu_tested, candidates, err_msg="mu_tested dataset does not match expected values")

        assert 'chi_squared' in f, "Missing dataset 'chi_squared' in analysis_results.h5"
        chi_squared = np.array(f['chi_squared'])
        assert len(chi_squared) == 5, f"Expected 5 elements in chi_squared, got {len(chi_squared)}"

        assert 'best_mu' in f.attrs, "Missing attribute 'best_mu' on the root group"
        best_mu = f.attrs['best_mu']
        assert best_mu == 1000, f"Expected best_mu to be 1000, got {best_mu}"

        idx_1000 = np.where(mu_tested == 1000)[0][0]
        chi2_1000 = chi_squared[idx_1000]
        assert chi2_1000 < 1e-4, f"Expected chi_squared for mu=1000 to be very small, got {chi2_1000}"

        # Require the stored statistics to equal values recomputed from actual simulations.
        assert chi_squared.shape == (5,), f"Expected chi_squared shape (5,), got {chi_squared.shape}"
        np.testing.assert_allclose(
            chi_squared, computed_chi_squared, rtol=1e-6, atol=1e-10,
            err_msg="chi_squared does not match statistics recomputed from observational data and run_simulation"
        )
        assert int(best_mu) == computed_best_mu, \
            f"best_mu={best_mu} does not match recomputed best mu={computed_best_mu}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
