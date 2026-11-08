#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import math
import os
import secrets
import subprocess
import sys
import tempfile

CPP_PATH = "/home/user/integrator.cpp"
SO_PATH = "/home/user/libintegrator.so"
PY_PATH = "/home/user/run_analysis.py"
JSON_PATH = "/home/user/analysis.json"


def reference_integrate(y0, t_end, lam, tol):
    t = 0.0
    y = y0
    h = 0.1
    steps = 0
    max_steps = 100000

    while t < t_end and steps < max_steps:
        k1 = -lam * y
        k2 = -lam * (y + h * k1)
        y_new = y + h / 2.0 * (k1 + k2)
        error = abs(h / 2.0 * (k2 - k1))

        if error == 0.0:
            error = 1e-15

        if error <= tol:
            t += h
            y = y_new

        h = h * 0.9 * math.sqrt(tol / error)
        h = max(1e-5, min(h, 0.5))
        if t + h > t_end:
            h = t_end - t
        steps += 1

    return (-1 if steps >= max_steps else 0), y, steps


def load_integrator(path):
    lib = ctypes.CDLL(path)
    integrate = lib.integrate
    integrate.argtypes = [
        ctypes.c_double,
        ctypes.c_double,
        ctypes.c_double,
        ctypes.c_double,
        ctypes.POINTER(ctypes.c_double),
        ctypes.POINTER(ctypes.c_int),
    ]
    integrate.restype = ctypes.c_int
    return lib, integrate


def call_integrator(integrate, y0, t_end, lam, tol):
    y_out = ctypes.c_double()
    steps_out = ctypes.c_int()
    rc = integrate(y0, t_end, lam, tol, ctypes.byref(y_out), ctypes.byref(steps_out))
    return rc, y_out.value, steps_out.value


def assert_matches_reference(integrate, case):
    expected_rc, expected_y, expected_steps = reference_integrate(*case)
    actual_rc, actual_y, actual_steps = call_integrator(integrate, *case)
    assert actual_rc == expected_rc, f"integrate returned {actual_rc}, expected {expected_rc}, for {case}"
    assert actual_steps == expected_steps, f"integrate used {actual_steps} steps, expected {expected_steps}, for {case}"
    assert math.isclose(actual_y, expected_y, rel_tol=1e-11, abs_tol=1e-13), \
        f"integrate returned y={actual_y}, expected {expected_y}, for {case}"


def test_integrator_cpp_fixed():
    assert os.path.exists(CPP_PATH), f"{CPP_PATH} does not exist."
    with open(CPP_PATH, "r") as f:
        content = f.read()

    # Retain the original source assertions, while behavioral tests below ensure
    # the expression is part of the working implementation rather than a comment.
    assert "std::sqrt(tol / error)" in content, "The step-size adaptation bug in integrator.cpp was not fixed correctly. Expected 'std::sqrt(tol / error)'."
    assert "std::sqrt(error / tol)" not in content, "The buggy line 'std::sqrt(error / tol)' is still present in integrator.cpp."


def test_shared_library_exists():
    assert os.path.exists(SO_PATH), f"Shared library {SO_PATH} does not exist. Did you compile the C++ code?"
    assert os.path.isfile(SO_PATH), f"{SO_PATH} is not a regular file."
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SO_PATH} is not an ELF shared library."
    load_integrator(SO_PATH)


def test_python_script_exists():
    assert os.path.exists(PY_PATH), f"Python script {PY_PATH} does not exist."
    assert os.path.isfile(PY_PATH), f"{PY_PATH} is not a regular file."
    with open(PY_PATH, "r") as f:
        tree = ast.parse(f.read(), filename=PY_PATH)
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, f"{PY_PATH} must use the ctypes module."


def test_source_and_library_behavior():
    with tempfile.TemporaryDirectory() as td:
        rebuilt_so = os.path.join(td, "libintegrator_rebuilt.so")
        result = subprocess.run(
            ["g++", "-shared", "-fPIC", "-O2", CPP_PATH, "-o", rebuilt_so],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"integrator.cpp did not compile successfully:\n{result.stderr}"

        rebuilt_lib, rebuilt_integrate = load_integrator(rebuilt_so)
        submitted_lib, submitted_integrate = load_integrator(SO_PATH)

        cases = [
            (1.0, 2.0, 5.0, 1e-2),
            (1.0, 2.0, 5.0, 1e-3),
            (1.0, 2.0, 5.0, 1e-4),
        ]
        # Unpredictable additional inputs prevent a hard-coded library from
        # satisfying only the three report cases.
        for _ in range(3):
            y0 = 0.5 + secrets.randbelow(1000) / 1000.0
            t_end = 0.75 + secrets.randbelow(1250) / 1000.0
            lam = 0.75 + secrets.randbelow(6000) / 1000.0
            tol = (1 + secrets.randbelow(9)) * 10 ** (-(3 + secrets.randbelow(2)))
            cases.append((y0, t_end, lam, tol))

        for case in cases:
            assert_matches_reference(rebuilt_integrate, case)
            assert_matches_reference(submitted_integrate, case)

        # Keep library objects alive until all calls complete.
        assert rebuilt_lib is not None and submitted_lib is not None


def test_analysis_json():
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)

    env = os.environ.copy()
    env["LD_DEBUG"] = "files"
    run = subprocess.run(
        [sys.executable, PY_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert run.returncode == 0, f"run_analysis.py failed:\nSTDOUT:\n{run.stdout}\nSTDERR:\n{run.stderr}"
    assert "libintegrator.so" in run.stderr, "run_analysis.py did not dynamically load libintegrator.so."
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} does not exist."

    try:
        with open(JSON_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"{JSON_PATH} is not a valid JSON file."

    expected_keys = ["1e-2", "1e-3", "1e-4"]
    for key in expected_keys:
        assert key in data, f"Key '{key}' is missing from {JSON_PATH}."
        assert "steps" in data[key], f"'steps' missing for tolerance {key}."
        assert "error" in data[key], f"'error' missing for tolerance {key}."
        assert isinstance(data[key]["steps"], int), f"'steps' for {key} must be an integer."
        assert isinstance(data[key]["error"], (int, float)), f"'error' for {key} must be a number."

    assert data["1e-2"]["steps"] < 1000, "Number of steps for 1e-2 is too high, indicating the bug might not be fully resolved or the integrator diverged."
    assert data["1e-3"]["steps"] < 1000, "Number of steps for 1e-3 is too high."
    assert data["1e-4"]["steps"] < 2000, "Number of steps for 1e-4 is too high."

    err_1 = data["1e-2"]["error"]
    err_2 = data["1e-3"]["error"]
    err_3 = data["1e-4"]["error"]
    assert err_1 > err_2, f"Error for 1e-2 ({err_1}) should be greater than error for 1e-3 ({err_2})."
    assert err_2 > err_3, f"Error for 1e-3 ({err_2}) should be greater than error for 1e-4 ({err_3})."

    # Derive the required report values independently from the submitted library.
    lib, integrate = load_integrator(SO_PATH)
    for key, tol in [("1e-2", 1e-2), ("1e-3", 1e-3), ("1e-4", 1e-4)]:
        rc, y_final, steps = call_integrator(integrate, 1.0, 2.0, 5.0, tol)
        assert rc == 0, f"Integration failed for tolerance {key}."
        expected_error = abs(y_final - math.exp(-10.0))
        assert data[key]["steps"] == steps, f"Fabricated step count for {key}: JSON has {data[key]['steps']}, library produced {steps}."
        assert math.isclose(data[key]["error"], expected_error, rel_tol=1e-10, abs_tol=1e-14), \
            f"Incorrect error for {key}: JSON has {data[key]['error']}, derived value is {expected_error}."
    assert lib is not None
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
