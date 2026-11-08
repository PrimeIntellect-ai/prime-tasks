#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import math
import os
import shutil
import subprocess
import tempfile
import time

import numpy as np
import pytest
from scipy.optimize import curve_fit

SO_FILE = "/home/user/src/libtensor.so"
SCRIPT_FILE = "/home/user/profile_ops.py"
RESULTS_FILE = "/home/user/profiling_results.json"
EXPECTED_N = [50, 100, 150, 200, 250]


def load_and_check_results(path=RESULTS_FILE):
    assert os.path.isfile(path), f"Results file {path} does not exist."
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    required_keys = {"N_values", "times", "exponent_b"}
    assert required_keys.issubset(data.keys()), f"JSON missing keys. Expected {required_keys}, found {list(data.keys())}."
    assert data["N_values"] == EXPECTED_N, f"Expected N_values {EXPECTED_N}, got {data['N_values']}."

    times = data["times"]
    assert isinstance(times, list), "'times' should be a list."
    assert len(times) == 5, f"Expected 5 time values, got {len(times)}."
    assert all(isinstance(t, (int, float)) for t in times), "All time values must be numeric."

    b = data["exponent_b"]
    assert isinstance(b, (int, float)), "'exponent_b' must be numeric."
    assert 2.5 <= b <= 3.5, f"Exponent {b} is far from the expected ~3.0 (must be between 2.5 and 3.5)."

    assert not isinstance(b, bool) and math.isfinite(float(b))
    assert all(not isinstance(t, bool) and math.isfinite(float(t)) and float(t) > 0 for t in times)

    def model(n, a, exponent):
        return a * np.power(n, exponent)

    fitted, _ = curve_fit(
        model,
        np.asarray(EXPECTED_N, dtype=float),
        np.asarray(times, dtype=float),
        p0=(max(float(times[0]), 1e-12) / (50.0 ** 3), 3.0),
        maxfev=20000,
    )
    fitted_b = float(fitted[1])
    assert math.isfinite(fitted_b)
    assert abs(float(b) - round(fitted_b, 2)) <= 0.011, (
        f"exponent_b={b} is not the exponent obtained by fitting the recorded times "
        f"(expected {round(fitted_b, 2)})."
    )
    return data


def run_profile_script():
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    completed = subprocess.run(
        ["python3", SCRIPT_FILE],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, (
        f"profile_ops.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS_FILE), "Executing profile_ops.py did not create profiling_results.json."
    return load_and_check_results()


def test_libtensor_so_exists():
    """Test that the compiled shared library exists."""
    assert os.path.isfile(SO_FILE), f"Compiled library {SO_FILE} does not exist."


def test_profile_ops_script_exists():
    """Test that the profiling script exists."""
    assert os.path.isfile(SCRIPT_FILE), f"Profiling script {SCRIPT_FILE} does not exist."


def test_profiling_results_json():
    """Test that the profiling results JSON exists and has the correct structure/values."""
    load_and_check_results()


def test_library_script_and_measurements_are_real():
    with open(SO_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libtensor.so is not an ELF binary."
    subprocess.run(["readelf", "-h", SO_FILE], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    symbols = subprocess.run(
        ["nm", "-D", SO_FILE], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ).stdout
    assert "compute_interactions" in symbols, "libtensor.so does not export compute_interactions."

    lib = ctypes.CDLL(SO_FILE)
    assert hasattr(lib, "compute_interactions"), "The shared library cannot load compute_interactions."
    fn = lib.compute_interactions
    fn.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    fn.restype = None

    direct_times = []
    for n in (80, 140, 200, 250):
        arr = np.random.default_rng(901 + n).random((n, n), dtype=np.float64)
        samples = []
        for _ in range(2):
            start = time.perf_counter()
            fn(arr.ctypes.data_as(ctypes.POINTER(ctypes.c_double)), n)
            samples.append(time.perf_counter() - start)
        direct_times.append(min(samples))
    direct_b = float(np.polyfit(np.log([80, 140, 200, 250]), np.log(direct_times), 1)[0])
    assert 2.3 <= direct_b <= 3.7, (
        f"compute_interactions does not exhibit the expected cubic scaling when called directly; "
        f"measured exponent was {direct_b:.2f}."
    )

    source = open(SCRIPT_FILE, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=SCRIPT_FILE)
    assert "ctypes" in source, "profile_ops.py must use ctypes."
    assert SO_FILE in source, f"profile_ops.py must load {SO_FILE}."
    assert "curve_fit" in source, "profile_ops.py must use scipy.optimize.curve_fit."
    attrs_assigned = {
        node.targets[0].attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Assign)
        and len(node.targets) == 1
        and isinstance(node.targets[0], ast.Attribute)
    }
    assert "argtypes" in attrs_assigned and "restype" in attrs_assigned, (
        "profile_ops.py must configure compute_interactions.argtypes and restype."
    )
    called_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                called_names.add(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                called_names.add(node.func.attr)
    assert "curve_fit" in called_names, "profile_ops.py does not call curve_fit."
    assert "perf_counter" in called_names, "profile_ops.py must measure calls with a wall-clock timer such as time.perf_counter."
    assert "min" in called_names, "profile_ops.py must take the minimum of repeated timings."

    # First execute the submitted script against the submitted library.
    actual_data = run_profile_script()
    actual_result_bytes = open(RESULTS_FILE, "rb").read()

    # Replace the library temporarily with an instrumented shared library. This
    # verifies that the script really loads it, supplies valid random N x N
    # arrays, invokes each requested size three times, and reports measured minima.
    probe_c = r'''
#include <stdio.h>
#include <time.h>
#include <math.h>

static int counts[5] = {0,0,0,0,0};
static int index_for(int n) {
    int vals[5] = {50,100,150,200,250};
    for (int i=0;i<5;i++) if (vals[i] == n) return i;
    return -1;
}
void compute_interactions(double *A, int N) {
    int idx = index_for(N);
    int ok = (idx >= 0 && A != NULL);
    double lo = 2.0, hi = -1.0;
    if (ok) {
        for (long long i=0; i<(long long)N*N; i++) {
            double x=A[i];
            if (!isfinite(x) || x < 0.0 || x > 1.0) ok=0;
            if (x < lo) lo=x;
            if (x > hi) hi=x;
        }
        if (!(hi > lo)) ok=0;
    }
    int occurrence = idx >= 0 ? ++counts[idx] : 1;
    FILE *f=fopen("/tmp/tensor_probe_calls.log", "a");
    if (f) { fprintf(f, "%d %d %d\n", N, occurrence, ok); fclose(f); }
    long long factor = occurrence == 1 ? 25 : (occurrence == 2 ? 20 : 15);
    long long ns = factor * (long long)N*N*N;
    struct timespec ts = { ns / 1000000000LL, ns % 1000000000LL };
    nanosleep(&ts, NULL);
}
'''
    backup = tempfile.mktemp(prefix="libtensor-backup-", suffix=".so")
    probe_src = tempfile.mktemp(prefix="tensor-probe-", suffix=".c")
    probe_so = tempfile.mktemp(prefix="tensor-probe-", suffix=".so")
    shutil.copy2(SO_FILE, backup)
    try:
        with open(probe_src, "w") as f:
            f.write(probe_c)
        subprocess.run(["gcc", "-shared", "-fPIC", probe_src, "-o", probe_so], check=True)
        shutil.copy2(probe_so, SO_FILE)
        if os.path.exists("/tmp/tensor_probe_calls.log"):
            os.remove("/tmp/tensor_probe_calls.log")

        probe_data = run_profile_script()
        assert os.path.isfile("/tmp/tensor_probe_calls.log"), "The profiling script never called the loaded C function."
        with open("/tmp/tensor_probe_calls.log") as f:
            calls = [tuple(map(int, line.split())) for line in f if line.strip()]
        expected_calls = [(n, repetition, 1) for n in EXPECTED_N for repetition in (1, 2, 3)]
        assert calls == expected_calls, (
            "compute_interactions must be called exactly three times for each requested N, in order, "
            "with valid float64 array data."
        )

        for n, measured in zip(EXPECTED_N, probe_data["times"]):
            expected_minimum = 15e-9 * (n ** 3)
            assert 0.90 * expected_minimum <= float(measured) <= 3.0 * expected_minimum, (
                f"Reported time {measured} for N={n} is not the measured minimum of the instrumented calls."
            )
    finally:
        shutil.copy2(backup, SO_FILE)
        with open(RESULTS_FILE, "wb") as f:
            f.write(actual_result_bytes)
        for path in (backup, probe_src, probe_so, "/tmp/tensor_probe_calls.log"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    # Ensure the restored result remains the real run against the submitted library.
    restored = load_and_check_results()
    assert restored == actual_data
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
