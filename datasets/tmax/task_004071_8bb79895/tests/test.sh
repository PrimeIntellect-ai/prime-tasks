#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import time

HEAT_BIN = "/tmp/verified_heat"
REGRESSION_BIN = "/tmp/verified_regression"
MESHES = [10, 20, 40, 80]


def run(cmd, *, input_text=None, cwd=None, timeout=30):
    return subprocess.run(
        cmd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=cwd,
        timeout=timeout,
        check=True,
    ).stdout


def reference_heat_error(n):
    alpha = 0.1
    final_time = 0.5
    dx = 1.0 / n
    dt = dx * dx / (4.0 * alpha)
    steps = int(round(final_time / dt))
    ratio = alpha * dt / (dx * dx)

    u = [math.sin(math.pi * i * dx) for i in range(n + 1)]
    u[0] = 0.0
    u[n] = 0.0
    for _ in range(steps):
        nxt = [0.0] * (n + 1)
        for i in range(1, n):
            nxt[i] = u[i] + ratio * (u[i + 1] - 2.0 * u[i] + u[i - 1])
        u = nxt

    factor = math.exp(-alpha * math.pi * math.pi * final_time)
    return max(abs(u[i] - factor * math.sin(math.pi * i * dx)) for i in range(n + 1))


def parse_heat_output(output):
    assert re.fullmatch(r"\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*", output), \
        f"heat must print only one floating-point error, but printed: {output!r}"
    value = float(output)
    assert math.isfinite(value) and value >= 0.0, f"Invalid heat error: {value}"
    return value


def ols_slope(rows):
    xs = [math.log(float(n)) for n, _ in rows]
    ys = [math.log(float(error)) for _, error in rows]
    xbar = sum(xs) / len(xs)
    ybar = sum(ys) / len(ys)
    return sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys)) / sum((x - xbar) ** 2 for x in xs)


def test_source_files_exist():
    """Check that the required source files and scripts have been created."""
    assert os.path.isfile("/home/user/heat.c"), "/home/user/heat.c is missing."
    assert os.path.isfile("/home/user/regression.c"), "/home/user/regression.c is missing."


def test_script_exists_and_executable():
    """Check that the bash script exists and is executable."""
    script_path = "/home/user/run_simulation.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_compile_and_run_heat_program():
    run(["gcc", "/home/user/heat.c", "-o", HEAT_BIN, "-lm"])
    for n in MESHES:
        output = run([HEAT_BIN, str(n)], timeout=30)
        actual = parse_heat_output(output)
        expected = reference_heat_error(n)
        # Accommodate the six decimal places explicitly allowed by printf("%f").
        assert abs(actual - expected) <= 5.1e-7, \
            f"For N={n}, expected maximum error {expected:.12g}, got {actual:.12g}"


def test_compile_and_run_regression_program():
    run(["gcc", "/home/user/regression.c", "-o", REGRESSION_BIN, "-lm"])
    rows = [(7, 0.31), (13, 0.081), (29, 0.018), (61, 0.0049)]
    input_text = "".join(f"{n} {error}\n" for n, error in rows)
    output = run([REGRESSION_BIN], input_text=input_text)
    assert re.fullmatch(r"Slope: -?\d+\.\d{3}\n", output), \
        f"Regression output has the wrong format: {output!r}"
    actual = float(output[len("Slope: "):].strip())
    expected = ols_slope(rows)
    assert abs(actual - expected) <= 0.00051, \
        f"Expected OLS slope {expected:.6f}, got {actual:.3f}"


def test_run_orchestration_script():
    output_path = "/home/user/convergence_rate.txt"
    if os.path.exists(output_path):
        os.remove(output_path)

    started = time.time()
    run(["/home/user/run_simulation.sh"], cwd="/home/user", timeout=60)
    assert os.path.isfile(output_path), \
        f"{output_path} was not produced by run_simulation.sh"
    assert os.path.getmtime(output_path) >= started - 1.0, \
        f"{output_path} was not freshly produced by run_simulation.sh"

    data = ""
    for n in MESHES:
        heat_output = run([HEAT_BIN, str(n)], timeout=30).strip()
        data += f"{n} {heat_output}\n"
    expected_output = run([REGRESSION_BIN], input_text=data)
    with open(output_path, "r") as f:
        actual_output = f.read()
    assert actual_output == expected_output, \
        f"run_simulation.sh did not save the regression result exactly; expected {expected_output!r}, got {actual_output!r}"


def test_convergence_rate_output():
    """Check that the convergence rate output file exists and contains the correct slope."""
    output_path = "/home/user/convergence_rate.txt"
    assert os.path.isfile(output_path), f"{output_path} is missing. The simulation may not have run successfully."

    with open(output_path, "r") as f:
        content = f.read().strip()

    # Look for the required format: "Slope: %.3f"
    match = re.search(r"Slope:\s*(-?\d+\.\d+)", content)
    assert match is not None, f"Could not find the expected 'Slope: <value>' format in {output_path}. Content was: '{content}'"

    slope = float(match.group(1))
    # The theoretical spatial order of accuracy for FTCS is O(dx^2), so slope should be very close to -2.0
    assert abs(slope - (-2.0)) < 0.05, f"Expected slope to be near -2.000, but got {slope:.3f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
