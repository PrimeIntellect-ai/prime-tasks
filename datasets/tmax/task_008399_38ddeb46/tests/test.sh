#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib
import math
import os
import pstats
import runpy
import subprocess
import sys

import numpy as np
import pytest

SIM_PROJECT_DIR = "/home/user/sim_project"


def test_libkernel_so_exists():
    so_path = os.path.join(SIM_PROJECT_DIR, "libkernel.so")
    assert os.path.isfile(so_path), f"{so_path} does not exist. Did you compile the C kernel?"


def test_libkernel_is_loadable_and_correct():
    so_path = os.path.join(SIM_PROJECT_DIR, "libkernel.so")
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libkernel.so is not an ELF shared library"

    try:
        lib = ctypes.CDLL(so_path)
        fn = lib.process_chunk
    except Exception as exc:
        pytest.fail(f"Could not load process_chunk from libkernel.so: {exc}")

    fn.argtypes = [
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=1, flags="C_CONTIGUOUS"),
        np.ctypeslib.ndpointer(dtype=np.float64, ndim=1, flags="C_CONTIGUOUS"),
        ctypes.c_int,
    ]
    fn.restype = None

    rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
    data = rng.uniform(-3.0, 3.0, 37).astype(np.float64)
    actual = np.empty_like(data)
    fn(data, actual, data.size)

    expected = np.empty_like(data)
    for i, value in enumerate(data):
        value = float(value)
        for _ in range(50):
            value = math.sin(value) * math.cos(value) + 0.1
        expected[i] = value
    np.testing.assert_allclose(actual, expected, rtol=1e-7, atol=1e-7)


def test_fast_solver_py():
    py_path = os.path.join(SIM_PROJECT_DIR, "fast_solver.py")
    assert os.path.isfile(py_path), f"{py_path} does not exist."
    with open(py_path, "r") as f:
        content = f.read()

    assert "def parallel_solve" in content, "parallel_solve function not found in fast_solver.py"
    assert "ctypes" in content, "ctypes module not imported/used in fast_solver.py"
    assert "multiprocessing" in content or "concurrent.futures" in content, "multiprocessing or concurrent.futures not used in fast_solver.py"
    assert os.access(py_path, os.X_OK), "fast_solver.py is not executable"


def test_parallel_solve_on_fresh_inputs():
    sys.path.insert(0, SIM_PROJECT_DIR)
    try:
        sys.modules.pop("fast_solver", None)
        solver = importlib.import_module("fast_solver")
        assert callable(solver.parallel_solve)

        rng = np.random.default_rng(int.from_bytes(os.urandom(8), "little"))
        for workers, length in ((1, 19), (2, 46), (3, 57), (4, 68), (5, 85)):
            data = rng.uniform(-5.0, 5.0, length).astype(np.float64)
            original = data.copy()
            actual = solver.parallel_solve(data, num_workers=workers)

            assert isinstance(actual, np.ndarray)
            assert actual.shape == data.shape
            assert actual.ndim == 1
            assert actual.dtype == np.float64
            np.testing.assert_array_equal(data, original, err_msg="parallel_solve modified its input")

            expected = np.empty_like(data)
            for i, value in enumerate(data):
                value = float(value)
                for _ in range(50):
                    value = math.sin(value) * math.cos(value) + 0.1
                expected[i] = value
            np.testing.assert_allclose(actual, expected, rtol=1e-7, atol=1e-7)
    finally:
        if sys.path and sys.path[0] == SIM_PROJECT_DIR:
            sys.path.pop(0)


def test_regression_tests_pass():
    test_file = os.path.join(SIM_PROJECT_DIR, "test_regression.py")
    assert os.path.isfile(test_file), f"{test_file} is missing."

    result = subprocess.run(
        ["pytest", test_file],
        capture_output=True,
        text=True,
        cwd=SIM_PROJECT_DIR
    )
    assert result.returncode == 0, f"Regression tests failed. Pytest output:\n{result.stdout}\n{result.stderr}"


def test_run_profile_py_exists():
    py_path = os.path.join(SIM_PROJECT_DIR, "run_profile.py")
    assert os.path.isfile(py_path), f"{py_path} does not exist."
    assert os.access(py_path, os.X_OK), "run_profile.py is not executable"


def test_run_profile_requests_required_workload():
    sys.path.insert(0, SIM_PROJECT_DIR)
    old_rand = np.random.rand
    try:
        solver = importlib.import_module("fast_solver")
        old_solve = solver.parallel_solve
        calls = {"rand": None, "dtype": None, "solve": None}
        marker = object()

        class FakeRandomResult:
            def astype(self, dtype):
                calls["dtype"] = np.dtype(dtype)
                return marker

        def fake_rand(*shape):
            calls["rand"] = shape
            return FakeRandomResult()

        def fake_solve(data, num_workers):
            calls["solve"] = (data, num_workers)
            return np.empty(0, dtype=np.float64)

        np.random.rand = fake_rand
        solver.parallel_solve = fake_solve
        runpy.run_path(os.path.join(SIM_PROJECT_DIR, "run_profile.py"), run_name="__main__")

        assert calls["rand"] == (10_000_000,), "run_profile.py must call numpy.random.rand(10000000)"
        assert calls["dtype"] == np.dtype(np.float64), "profile input must be converted to float64"
        assert calls["solve"] == (marker, 4), "run_profile.py must call parallel_solve(data, num_workers=4)"
    finally:
        np.random.rand = old_rand
        if 'solver' in locals() and 'old_solve' in locals():
            solver.parallel_solve = old_solve
        if sys.path and sys.path[0] == SIM_PROJECT_DIR:
            sys.path.pop(0)


def test_profile_data_prof_exists_and_valid():
    prof_path = os.path.join(SIM_PROJECT_DIR, "profile_data.prof")
    assert os.path.isfile(prof_path), f"{prof_path} does not exist. Did you run cProfile and output to this file?"

    try:
        stats = pstats.Stats(prof_path)
        assert len(stats.stats) > 0, "Profile data appears empty."
    except Exception as e:
        pytest.fail(f"Failed to load {prof_path} as a valid cProfile output: {e}")


def test_profile_is_generated_by_required_execution():
    prof_path = os.path.join(SIM_PROJECT_DIR, "profile_data.prof")
    os.unlink(prof_path)
    try:
        result = subprocess.run(
            [sys.executable, "-m", "cProfile", "-o", prof_path, "run_profile.py"],
            cwd=SIM_PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Profiling run_profile.py timed out")

    assert result.returncode == 0, (
        "Profiling run_profile.py failed:\n" + result.stdout + "\n" + result.stderr
    )
    assert os.path.isfile(prof_path), "cProfile did not generate profile_data.prof"

    stats = pstats.Stats(prof_path)
    assert len(stats.stats) > 0, "Generated profile is empty"
    function_names = [key[2] for key in stats.stats]
    assert any(name == "parallel_solve" for name in function_names), (
        "profile_data.prof does not contain a parallel_solve execution"
    )
    assert any("rand" in name for name in function_names), (
        "profile_data.prof does not contain the required numpy.random.rand call"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
