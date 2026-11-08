#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import inspect
import json
import math
import os
import runpy
import sys
import time

import numpy as np
import scipy.integrate
import scipy.stats


def test_profile_script_and_results():
    script_file = "/home/user/profile_ode.py"
    results_file = "/home/user/profile_results.json"

    assert os.path.isfile(script_file), f"File {script_file} not found or is not a regular file."
    os.unlink(results_file) if os.path.exists(results_file) else None

    real_solve_ivp = scipy.integrate.solve_ivp
    real_ttest_ind = scipy.stats.ttest_ind
    real_wasserstein = scipy.stats.wasserstein_distance
    real_perf_counter = time.perf_counter

    events = []
    solve_calls = []
    ttest_calls = []
    wasserstein_calls = []

    solve_signature = inspect.signature(real_solve_ivp)
    ttest_signature = inspect.signature(real_ttest_ind)
    wasserstein_signature = inspect.signature(real_wasserstein)

    def spy_perf_counter():
        value = real_perf_counter()
        events.append(("perf", value))
        return value

    def spy_solve_ivp(*args, **kwargs):
        bound = solve_signature.bind(*args, **kwargs)
        bound.apply_defaults()
        call = {
            "fun": bound.arguments["fun"],
            "t_span": bound.arguments["t_span"],
            "y0": np.asarray(bound.arguments["y0"], dtype=float).copy(),
            "method": bound.arguments["method"],
            "t_eval": None if bound.arguments["t_eval"] is None else np.asarray(bound.arguments["t_eval"], dtype=float).copy(),
            "start_index": len(events),
        }
        events.append(("solve_start", len(solve_calls)))
        solve_calls.append(call)
        result = real_solve_ivp(*args, **kwargs)
        call["result_t"] = np.asarray(result.t, dtype=float).copy()
        call["result_y"] = np.asarray(result.y, dtype=float).copy()
        call["success"] = bool(result.success)
        events.append(("solve_end", len(solve_calls) - 1))
        call["end_index"] = len(events) - 1
        return result

    def spy_ttest_ind(*args, **kwargs):
        bound = ttest_signature.bind(*args, **kwargs)
        bound.apply_defaults()
        result = real_ttest_ind(*args, **kwargs)
        ttest_calls.append({
            "a": np.asarray(bound.arguments["a"], dtype=float).copy(),
            "b": np.asarray(bound.arguments["b"], dtype=float).copy(),
            "equal_var": bound.arguments["equal_var"],
            "statistic": float(result.statistic),
            "pvalue": float(result.pvalue),
        })
        return result

    def spy_wasserstein_distance(*args, **kwargs):
        bound = wasserstein_signature.bind(*args, **kwargs)
        bound.apply_defaults()
        result = real_wasserstein(*args, **kwargs)
        wasserstein_calls.append({
            "u": np.asarray(bound.arguments["u_values"], dtype=float).copy(),
            "v": np.asarray(bound.arguments["v_values"], dtype=float).copy(),
            "result": float(result),
        })
        return result

    scipy.integrate.solve_ivp = spy_solve_ivp
    scipy.stats.ttest_ind = spy_ttest_ind
    scipy.stats.wasserstein_distance = spy_wasserstein_distance
    time.perf_counter = spy_perf_counter

    old_argv = sys.argv[:]
    old_cwd = os.getcwd()
    try:
        sys.argv = [script_file]
        os.chdir("/home/user")
        try:
            runpy.run_path(script_file, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"{script_file} exited with status {exc.code}"
    finally:
        sys.argv = old_argv
        os.chdir(old_cwd)
        time.perf_counter = real_perf_counter
        scipy.integrate.solve_ivp = real_solve_ivp
        scipy.stats.ttest_ind = real_ttest_ind
        scipy.stats.wasserstein_distance = real_wasserstein

    assert os.path.exists(results_file), f"File {results_file} not found."
    with open(results_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {results_file} contains invalid JSON."

    required_keys = ["t_stat", "p_value", "wasserstein_dist"]
    for key in required_keys:
        assert key in data, f"Missing key '{key}' in {results_file}."
        assert isinstance(data[key], (float, int)), f"Key '{key}' must be a float."

    assert len(solve_calls) == 100, f"Expected 100 solve_ivp calls, got {len(solve_calls)}."
    rk_calls = [call for call in solve_calls if call["method"] == "RK45"]
    radau_calls = [call for call in solve_calls if call["method"] == "Radau"]
    assert len(rk_calls) == 50, f"Expected 50 RK45 runs, got {len(rk_calls)}."
    assert len(radau_calls) == 50, f"Expected 50 Radau runs, got {len(radau_calls)}."

    expected_t_eval = np.linspace(0, 15, 300)
    durations = {"RK45": [], "Radau": []}
    for call in solve_calls:
        assert np.allclose(np.asarray(call["t_span"], dtype=float), [0.0, 15.0]), "Incorrect t_span."
        assert np.allclose(call["y0"], [1.0]), "Incorrect initial condition."
        assert call["t_eval"] is not None and np.array_equal(call["t_eval"], expected_t_eval), \
            "t_eval must contain 300 evenly spaced points from 0 to 15 inclusive."
        assert call["success"], "A solve_ivp integration failed."
        assert call["result_y"].shape == (1, 300), "Solver result was not evaluated at all 300 points."

        fun = call["fun"]
        for y in (1.0, 25.0, 50.0, 99.0):
            actual = np.asarray(fun(3.7, np.array([y])), dtype=float).reshape(-1)
            expected = np.array([1.5 * y * (1.0 - y / 100.0)])
            assert np.allclose(actual, expected, rtol=1e-12, atol=1e-12), "Incorrect logistic growth ODE."

        start = call["start_index"]
        end = call["end_index"]
        assert start > 0 and events[start - 1][0] == "perf", \
            "Each integration must be preceded by time.perf_counter()."
        assert end + 1 < len(events) and events[end + 1][0] == "perf", \
            "Each integration must be followed by time.perf_counter()."
        duration = events[end + 1][1] - events[start - 1][1]
        assert duration >= 0
        durations[call["method"]].append(duration)

    matching_ttests = []
    for call in ttest_calls:
        if (call["equal_var"] is False
                and call["a"].shape == (50,)
                and call["b"].shape == (50,)
                and np.allclose(call["a"], durations["RK45"], rtol=1e-9, atol=1e-12)
                and np.allclose(call["b"], durations["Radau"], rtol=1e-9, atol=1e-12)):
            matching_ttests.append(call)
    assert matching_ttests, "Welch's t-test was not performed on the 50 measured timings for each solver."
    assert any(math.isclose(float(data["t_stat"]), call["statistic"], rel_tol=1e-9, abs_tol=1e-12)
               and math.isclose(float(data["p_value"]), call["pvalue"], rel_tol=1e-9, abs_tol=1e-12)
               for call in matching_ttests), "JSON t_stat or p_value does not match the measured Welch t-test."

    first_rk_y = rk_calls[0]["result_y"][0]
    first_radau_y = radau_calls[0]["result_y"][0]
    matching_wasserstein = [
        call for call in wasserstein_calls
        if np.array_equal(call["u"], first_rk_y) and np.array_equal(call["v"], first_radau_y)
    ]
    assert matching_wasserstein, "Wasserstein distance was not computed from the first RK45 and Radau runs."
    assert any(math.isclose(float(data["wasserstein_dist"]), call["result"], rel_tol=1e-9, abs_tol=1e-12)
               for call in matching_wasserstein), "JSON wasserstein_dist does not match the profiled first runs."

    def ode(t, y):
        r = 1.5
        K = 100.0
        return r * y * (1 - y / K)

    sol_rk45 = real_solve_ivp(ode, (0, 15), [1.0], method="RK45", t_eval=expected_t_eval)
    sol_radau = real_solve_ivp(ode, (0, 15), [1.0], method="Radau", t_eval=expected_t_eval)
    expected_wd = real_wasserstein(sol_rk45.y[0], sol_radau.y[0])
    assert math.isclose(data["wasserstein_dist"], expected_wd, abs_tol=1e-5), \
        f"Incorrect wasserstein_dist. Expected {expected_wd}, got {data['wasserstein_dist']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
