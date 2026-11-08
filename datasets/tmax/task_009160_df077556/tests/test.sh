#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import itertools
import math
import os
import re
import shlex
import subprocess
import tempfile

import pytest

BEST_PARAMS_PATH = "/home/user/best_params.txt"
CPP_PATH = "/home/user/lv_fit.cpp"
SH_PATH = "/home/user/grid_search.sh"
REFERENCE_PATH = "/home/user/reference_data.csv"
EXE_PATH = "/home/user/lv_fit"

GRID_A = [1.0, 1.5, 2.0]
GRID_B = [0.5, 1.0, 1.5]
GRID_G = [2.0, 3.0, 4.0]
GRID_D = [0.5, 1.0, 1.5]
EXPECTED_COMBINATIONS = set(itertools.product(GRID_A, GRID_B, GRID_G, GRID_D))
FLOAT_ONLY = re.compile(r"^[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?$")


def rk4_step(x, y, alpha, beta, gamma, delta, dt=0.1):
    dx1 = alpha*x - beta*x*y
    dy1 = delta*x*y - gamma*y

    x2 = x + 0.5*dt*dx1
    y2 = y + 0.5*dt*dy1
    dx2 = alpha*x2 - beta*x2*y2
    dy2 = delta*x2*y2 - gamma*y2

    x3 = x + 0.5*dt*dx2
    y3 = y + 0.5*dt*dy2
    dx3 = alpha*x3 - beta*x3*y3
    dy3 = delta*x3*y3 - gamma*y3

    x4 = x + dt*dx3
    y4 = y + dt*dy3
    dx4 = alpha*x4 - beta*x4*y4
    dy4 = delta*x4*y4 - gamma*y4

    return (x + dt*(dx1 + 2*dx2 + 2*dx3 + dx4)/6.0,
            y + dt*(dy1 + 2*dy2 + 2*dy3 + dy4)/6.0)


def trajectory(params):
    x, y = 40.0, 9.0
    points = [(x, y)]
    for _ in range(500):
        x, y = rk4_step(x, y, *params)
        if not (math.isfinite(x) and math.isfinite(y)):
            return None
        points.append((x, y))
    return points


def write_dataset(path, points):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["t", "x", "y"])
        for i, (x, y) in enumerate(points):
            writer.writerow([f"{i/10:.1f}", repr(x), repr(y)])


def oracle_mse(candidate, reference_points):
    simulated = trajectory(candidate)
    assert simulated is not None
    total = 0.0
    for (sx, sy), (rx, ry) in zip(simulated, reference_points):
        total += (sx-rx)**2 + (sy-ry)**2
    return total / 501.0


def parse_single_float(stdout):
    text = stdout.strip()
    assert FLOAT_ONLY.fullmatch(text), f"Program must print only one floating-point number, got: {stdout!r}"
    value = float(text)
    assert math.isfinite(value), f"Program returned a non-finite MSE: {text}"
    return value


def parse_best(path=BEST_PARAMS_PATH):
    with open(path, "r") as f:
        content = f.read().strip()
    assert content, "best_params.txt is empty"
    parts = content.split(',')
    assert len(parts) == 5, f"best_params.txt must contain exactly 5 comma-separated values (alpha,beta,gamma,delta,MSE), got {len(parts)}"
    try:
        values = tuple(float(p) for p in parts)
    except ValueError:
        pytest.fail(f"Could not parse values in best_params.txt as floats. Content was: {content}")
    assert all(math.isfinite(v) for v in values), f"best_params.txt contains a non-finite value: {content}"
    return values


def run_grid(trace=False):
    command = ["bash"]
    if trace:
        command.append("-x")
    command.append(SH_PATH)
    result = subprocess.run(command, cwd="/home/user", text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=90)
    assert result.returncode == 0, f"grid_search.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    return result


def traced_combinations(stderr):
    found = []
    for raw_line in stderr.splitlines():
        if not raw_line.startswith("+"):
            continue
        line = raw_line.lstrip("+ ")
        try:
            tokens = shlex.split(line)
        except ValueError:
            continue
        for i in range(1, len(tokens)-4):
            if tokens[i+4] != REFERENCE_PATH:
                continue
            try:
                combo = tuple(float(tokens[i+j]) for j in range(4))
            except ValueError:
                continue
            if combo in EXPECTED_COMBINATIONS:
                found.append(combo)
    return found


def test_files_exist():
    """Test that the required source and output files exist."""
    assert os.path.exists(CPP_PATH), f"Missing required file: {CPP_PATH}"
    assert os.path.exists(SH_PATH), f"Missing required file: {SH_PATH}"
    assert os.path.exists(BEST_PARAMS_PATH), f"Missing required file: {BEST_PARAMS_PATH}"


def test_best_params_content():
    """Test that best_params.txt contains the correct parameters and a small MSE."""
    alpha, beta, gamma, delta, mse = parse_best()
    assert alpha == 1.5, f"Expected alpha=1.5, got {alpha}"
    assert beta == 1.0, f"Expected beta=1.0, got {beta}"
    assert gamma == 3.0, f"Expected gamma=3.0, got {gamma}"
    assert delta == 1.0, f"Expected delta=1.0, got {delta}"
    assert mse < 1e-5, f"Expected MSE < 1e-5, got {mse}"


def test_cpp_compiles_and_computes_independent_mses():
    compiled = subprocess.run(["g++", "-std=c++17", "-O2", CPP_PATH, "-o", EXE_PATH],
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=30)
    assert compiled.returncode == 0, f"lv_fit.cpp did not compile:\n{compiled.stderr}"
    assert os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK)

    no_args = subprocess.run([EXE_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert no_args.returncode != 0, "Program must reject calls without the five required arguments"
    too_many = subprocess.run([EXE_PATH, "1", "1", "1", "1", REFERENCE_PATH, "extra"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert too_many.returncode != 0, "Program must reject calls with more than five arguments"

    cases = [
        ((0.20, 0.010, 0.30, 0.010), (0.25, 0.012, 0.28, 0.009)),
        ((0.35, 0.015, 0.45, 0.012), (0.30, 0.013, 0.50, 0.010)),
    ]
    with tempfile.TemporaryDirectory() as td:
        for index, (data_params, candidate) in enumerate(cases):
            points = trajectory(data_params)
            assert points is not None
            csv_path = os.path.join(td, f"case_{index}.csv")
            write_dataset(csv_path, points)
            expected = oracle_mse(candidate, points)
            result = subprocess.run([EXE_PATH, *(str(v) for v in candidate), csv_path],
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    timeout=15)
            assert result.returncode == 0, f"lv_fit failed on test data: {result.stderr}"
            actual = parse_single_float(result.stdout)
            tolerance = max(1e-7, abs(expected) * 3e-5)
            assert abs(actual-expected) <= tolerance, \
                f"Incorrect RK4/MSE result: expected {expected}, got {actual}"


def test_grid_script_executes_complete_search_and_uses_data():
    # Ensure the executable used by conventional scripts is the freshly compiled submission.
    compiled = subprocess.run(["g++", "-std=c++17", "-O2", CPP_PATH, "-o", EXE_PATH],
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=30)
    assert compiled.returncode == 0, f"lv_fit.cpp did not compile:\n{compiled.stderr}"

    with open(REFERENCE_PATH, "rb") as f:
        original_reference = f.read()

    original_best = None
    try:
        first = run_grid(trace=True)
        seen = traced_combinations(first.stderr)
        assert set(seen) == EXPECTED_COMBINATIONS, \
            f"grid_search.sh did not execute every one of the 81 parameter combinations; saw {len(set(seen))}"
        assert len(seen) >= 81, "Expected at least one C++ invocation for each grid combination"

        alpha, beta, gamma, delta, mse = parse_best()
        assert (alpha, beta, gamma, delta) == (1.5, 1.0, 3.0, 1.0)
        assert mse < 1e-5
        with open(BEST_PARAMS_PATH, "rb") as f:
            original_best = f.read()

        dynamic_params = None
        dynamic_points = None
        for params in sorted(EXPECTED_COMBINATIONS):
            if params == (1.5, 1.0, 3.0, 1.0):
                continue
            points = trajectory(params)
            if points is not None:
                dynamic_params, dynamic_points = params, points
                break
        assert dynamic_params is not None, "Could not construct a finite independent grid dataset"
        write_dataset(REFERENCE_PATH, dynamic_points)
        if os.path.exists(BEST_PARAMS_PATH):
            os.remove(BEST_PARAMS_PATH)

        run_grid(trace=False)
        alpha, beta, gamma, delta, mse = parse_best()
        assert (alpha, beta, gamma, delta) == dynamic_params, \
            f"Grid search did not adapt to changed reference data; expected {dynamic_params}, got {(alpha,beta,gamma,delta)}"
        assert mse < 1e-5, f"Expected near-zero MSE for an exact grid-generated dataset, got {mse}"
    finally:
        with open(REFERENCE_PATH, "wb") as f:
            f.write(original_reference)
        if original_best is not None:
            with open(BEST_PARAMS_PATH, "wb") as f:
                f.write(original_best)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
