#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile
import pytest


def compile_source(tmpdir):
    cpp_path = "/home/user/stencil.cpp"
    assert os.path.isfile(cpp_path), f"File {cpp_path} does not exist."
    bin_path = os.path.join(tmpdir, "stencil")
    result = subprocess.run(
        ["g++", "-O2", cpp_path, "-o", bin_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"
    return bin_path


def run_stencil(bin_path, n):
    result = subprocess.run(
        [bin_path, str(n)], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"Execution failed for N={n}:\n{result.stderr}"
    assert result.stderr == "", f"Unexpected stderr for N={n}: {result.stderr}"
    assert re.fullmatch(r"[0-9]+\.[0-9]{6}\n", result.stdout), (
        f"Output formatting changed for N={n}: {result.stdout!r}"
    )
    return result.stdout, float(result.stdout.strip())


def reference_error(n):
    """Independently evaluate the specified, corrected five-point stencil."""
    h = 1.0 / n
    width = n + 1
    values = [0.0] * (width * width)
    for i in range(width):
        x = i * h
        for j in range(width):
            y = j * h
            values[i * width + j] = math.sin(math.pi * x) * math.sin(math.pi * y)

    maximum = 0.0
    for i in range(1, n):
        for j in range(1, n):
            center = values[i * width + j]
            numerical = (
                values[(i + 1) * width + j]
                + values[(i - 1) * width + j]
                + values[i * width + j + 1]
                + values[i * width + j - 1]
                - 4.0 * center
            ) / (h * h)
            analytical = -2.0 * math.pi * math.pi * math.sin(math.pi * i * h) * math.sin(math.pi * j * h)
            maximum = max(maximum, abs(numerical - analytical))
    return maximum


def test_stencil_cpp_fixes():
    """Test that stencil.cpp is fixed and produces correct output."""
    cpp_path = "/home/user/stencil.cpp"
    assert os.path.isfile(cpp_path), f"File {cpp_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        bin_path = os.path.join(tmpdir, "stencil")

        # Compile the modified C++ code
        compile_cmd = ["g++", "-O2", cpp_path, "-o", bin_path]
        result = subprocess.run(compile_cmd, capture_output=True, text=True)
        assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"

        # Run for N=100
        run_cmd = [bin_path, "100"]
        result = subprocess.run(run_cmd, capture_output=True, text=True)
        assert result.returncode == 0, f"Execution failed for N=100:\n{result.stderr}"

        output = result.stdout.strip()
        try:
            error_val = float(output)
        except ValueError:
            pytest.fail(f"Could not parse output as float: {output}")

        assert error_val < 0.002, f"Error for N=100 is {error_val}, expected < 0.002. The bug might not be fully fixed."


def test_dynamic_stencil_results():
    """Exercise non-fixed grid sizes and compare with an independent stencil."""
    excluded = {10, 20, 40, 80, 100}
    candidates = [n for n in range(6, 97) if n not in excluded]
    grid_sizes = secrets.SystemRandom().sample(candidates, 8)

    with tempfile.TemporaryDirectory() as tmpdir:
        bin_path = compile_source(tmpdir)
        for n in grid_sizes:
            _, actual = run_stencil(bin_path, n)
            expected = reference_error(n)
            assert math.isfinite(actual), f"Non-finite error for N={n}: {actual}"
            assert abs(actual - expected) <= 1.1e-6, (
                f"Incorrect stencil result for N={n}: got {actual:.6f}, "
                f"expected {expected:.6f}"
            )


def test_errors_txt():
    """Test that errors.txt contains the correct convergence results."""
    txt_path = "/home/user/errors.txt"
    assert os.path.isfile(txt_path), f"File {txt_path} does not exist."

    with open(txt_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in errors.txt, found {len(lines)}."

    expected_values = [0.162319, 0.040989, 0.010265, 0.002568]

    for i, (line, expected) in enumerate(zip(lines, expected_values)):
        try:
            val = float(line)
        except ValueError:
            pytest.fail(f"Line {i+1} in errors.txt is not a valid float: {line}")

        assert abs(val - expected) < 1e-4, f"Value on line {i+1} is {val}, expected approximately {expected}."


def test_errors_txt_matches_program_runs():
    """Ensure the saved convergence data is exactly what the fixed program prints."""
    txt_path = "/home/user/errors.txt"
    assert os.path.isfile(txt_path), f"File {txt_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        bin_path = compile_source(tmpdir)
        outputs = []
        for n in (10, 20, 40, 80):
            stdout, actual = run_stencil(bin_path, n)
            expected = reference_error(n)
            assert abs(actual - expected) <= 1.1e-6, (
                f"Incorrect convergence result for N={n}: got {actual:.6f}, "
                f"expected {expected:.6f}"
            )
            outputs.append(stdout)

    with open(txt_path, "r") as f:
        saved = f.read()
    assert saved == "".join(outputs), (
        "errors.txt must contain, in order, exactly the output produced by runs "
        "for N=10, 20, 40, and 80"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
