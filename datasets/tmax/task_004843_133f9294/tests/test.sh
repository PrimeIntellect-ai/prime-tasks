#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile

SOURCE = "/home/user/diffusion.c"
BINARY = "/home/user/diffusion"
OUTPUT = "/home/user/final_state.txt"


def parse_output(content):
    assert "NaN" not in content, "The output contains 'NaN', indicating the integrator diverged."
    assert "Step size too small" not in content, "The output indicates the step size became too small."
    lines = content.strip().splitlines()
    assert len(lines) == 1, f"Expected a single line of output, but found {len(lines)} lines."
    parts = lines[0].split()
    assert len(parts) == 5, f"Expected 5 numbers in the output, but found {len(parts)}."
    try:
        numbers = [float(p) for p in parts]
    except ValueError:
        assert False, "The output contains non-numeric values."
    assert all(math.isfinite(x) for x in numbers), "The output contains a non-finite value."
    return numbers


def expected_state():
    # Independent implementation of the stated corrected adaptive Euler scheme.
    A = [
        [-2.0, 1.0, 0.0, 0.0, 1.0],
        [1.0, -2.0, 1.0, 0.0, 0.0],
        [0.0, 1.0, -2.0, 1.0, 0.0],
        [0.0, 0.0, 1.0, -2.0, 1.0],
        [1.0, 0.0, 0.0, 1.0, -2.0],
    ]

    def deriv(x):
        return [sum(A[i][j] * x[j] for j in range(5)) for i in range(5)]

    x = [10.0, 0.0, 0.0, 0.0, 0.0]
    t = 0.0
    dt = 0.1
    tol = 1e-4
    iterations = 0
    while t < 2.0:
        iterations += 1
        assert iterations < 1000000, "Independent simulation failed to converge."
        if t + dt > 2.0:
            dt = 2.0 - t
        dxdt = deriv(x)
        x1 = [x[i] + dxdt[i] * dt for i in range(5)]
        x_half = [x[i] + dxdt[i] * (dt / 2.0) for i in range(5)]
        dxdt_half = deriv(x_half)
        x2 = [x_half[i] + dxdt_half[i] * (dt / 2.0) for i in range(5)]
        err = sum(abs(x1[i] - x2[i]) for i in range(5)) / 5.0 + 1e-16
        dt_new = dt * math.sqrt(tol / err)
        if err <= tol:
            x = x2
            t += dt
        dt = min(dt_new, 0.5)
        assert dt >= 1e-6, "Independent corrected simulation reached a too-small step."
    return x


def run_program(path):
    result = subprocess.run([path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=10)
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout, parse_output(result.stdout)


def assert_correct_state(numbers):
    expected = expected_state()
    for i, (actual, wanted) in enumerate(zip(numbers, expected)):
        assert math.isclose(actual, wanted, rel_tol=0.0, abs_tol=7e-4), (
            f"Value at index {i} ({actual}) does not match the corrected simulation "
            f"at t=2.0 (expected approximately {wanted})."
        )


def test_final_state_exists():
    assert os.path.exists(OUTPUT), f"The file {OUTPUT} is missing. Did you run the simulation and redirect output?"
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."


def test_final_state_content():
    with open(OUTPUT, "r") as f:
        content = f.read()
    numbers = parse_output(content)
    total_mass = sum(numbers)
    assert math.isclose(total_mass, 10.0, rel_tol=1e-3), \
        f"Total mass is not conserved. Sum is {total_mass}, expected ~10.0."
    assert_correct_state(numbers)


def test_diffusion_c_fixed():
    assert os.path.exists(SOURCE), f"The file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original source assertion.
    assert "sqrt(tol / err)" in content or "sqrt(tol/err)" in content, \
        "The step-size adaptation logic does not appear to be fixed."

    # Ensure the required expression is executable code, rather than a comment.
    code = re.sub(r"/\*.*?\*/|//[^\n]*", "", content, flags=re.DOTALL)
    match = re.search(r"\bdt_new\s*=\s*([^;]+);", code)
    assert match, "Could not find an assignment to dt_new in executable source code."
    expression = match.group(1)
    assert re.search(r"\bdt\s*\*\s*sqrt\s*\(\s*tol\s*/\s*err\s*\)", expression), \
        "dt_new must shrink for err > tol by using dt * sqrt(tol / err)."


def test_binary_exists_and_is_real_executable():
    assert os.path.exists(BINARY), f"The compiled binary {BINARY} is missing."
    assert os.path.isfile(BINARY), f"The compiled binary {BINARY} is not a regular file."
    assert os.access(BINARY, os.X_OK), f"The file {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary."


def test_compiled_source_binary_and_saved_output():
    with tempfile.TemporaryDirectory() as tmp:
        rebuilt = os.path.join(tmp, "diffusion")
        compile_result = subprocess.run(
            ["gcc", "-O3", SOURCE, "-lm", "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compile_result.returncode == 0, \
            f"The submitted source does not compile with the required command: {compile_result.stderr}"

        rebuilt_stdout, rebuilt_numbers = run_program(rebuilt)
        installed_stdout, installed_numbers = run_program(BINARY)
        assert_correct_state(rebuilt_numbers)
        assert_correct_state(installed_numbers)

        with open(OUTPUT, "r") as f:
            saved = f.read()
        assert saved == installed_stdout, \
            "final_state.txt is not the standard output produced by the installed binary."
        assert installed_stdout == rebuilt_stdout, \
            "The installed binary's output does not match a fresh required compilation of diffusion.c."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
