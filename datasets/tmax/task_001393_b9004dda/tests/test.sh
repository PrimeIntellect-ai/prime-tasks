#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import math
import ctypes
import runpy
import numpy as np
import pytest
import scipy.integrate

PROJECT = "/home/user/sim_project"
LIB_PATH = os.path.join(PROJECT, "librhs.so")
SCRIPT_PATH = os.path.join(PROJECT, "run_sim.py")
JSON_PATH = os.path.join(PROJECT, "convergence_result.json")
RTOLS = [1e-2, 1e-3, 1e-4, 1e-5, 1e-6]
_execution_checked = False


def test_librhs_so_exists_and_loadable():
    """Check that the shared library loads, exports the RHS, and computes it correctly."""
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} does not exist."

    try:
        lib = ctypes.CDLL(LIB_PATH)
    except Exception as e:
        pytest.fail(f"Failed to load {LIB_PATH} using ctypes: {e}")

    assert hasattr(lib, "robertson_rhs"), f"Function 'robertson_rhs' not found in {LIB_PATH}."
    rhs = lib.robertson_rhs
    rhs.argtypes = [ctypes.c_double, ctypes.POINTER(ctypes.c_double), ctypes.POINTER(ctypes.c_double)]
    rhs.restype = None

    for t, values in [(0.0, [1.0, 0.0, 0.0]), (7.25, [0.72, 2.3e-5, 0.279977])]:
        y = (ctypes.c_double * 3)(*values)
        out = (ctypes.c_double * 3)()
        rhs(t, y, out)
        expected = [
            -0.04 * values[0] + 1e4 * values[1] * values[2],
            0.04 * values[0] - 1e4 * values[1] * values[2] - 3e7 * values[1] ** 2,
            3e7 * values[1] ** 2,
        ]
        assert np.allclose(list(out), expected, rtol=1e-13, atol=1e-14)


def test_run_sim_script_exists():
    """Check if the Python simulation script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."


def execute_and_check_script():
    """Execute run_sim.py while recording its ctypes and solve_ivp behavior."""
    global _execution_checked
    if _execution_checked:
        return

    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    original_cdll = ctypes.CDLL
    original_solve_ivp = scipy.integrate.solve_ivp
    loaded_libraries = []
    solve_calls = []
    c_call_count = [0]

    class FunctionProxy:
        def __init__(self, function):
            object.__setattr__(self, "_function", function)

        def __call__(self, *args, **kwargs):
            c_call_count[0] += 1
            return self._function(*args, **kwargs)

        def __getattr__(self, name):
            return getattr(self._function, name)

        def __setattr__(self, name, value):
            if name == "_function":
                object.__setattr__(self, name, value)
            else:
                setattr(self._function, name, value)

    class LibraryProxy:
        def __init__(self, library):
            self._library = library
            self._rhs = FunctionProxy(library.robertson_rhs)

        def __getattr__(self, name):
            if name == "robertson_rhs":
                return self._rhs
            return getattr(self._library, name)

        def __getitem__(self, name):
            if name == "robertson_rhs":
                return self._rhs
            return self._library[name]

    def tracking_cdll(name, *args, **kwargs):
        library = original_cdll(name, *args, **kwargs)
        try:
            resolved = os.path.abspath(os.fspath(name))
        except TypeError:
            resolved = str(name)
        loaded_libraries.append(resolved)
        if resolved == LIB_PATH:
            return LibraryProxy(library)
        return library

    def tracking_solve_ivp(fun, t_span, y0, *args, **kwargs):
        before = c_call_count[0]
        result = original_solve_ivp(fun, t_span, y0, *args, **kwargs)
        solve_calls.append({
            "t_span": tuple(t_span),
            "y0": tuple(float(x) for x in y0),
            "method": kwargs.get("method", "RK45"),
            "rtol": kwargs.get("rtol", 1e-3),
            "atol": kwargs.get("atol", 1e-6),
            "c_calls": c_call_count[0] - before,
            "success": result.success,
        })
        return result

    old_cwd = os.getcwd()
    old_argv = sys.argv[:]
    ctypes.CDLL = tracking_cdll
    scipy.integrate.solve_ivp = tracking_solve_ivp
    try:
        os.chdir(PROJECT)
        sys.argv = [SCRIPT_PATH]
        try:
            runpy.run_path(SCRIPT_PATH, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"run_sim.py exited with status {exc.code}"
    finally:
        ctypes.CDLL = original_cdll
        scipy.integrate.solve_ivp = original_solve_ivp
        os.chdir(old_cwd)
        sys.argv = old_argv

    assert LIB_PATH in loaded_libraries, "run_sim.py did not load librhs.so using ctypes.CDLL."
    assert os.path.isfile(JSON_PATH), "run_sim.py did not create convergence_result.json when executed."

    for requested_rtol in RTOLS:
        matching = []
        for call in solve_calls:
            method = call["method"]
            method_name = method if isinstance(method, str) else getattr(method, "__name__", "")
            try:
                call_rtol = float(call["rtol"])
                call_atol = float(call["atol"])
            except (TypeError, ValueError):
                continue
            if (
                method_name.lower() == "radau"
                and len(call["t_span"]) == 2
                and math.isclose(float(call["t_span"][0]), 0.0, abs_tol=0.0)
                and math.isclose(float(call["t_span"][1]), 1000.0, rel_tol=0.0, abs_tol=1e-12)
                and np.allclose(call["y0"], [1.0, 0.0, 0.0], rtol=0.0, atol=0.0)
                and math.isclose(call_rtol, requested_rtol, rel_tol=1e-12, abs_tol=0.0)
                and math.isclose(call_atol, 1e-3 * requested_rtol, rel_tol=1e-12, abs_tol=0.0)
            ):
                matching.append(call)
        assert matching, f"No Radau solve from 0 to 1000 used rtol={requested_rtol} and atol=1e-3*rtol."
        assert any(call["success"] for call in matching), f"The solve for rtol={requested_rtol} did not succeed."
        assert any(call["c_calls"] > 0 for call in matching), (
            f"The solve for rtol={requested_rtol} did not evaluate the ctypes C RHS."
        )

    _execution_checked = True


def independent_results():
    def rhs(t, y):
        return [
            -0.04 * y[0] + 1e4 * y[1] * y[2],
            0.04 * y[0] - 1e4 * y[1] * y[2] - 3e7 * y[1] ** 2,
            3e7 * y[1] ** 2,
        ]

    finals = {}
    for rtol in RTOLS:
        solution = scipy.integrate.solve_ivp(
            rhs, (0.0, 1000.0), [1.0, 0.0, 0.0],
            method="Radau", rtol=rtol, atol=1e-3 * rtol,
        )
        assert solution.success, solution.message
        finals[rtol] = float(solution.y[0, -1])

    baseline = finals[1e-6]
    threshold = 1e-6
    for rtol in RTOLS[:-1]:
        if abs(finals[rtol] - baseline) < 1e-5:
            threshold = rtol
            break
    return baseline, threshold


def test_convergence_result_json():
    """Execute the simulation and validate its JSON against independent recomputation."""
    execute_and_check_script()
    assert os.path.isfile(JSON_PATH), f"JSON result file {JSON_PATH} does not exist."

    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "baseline_y1" in data, "Key 'baseline_y1' is missing from the JSON file."
    assert "threshold_rtol" in data, "Key 'threshold_rtol' is missing from the JSON file."

    baseline_y1 = data["baseline_y1"]
    threshold_rtol = data["threshold_rtol"]

    assert isinstance(baseline_y1, (int, float)), "baseline_y1 must be a number."
    assert isinstance(threshold_rtol, (int, float)), "threshold_rtol must be a number."
    assert math.isfinite(float(baseline_y1)), "baseline_y1 must be finite."
    assert math.isfinite(float(threshold_rtol)), "threshold_rtol must be finite."

    assert 0.800 < baseline_y1 < 0.805, f"baseline_y1 value {baseline_y1} is out of expected range (0.800 - 0.805)."

    valid_rtols = [1e-2, 1e-3, 1e-4, 1e-5, 1e-6]
    assert threshold_rtol in valid_rtols, f"threshold_rtol {threshold_rtol} is not one of the valid sequence values."

    expected_baseline, expected_threshold = independent_results()
    assert math.isclose(float(baseline_y1), expected_baseline, rel_tol=0.0, abs_tol=5e-9), (
        f"baseline_y1 {baseline_y1} does not match independently recomputed value {expected_baseline}."
    )
    assert float(threshold_rtol) == expected_threshold, (
        f"threshold_rtol {threshold_rtol} does not match independently recomputed value {expected_threshold}."
    )
TEST_EOF

if timeout 180s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
