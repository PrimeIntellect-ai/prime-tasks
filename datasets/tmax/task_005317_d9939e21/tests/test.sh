#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import inspect
import math
import os
import secrets
import shutil
import subprocess
import sys
import time

from scipy.integrate import quad

DIV = "/home/user/divergence.py"
RUN = "/home/user/run_parallel.sh"
AGENT_TEST = "/home/user/test_divergence.py"
LOG = "/home/user/kl_results.log"


def reference_kl(mu, sigma):
    norm = math.sqrt(2.0 * math.pi)

    def integrand(x):
        p = math.exp(-0.5 * x * x) / norm
        log_p = -0.5 * x * x - math.log(norm)
        log_q = -0.5 * ((x - mu) / sigma) ** 2 - math.log(norm * sigma)
        return p * (log_p - log_q)

    return quad(integrand, -20.0, 20.0)[0]


def test_files_exist():
    assert os.path.isfile(DIV), "/home/user/divergence.py is missing."
    assert os.path.isfile(RUN), "/home/user/run_parallel.sh is missing."
    assert os.path.isfile(AGENT_TEST), "/home/user/test_divergence.py is missing."


def test_run_parallel_and_log():
    subprocess.run(["bash", RUN], cwd="/home/user", check=True)
    assert os.path.isfile(LOG), "/home/user/kl_results.log was not created."
    with open(LOG) as f:
        lines = sorted(line.strip() for line in f if line.strip())
    expected_lines = [
        "-0.5,2.0,0.3494",
        "0.5,1.5,0.1832",
        "1.0,1.0,0.5000",
        "2.0,0.8,3.1831",
    ]
    assert lines == expected_lines, f"kl_results.log contents do not match expected. Got: {lines}"


def test_run_parallel_really_invokes_divergence_concurrently():
    backup = "/tmp/divergence.agent.py"
    calls = "/tmp/divergence_calls.log"
    shutil.copy2(DIV, backup)
    try:
        if os.path.exists(calls):
            os.unlink(calls)
        probe = r'''#!/usr/bin/python3
import argparse, os, time
p = argparse.ArgumentParser()
p.add_argument("--mu", type=float, required=True)
p.add_argument("--sigma", type=float, required=True)
a = p.parse_args()
fd = os.open("/tmp/divergence_calls.log", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
os.write(fd, (str(a.mu) + "," + str(a.sigma) + "\n").encode())
os.close(fd)
time.sleep(0.7)
vals = {(0.5,1.5):0.1832, (1.0,1.0):0.5000, (-0.5,2.0):0.3494, (2.0,0.8):3.1831}
print(f"{a.mu},{a.sigma},{vals[(a.mu,a.sigma)]:.4f}")
'''
        with open(DIV, "w") as f:
            f.write(probe)
        os.chmod(DIV, 0o755)
        start = time.monotonic()
        subprocess.run(["bash", RUN], cwd="/home/user", check=True, timeout=10)
        elapsed = time.monotonic() - start
        assert os.path.isfile(calls), "run_parallel.sh did not invoke divergence.py"
        with open(calls) as f:
            got = sorted(line.strip() for line in f if line.strip())
        expected = sorted(["0.5,1.5", "1.0,1.0", "-0.5,2.0", "2.0,0.8"])
        assert got == expected, f"run_parallel.sh invoked the wrong jobs: {got}"
        assert elapsed < 2.2, f"The four jobs did not run in parallel (elapsed {elapsed:.2f}s)"
    finally:
        shutil.copy2(backup, DIV)


def test_pytest_execution():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", AGENT_TEST],
        cwd="/home/user", capture_output=True, text=True
    )
    assert result.returncode == 0, f"pytest failed:\n{result.stdout}\n{result.stderr}"


def test_agent_test_is_a_real_regression_test():
    with open(AGENT_TEST) as f:
        tree = ast.parse(f.read(), AGENT_TEST)
    imports_divergence = any(
        (isinstance(n, ast.Import) and any(a.name == "divergence" for a in n.names)) or
        (isinstance(n, ast.ImportFrom) and n.module == "divergence")
        for n in ast.walk(tree)
    )
    assert imports_divergence, "test_divergence.py must import integration logic from divergence.py"
    tests = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith("test")]
    assert tests, "test_divergence.py contains no pytest test function"
    valid = False
    for fn in tests:
        nodes = list(ast.walk(fn))
        values = [n.value for n in nodes if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))]
        has_call = any(isinstance(n, ast.Call) for n in nodes)
        asserts = [n for n in nodes if isinstance(n, ast.Assert)]
        assert_values = [n.value for a in asserts for n in ast.walk(a.test)
                         if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))]
        if has_call and values.count(1.0) >= 2 and any(abs(v - 0.5) < 1e-12 for v in assert_values) and any(abs(v - 1e-3) < 1e-12 for v in assert_values):
            valid = True
    assert valid, "A test must compute mu=1.0, sigma=1.0 and assert 0.5 with absolute tolerance 1e-3"


def test_divergence_script_output():
    result = subprocess.run(
        [sys.executable, DIV, "--mu", "0.0", "--sigma", "1.0"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"divergence.py failed to run:\n{result.stderr}"
    assert result.stdout.strip() == "0.0,1.0,0.0000", f"Unexpected output: {result.stdout!r}"


def test_divergence_on_runtime_generated_inputs():
    rng = secrets.SystemRandom()
    pairs = set()
    forbidden = {(0.0, 1.0), (0.5, 1.5), (1.0, 1.0), (-0.5, 2.0), (2.0, 0.8)}
    while len(pairs) < 4:
        pair = (rng.randrange(-37, 38) / 10.0, rng.randrange(4, 31) / 10.0)
        if pair not in forbidden:
            pairs.add(pair)
    for mu, sigma in pairs:
        result = subprocess.run(
            [sys.executable, DIV, "--mu", str(mu), "--sigma", str(sigma)],
            capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, result.stderr
        expected = f"{mu},{sigma},{reference_kl(mu, sigma):.4f}"
        assert result.stdout.splitlines() == [expected], f"For {(mu, sigma)}, expected {expected!r}, got {result.stdout!r}"


def test_imported_logic_uses_scipy_quad_and_is_correct():
    spec = importlib.util.spec_from_file_location("agent_divergence", DIV)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    mu, sigma = 1.7, 1.3
    expected = reference_kl(mu, sigma)
    import scipy.integrate
    original_quad = scipy.integrate.quad
    count = [0]

    def tracked_quad(*args, **kwargs):
        count[0] += 1
        return original_quad(*args, **kwargs)

    aliases = [name for name, value in vars(module).items() if value is original_quad]
    scipy.integrate.quad = tracked_quad
    for name in aliases:
        setattr(module, name, tracked_quad)
    matched = False
    try:
        for name, fn in vars(module).items():
            if not inspect.isfunction(fn) or fn.__module__ != module.__name__:
                continue
            try:
                inspect.signature(fn).bind(mu, sigma)
            except TypeError:
                continue
            count[0] = 0
            try:
                value = fn(mu, sigma)
            except Exception:
                continue
            if isinstance(value, (int, float)) and abs(float(value) - expected) <= 1e-3 and count[0] > 0:
                matched = True
                break
    finally:
        scipy.integrate.quad = original_quad
        for name in aliases:
            setattr(module, name, original_quad)
    assert matched, "No imported two-argument integration function both produced the KL value and called scipy.integrate.quad"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
