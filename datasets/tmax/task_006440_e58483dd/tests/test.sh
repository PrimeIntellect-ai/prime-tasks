#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import ctypes
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest

SOLVER_CPP = '/home/user/solver.cpp'
SOLVER_SO = '/home/user/solver.so'
FIT_MODEL = '/home/user/fit_model.py'
REFERENCE = '/home/user/reference_data.csv'
RESULT = '/home/user/result_sse.txt'


def test_solver_cpp_exists():
    assert os.path.exists(SOLVER_CPP), "The file /home/user/solver.cpp does not exist."
    assert os.path.isfile(SOLVER_CPP), "The path /home/user/solver.cpp is not a regular file."


def test_solver_so_exists():
    assert os.path.exists(SOLVER_SO), "The shared library /home/user/solver.so does not exist."
    assert os.path.isfile(SOLVER_SO), "The path /home/user/solver.so is not a regular file."


def test_fit_model_py_exists():
    assert os.path.exists(FIT_MODEL), "The file /home/user/fit_model.py does not exist."
    assert os.path.isfile(FIT_MODEL), "The path /home/user/fit_model.py is not a regular file."


def test_result_sse_content():
    assert os.path.exists(RESULT), f"The file {RESULT} does not exist."
    with open(RESULT, 'r') as f:
        content = f.read().strip()
    assert content == "0.0850", f"Expected SSE to be '0.0850', but got '{content}'."


def newton_20(p1, p2):
    u = 3.0
    v = 3.0
    for _ in range(20):
        f1 = u * u + p1 * v - 10.0
        f2 = p2 * u + v * v - 10.0
        det = 4.0 * u * v - p1 * p2
        du = (2.0 * v * f1 - p1 * f2) / det
        dv = (-p2 * f1 + 2.0 * u * f2) / det
        u -= du
        v -= dv
    return u, v


def check_library(path):
    try:
        lib = ctypes.CDLL(path)
        solve = lib.solve_system
    except Exception as exc:
        pytest.fail(f"Could not load solve_system from {path}: {exc}")
    solve.argtypes = [ctypes.c_double, ctypes.c_double,
                      ctypes.POINTER(ctypes.c_double), ctypes.POINTER(ctypes.c_double)]
    solve.restype = None
    for p1 in (1.0, 2.0, 3.0, 4.0, 5.0):
        for p2 in (1.0, 2.0, 3.0, 4.0, 5.0):
            u = ctypes.c_double()
            v = ctypes.c_double()
            solve(p1, p2, ctypes.byref(u), ctypes.byref(v))
            expected_u, expected_v = newton_20(p1, p2)
            assert math.isfinite(u.value) and math.isfinite(v.value)
            assert u.value == pytest.approx(expected_u, rel=1e-10, abs=1e-10)
            assert v.value == pytest.approx(expected_v, rel=1e-10, abs=1e-10)


def test_cpp_source_compiles_and_both_libraries_solve_grid():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'rebuilt_solver.so')
        proc = subprocess.run(
            ['g++', '-shared', '-fPIC', '-O2', SOLVER_CPP, '-o', rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        assert proc.returncode == 0, f"solver.cpp did not compile:\n{proc.stderr}"
        check_library(rebuilt)
    check_library(SOLVER_SO)


def run_fit_model():
    proc = subprocess.run(
        ['python3', FIT_MODEL], cwd='/home/user',
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    assert proc.returncode == 0, (
        f"fit_model.py failed with exit code {proc.returncode}:\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")
    assert os.path.isfile(RESULT), "fit_model.py did not create result_sse.txt"
    with open(RESULT) as f:
        value = f.read().strip()
    assert re.fullmatch(r'-?\d+\.\d{4}', value), (
        f"result_sse.txt is not formatted to exactly four decimal places: {value!r}")
    return value


def test_fit_model_executes_with_submitted_solver_and_reference():
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    value = run_fit_model()
    assert value == '0.0850', f"Expected SSE to be '0.0850', but got '{value}'."


def test_fit_model_calls_ctypes_solver_for_entire_grid_and_computes_sse():
    token = uuid.uuid4().hex
    log_path = f'/tmp/solver_calls_{token}.txt'
    shim_cpp = f'/tmp/solver_shim_{token}.cpp'
    shim_so = f'/tmp/solver_shim_{token}.so'

    with open(SOLVER_SO, 'rb') as f:
        original_so = f.read()
    original_so_mode = os.stat(SOLVER_SO).st_mode
    with open(REFERENCE, 'rb') as f:
        original_reference = f.read()
    result_existed = os.path.exists(RESULT)
    original_result = None
    if result_existed:
        with open(RESULT, 'rb') as f:
            original_result = f.read()

    shim_source = r'''#include <cstdio>
extern "C" void solve_system(double p1, double p2, double* u, double* v) {
    FILE* f = std::fopen("LOG_PATH", "a");
    if (f) { std::fprintf(f, "%.17g %.17g\n", p1, p2); std::fclose(f); }
    *u = 1.25 * p1 + 0.5 * p2 + 0.125;
    *v = -0.75 * p1 + 1.5 * p2 + 0.375;
}
'''.replace('LOG_PATH', log_path)

    try:
        with open(shim_cpp, 'w') as f:
            f.write(shim_source)
        proc = subprocess.run(
            ['g++', '-shared', '-fPIC', shim_cpp, '-o', shim_so],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        assert proc.returncode == 0, f"Verifier shim compilation failed: {proc.stderr}"
        os.replace(shim_so, SOLVER_SO)

        rng = random.Random(secrets.randbits(128))
        rows = []
        expected_sse = 0.0
        for p1 in (1.0, 2.0, 3.0, 4.0, 5.0):
            for p2 in (1.0, 2.0, 3.0, 4.0, 5.0):
                u = 1.25 * p1 + 0.5 * p2 + 0.125
                v = -0.75 * p1 + 1.5 * p2 + 0.375
                du = rng.uniform(0.11, 0.39)
                dv = rng.uniform(-0.41, -0.13)
                rows.append((p1, p2, u + du, v + dv))
                expected_sse += du * du + dv * dv

        with open(REFERENCE, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['p1', 'p2', 'u_ref', 'v_ref'])
            writer.writerows(rows)
        if os.path.exists(RESULT):
            os.unlink(RESULT)

        value = run_fit_model()
        assert value == f'{expected_sse:.4f}', (
            f"fit_model.py did not calculate SSE from solver outputs and reference data; "
            f"expected {expected_sse:.4f}, got {value}")

        assert os.path.isfile(log_path), "The Python script did not call solve_system"
        calls = []
        with open(log_path) as f:
            for line in f:
                fields = line.split()
                assert len(fields) == 2, f"Malformed solver call log line: {line!r}"
                calls.append((float(fields[0]), float(fields[1])))
        expected_calls = [(p1, p2) for p1 in (1.0, 2.0, 3.0, 4.0, 5.0)
                          for p2 in (1.0, 2.0, 3.0, 4.0, 5.0)]
        assert len(calls) == 25, f"Expected 25 solve_system calls, got {len(calls)}"
        assert sorted(calls) == sorted(expected_calls), (
            "solve_system was not called exactly once for every point in the 5x5 grid")
    finally:
        restore_tmp = f'/tmp/original_solver_{token}.so'
        with open(restore_tmp, 'wb') as f:
            f.write(original_so)
        os.chmod(restore_tmp, original_so_mode)
        os.replace(restore_tmp, SOLVER_SO)
        with open(REFERENCE, 'wb') as f:
            f.write(original_reference)
        if result_existed:
            with open(RESULT, 'wb') as f:
                f.write(original_result)
        elif os.path.exists(RESULT):
            os.unlink(RESULT)
        for path in (shim_cpp, shim_so, log_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
