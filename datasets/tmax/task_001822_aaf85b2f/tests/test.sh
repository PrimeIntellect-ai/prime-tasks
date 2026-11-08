#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import runpy
import sys
import numpy as np
import scipy.integrate

SCRIPT = "/home/user/simulate_and_process.py"


def test_script_exists():
    assert os.path.exists(SCRIPT), f"The script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file."
    with open(SCRIPT, "rb") as f:
        source = f.read()
    assert source.strip(), f"{SCRIPT} is empty."
    compile(source, SCRIPT, "exec")


def test_script_execution_and_pipeline_behavior():
    # Outputs must be freshly produced by executing the submitted artifact.
    for path in ("/home/user/validation_results.csv", "/home/user/max_error.txt"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    real_solve_ivp = scipy.integrate.solve_ivp
    real_rfft = np.fft.rfft
    real_rfftfreq = np.fft.rfftfreq

    solves = []
    fft_matches = set()
    freq_calls = []
    issues = []
    saw_required_array = [False]

    symmetric_hann = np.hanning(1024)
    periodic_hann = 0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(1024) / 1024.0)

    def checked_solve_ivp(*args, **kwargs):
        fun = args[0] if len(args) > 0 else kwargs.get("fun")
        t_span = args[1] if len(args) > 1 else kwargs.get("t_span")
        y0 = args[2] if len(args) > 2 else kwargs.get("y0")
        t_eval = kwargs.get("t_eval")
        method = kwargs.get("method")
        max_step = kwargs.get("max_step")
        ode_args = kwargs.get("args", ())

        try:
            if not np.allclose(np.asarray(t_span, dtype=float), [0.0, 2.0], rtol=0, atol=1e-12):
                issues.append(f"solve_ivp used incorrect t_span: {t_span}")
            y0_arr = np.asarray(y0)
            if y0_arr.size != 1 or not np.iscomplexobj(y0_arr) or not np.allclose(y0_arr.ravel()[0], 1.0 + 0.0j):
                issues.append(f"solve_ivp used incorrect complex initial condition: {y0}")
            expected_t = np.linspace(0.0, 2.0, 1024)
            if t_eval is None or np.asarray(t_eval).shape != (1024,) or not np.allclose(t_eval, expected_t, rtol=0, atol=1e-12):
                issues.append("solve_ivp was not given exactly 1024 evenly spaced t_eval points from 0 to 2")
            if method != "RK45":
                issues.append(f"solve_ivp method was {method!r}, not 'RK45'")
            if max_step is None or not math.isclose(float(max_step), 0.01, rel_tol=0, abs_tol=1e-12):
                issues.append(f"solve_ivp max_step was {max_step!r}, not 0.01")

            derivative = np.asarray(fun(0.0, np.array([1.0 + 0.0j]), *ode_args)).ravel()[0]
            gamma = -float(np.real(derivative))
            frequency = float(np.imag(derivative)) / (2.0 * np.pi)
        except Exception as exc:
            issues.append(f"Could not validate a solve_ivp call: {exc}")
            gamma = float("nan")
            frequency = float("nan")

        result = real_solve_ivp(*args, **kwargs)
        try:
            values = np.asarray(result.y)
            if values.shape != (1, 1024):
                issues.append(f"solve_ivp result had unexpected shape {values.shape}")
            solves.append((gamma, frequency, values[0].real.copy()))
        except Exception as exc:
            issues.append(f"Could not inspect solve_ivp result: {exc}")
        return result

    def checked_rfft(*args, **kwargs):
        data = np.asarray(args[0] if args else kwargs.get("a"))
        n = args[1] if len(args) > 1 else kwargs.get("n")
        axis = args[2] if len(args) > 2 else kwargs.get("axis", -1)
        try:
            axis = int(axis)
            if data.shape[axis] != 1024 or n not in (None, 1024):
                issues.append(f"rfft did not process complete 1024-sample signals: shape={data.shape}, n={n}")
            else:
                vectors = np.moveaxis(data, axis, -1).reshape(-1, 1024)
                for vector in vectors:
                    matches = []
                    for index, (_, _, raw) in enumerate(solves):
                        if (np.allclose(vector, raw * symmetric_hann, rtol=1e-7, atol=1e-9) or
                                np.allclose(vector, raw * periodic_hann, rtol=1e-7, atol=1e-9)):
                            matches.append(index)
                    if len(matches) == 1:
                        fft_matches.add(matches[0])
                    else:
                        issues.append("An rfft input was not a Hann-windowed solve_ivp result")
        except Exception as exc:
            issues.append(f"Could not inspect an rfft call: {exc}")
        return real_rfft(*args, **kwargs)

    def checked_rfftfreq(*args, **kwargs):
        n = args[0] if len(args) > 0 else kwargs.get("n")
        d = args[1] if len(args) > 1 else kwargs.get("d", 1.0)
        freq_calls.append((n, d))
        if n != 1024 or not math.isclose(float(d), 2.0 / 1023.0, rel_tol=0, abs_tol=1e-15):
            issues.append(f"rfftfreq used n={n}, d={d} instead of n=1024, d=2/1023")
        return real_rfftfreq(*args, **kwargs)

    def trace_script(frame, event, arg):
        if frame.f_code.co_filename == SCRIPT:
            if event in ("line", "return"):
                for value in frame.f_locals.values():
                    if isinstance(value, np.ndarray) and value.shape == (2, 3, 1024):
                        saw_required_array[0] = True
            return trace_script
        return None

    scipy.integrate.solve_ivp = checked_solve_ivp
    np.fft.rfft = checked_rfft
    np.fft.rfftfreq = checked_rfftfreq
    old_trace = sys.gettrace()
    try:
        sys.settrace(trace_script)
        runpy.run_path(SCRIPT, run_name="__main__")
    finally:
        sys.settrace(old_trace)
        scipy.integrate.solve_ivp = real_solve_ivp
        np.fft.rfft = real_rfft
        np.fft.rfftfreq = real_rfftfreq

    assert not issues, "; ".join(issues)
    assert len(solves) == 6, f"Expected exactly 6 solve_ivp simulations, observed {len(solves)}."
    observed = {(round(g, 6), round(f, 6)) for g, f, _ in solves}
    expected = {(g, f) for g in (0.1, 0.5) for f in (15.0, 25.0, 35.0)}
    assert observed == expected, f"ODE calls represented parameter pairs {observed}, expected {expected}."
    assert saw_required_array[0], "The script did not store the time-series in a numpy array of shape (2, 3, 1024)."
    assert fft_matches == set(range(6)), "Not all six solve_ivp signals were Hann-windowed and passed to numpy.fft.rfft."
    assert freq_calls, "The script did not call numpy.fft.rfftfreq."
    assert os.path.exists("/home/user/validation_results.csv"), "Execution did not create validation_results.csv."
    assert os.path.exists("/home/user/max_error.txt"), "Execution did not create max_error.txt."


def test_max_error_file():
    file_path = "/home/user/max_error.txt"
    assert os.path.exists(file_path), f"{file_path} does not exist."
    with open(file_path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        assert False, f"Contents of {file_path} could not be parsed as a float. Got: '{content}'"

    assert math.isclose(val, 0.0342, abs_tol=1e-4), f"Expected max_error.txt to contain '0.0342', but got '{content}'."


def test_validation_results_csv():
    file_path = "/home/user/validation_results.csv"
    assert os.path.exists(file_path), f"{file_path} does not exist."

    with open(file_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 7, f"Expected 7 rows (1 header + 6 data) in CSV, got {len(rows)}."

    header = rows[0]
    expected_header = ["gamma", "f_true", "f_peak", "error"]
    assert header == expected_header, f"Expected header {expected_header}, got {header}."

    data_rows = rows[1:]
    gammas = [0.1, 0.5]
    fs = [15.0, 25.0, 35.0]
    expected_combinations = [(g, f) for g in gammas for f in fs]

    for i, (expected_g, expected_f) in enumerate(expected_combinations):
        row = data_rows[i]
        assert len(row) == 4, f"Row {i+1} does not have 4 columns: {row}"

        try:
            g_val = float(row[0])
            f_val = float(row[1])
            f_peak = float(row[2])
            error = float(row[3])
        except ValueError:
            assert False, f"Could not parse numeric values in row {i+1}: {row}"

        assert math.isclose(g_val, expected_g, rel_tol=1e-5), f"Expected gamma {expected_g}, got {g_val}."
        assert math.isclose(f_val, expected_f, rel_tol=1e-5), f"Expected f_true {expected_f}, got {f_val}."

        dt = 2.0 / 1023.0
        df = 1.0 / (1024 * dt)

        if expected_f == 15.0:
            expected_f_peak = 30 * df
        elif expected_f == 25.0:
            expected_f_peak = 50 * df
        elif expected_f == 35.0:
            expected_f_peak = 70 * df
        else:
            expected_f_peak = expected_f

        assert math.isclose(f_peak, expected_f_peak, rel_tol=1e-2), f"Expected f_peak ~{expected_f_peak} for f={expected_f}, got {f_peak}."

        expected_error = abs(expected_f_peak - expected_f)
        assert math.isclose(error, expected_error, rel_tol=1e-2, abs_tol=1e-4), f"Expected error ~{expected_error} for f={expected_f}, got {error}."
TEST_EOF

if timeout 120s python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
