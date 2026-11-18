#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import subprocess
import sys


def test_cpp_updated():
    file_path = "/home/user/heat_sim.cpp"
    assert os.path.isfile(file_path), f"Missing file: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read()

    assert "double dt = 0.001;" not in content, "The file still contains the hardcoded buggy dt variable."
    assert "dt =" in content, "The file must calculate dt."


def test_compile_and_run_simulator():
    source = "/home/user/heat_sim.cpp"
    executable = "/tmp/heat_sim_verified"
    output_path = "/home/user/output.csv"

    if os.path.exists(output_path):
        os.remove(output_path)
    if os.path.exists(executable):
        os.remove(executable)

    try:
        subprocess.run(
            ["g++", "-O3", source, "-o", executable],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
        )
        subprocess.run(
            [executable],
            cwd="/home/user",
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
        )
    except subprocess.CalledProcessError as e:
        raise AssertionError(f"Failed to compile or run heat_sim.cpp:\n{e.stdout.decode('utf-8', errors='replace')}")
    except subprocess.TimeoutExpired:
        raise AssertionError("Compiling or running heat_sim.cpp timed out.")

    assert os.path.isfile(output_path), "Running the compiled simulator did not create /home/user/output.csv."


def test_output_exists_and_valid():
    output_path = "/home/user/output.csv"
    assert os.path.exists(output_path), f"File {output_path} does not exist. Did you run the simulation?"

    with open(output_path, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) == 2500, f"The file {output_path} should contain exactly 2500 lines, but found {len(lines)}."

    # Check that they are valid floats and not NaN
    for i, line in enumerate(lines):
        try:
            val = float(line)
            assert val == val, f"Found NaN value at line {i+1} in {output_path}."
        except ValueError:
            raise AssertionError(f"Invalid float value at line {i+1} in {output_path}: {line}")


def test_output_matches_independent_simulation():
    import numpy as np

    nx = 50
    ny = 50
    L = 1.0
    dx = L / (nx - 1)
    dy = L / (ny - 1)
    alpha = 1.0
    dt = 0.2 * min(dx * dx, dy * dy) / alpha
    t_final = 0.05
    n_steps = int(np.ceil(t_final / dt))
    dt = t_final / n_steps

    expected = np.zeros((nx, ny), dtype=np.float64)
    expected_new = np.zeros((nx, ny), dtype=np.float64)

    for i in range(nx):
        for j in range(ny):
            x = i * dx - 0.5
            y = j * dy - 0.5
            if x * x + y * y < 0.05:
                expected[i, j] = 1.0

    for _ in range(n_steps):
        expected_new[1:-1, 1:-1] = expected[1:-1, 1:-1] + alpha * dt * (
            (expected[2:, 1:-1] - 2.0 * expected[1:-1, 1:-1] + expected[:-2, 1:-1]) / (dx * dx)
            + (expected[1:-1, 2:] - 2.0 * expected[1:-1, 1:-1] + expected[1:-1, :-2]) / (dy * dy)
        )
        expected = expected_new.copy()

    with open('/home/user/output.csv', 'r') as f:
        actual = np.array([float(x) for x in f.read().splitlines()], dtype=np.float64)

    assert np.all(np.isfinite(actual)), "output.csv contains a non-finite value."
    assert np.allclose(actual, expected.ravel(), rtol=2e-5, atol=2e-9), (
        f"output.csv does not match the independently computed stable heat simulation; "
        f"maximum absolute error is {np.max(np.abs(actual - expected.ravel()))}."
    )


def test_report_correct():
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"File {report_path} does not exist."

    with open(report_path, 'r') as f:
        content = f.read()

    match = re.search(r'CI:\s*\[([0-9.]+),\s*([0-9.]+)\]', content)
    assert match is not None, "Could not parse CI from report.txt. Expected format: CI: [lower_bound, upper_bound]"

    lower = float(match.group(1))
    upper = float(match.group(2))

    # Use a subprocess to run the numpy verification script so we strictly adhere to stdlib imports in this pytest file
    script = """
import numpy as np
with open('/home/user/output.csv', 'r') as f:
    out_vals = np.array([float(x) for x in f.read().splitlines()])
with open('/home/user/reference.csv', 'r') as f:
    ref_vals = np.array([float(x) for x in f.read().splitlines()])
residuals = np.abs(out_vals - ref_vals)
np.random.seed(42)
means = [np.mean(np.random.choice(residuals, size=len(residuals), replace=True)) for _ in range(10000)]
print(np.percentile(means, 2.5))
print(np.percentile(means, 97.5))
"""
    try:
        output = subprocess.check_output([sys.executable, "-c", script], stderr=subprocess.STDOUT).decode('utf-8').split()
        expected_lower = float(output[0])
        expected_upper = float(output[1])
    except subprocess.CalledProcessError as e:
        raise AssertionError(f"Failed to compute expected CI using numpy: {e.output.decode('utf-8')}")
    except Exception as e:
        raise AssertionError(f"Failed to compute expected CI: {e}")

    assert abs(lower - expected_lower) < 1e-5, f"Lower bound {lower} does not match expected {expected_lower:.6f}"
    assert abs(upper - expected_upper) < 1e-5, f"Upper bound {upper} does not match expected {expected_upper:.6f}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
