#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import runpy
import secrets
import subprocess
import sys

import pytest

WORK_DIR = "/home/user/ticket_8841"


def test_wrapper_c_fixed():
    wrapper_path = os.path.join(WORK_DIR, "wrapper.c")
    assert os.path.isfile(wrapper_path), f"File {wrapper_path} does not exist."
    with open(wrapper_path, "r") as f:
        content = f.read()
    assert "calc_decay_v2" in content, "wrapper.c does not contain the correct function name 'calc_decay_v2'."
    assert "calculate_decay" not in content, "wrapper.c still contains the incorrect function name 'calculate_decay'."


def test_wrapper_so_compiled_and_functional():
    wrapper_so_path = os.path.join(WORK_DIR, "wrapper.so")
    if os.path.lexists(wrapper_so_path):
        os.remove(wrapper_so_path)

    proc = subprocess.run(
        ["bash", "./build.sh"],
        cwd=WORK_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"build.sh failed:\n{proc.stdout}\n{proc.stderr}"
    assert os.path.isfile(wrapper_so_path), f"File {wrapper_so_path} does not exist. The build script was likely not run or failed."
    with open(wrapper_so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "wrapper.so is not an ELF shared object."

    probe = r'''import ctypes, sys
lib = ctypes.CDLL(sys.argv[1])
fn = lib.do_compute
fn.restype = ctypes.c_double
fn.argtypes = [ctypes.c_double]
for arg in (0.125, 0.5, 1.0):
    print(repr(fn(arg)))
'''
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = WORK_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    proc = subprocess.run(
        [sys.executable, "-c", probe, wrapper_so_path],
        cwd=WORK_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"The rebuilt wrapper could not be loaded or called:\n{proc.stderr}"
    values = [float(line) for line in proc.stdout.splitlines() if line.strip()]
    assert len(values) == 3
    for x, actual in zip((0.125, 0.5, 1.0), values):
        expected = 2.0 * (math.sin(x / 2.0) / x) ** 2
        assert math.isfinite(actual)
        assert abs(actual - expected) < 1e-10, f"do_compute({x}) returned {actual}, expected {expected}."


def test_fallback_decay_is_numerically_stable():
    simulate_path = os.path.join(WORK_DIR, "simulate.py")
    assert os.path.isfile(simulate_path), f"File {simulate_path} does not exist."
    with open(simulate_path, "r") as f:
        tree = ast.parse(f.read(), filename=simulate_path)
    assert any(isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "fallback_decay" for n in tree.body), \
        "simulate.py does not define fallback_decay."

    old_cwd = os.getcwd()
    try:
        os.chdir(WORK_DIR)
        namespace = runpy.run_path(simulate_path)
    finally:
        os.chdir(old_cwd)

    fallback = namespace.get("fallback_decay")
    assert callable(fallback), "fallback_decay is not callable."

    rng = secrets.SystemRandom()
    inputs = [1e-8, -1e-8, 1e-10, -1e-12]
    inputs.extend(((-1.0 if rng.randrange(2) else 1.0) * 10.0 ** rng.uniform(-12.0, -5.0)) for _ in range(8))
    inputs.extend(rng.uniform(-0.75, 0.75) or 0.25 for _ in range(6))

    for x in inputs:
        actual = fallback(x)
        expected = 2.0 * (math.sin(x / 2.0) / x) ** 2
        assert isinstance(actual, (int, float)), f"fallback_decay({x}) did not return a number."
        assert math.isfinite(actual), f"fallback_decay({x}) returned a non-finite value."
        assert abs(actual - expected) < 5e-6, f"fallback_decay({x}) returned {actual}, expected {expected}."


def test_result_txt_correct():
    result_path = os.path.join(WORK_DIR, "result.txt")
    if os.path.lexists(result_path):
        os.remove(result_path)

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = WORK_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    proc = subprocess.run(
        [sys.executable, "simulate.py"],
        cwd=WORK_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"simulate.py failed:\n{proc.stdout}\n{proc.stderr}"
    assert os.path.isfile(result_path), f"File {result_path} does not exist. simulate.py was likely not run."
    with open(result_path, "r") as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        pytest.fail(f"result.txt content '{content}' is not a valid float.")

    assert abs(val - 0.5) < 1e-4, f"result.txt contains {val}, expected 0.500000 (numerical instability not fixed)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
