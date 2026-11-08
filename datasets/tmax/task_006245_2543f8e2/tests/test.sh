#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import math
import os
import re
import secrets
import subprocess

import pytest

PROJECT = "/home/user/poly_service"
INPUT = os.path.join(PROJECT, "input.txt")
OUTPUT = os.path.join(PROJECT, "output.log")
BINARY = os.path.join(PROJECT, "poly_eval")

ORIGINAL_INPUT = (
    "DEG: 2 | COEFFS: 1.0,2.0,3.0 | X: 2.0\n"
    "DEG: 3 | COEFFS: 0.5,0.0,1.5,2.0| X: 1.0\n"
    "DEG: 1 | COEFFS: -1.0,5.0| X: 3.5\n"
)
ORIGINAL_RESULTS = [17.0, 4.0, 16.5]


def compute_expected_output(input_path):
    results = []
    with open(input_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            deg_match = re.search(r'DEG:\s*(\d+)', line)
            coeffs_match = re.search(r'COEFFS:\s*([^|]+)', line)
            x_match = re.search(r'X:\s*([-\d\.]+)', line)

            if not (deg_match and coeffs_match and x_match):
                continue

            degree = int(deg_match.group(1))
            coeffs_str = coeffs_match.group(1).strip()
            x = float(x_match.group(1))
            coeffs = [float(c.strip()) for c in coeffs_str.split(',')]

            res = 0.0
            for i in range(min(degree + 1, len(coeffs))):
                res += coeffs[i] * (x ** i)
            results.append(res)
    return results


@pytest.fixture(scope="session", autouse=True)
def rebuild_from_makefile():
    for name in ("poly_eval", "poly_eval.o", "fastmath.o", "libfastmath.a"):
        path = os.path.join(PROJECT, name)
        if os.path.lexists(path):
            os.remove(path)

    proc = subprocess.run(
        ["make"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert proc.returncode == 0, "make failed:\n" + proc.stdout


@contextlib.contextmanager
def temporary_input(contents):
    old = None
    existed = os.path.exists(INPUT)
    if existed:
        with open(INPUT, "rb") as f:
            old = f.read()
    try:
        with open(INPUT, "w", newline="") as f:
            f.write(contents)
        yield
    finally:
        if existed:
            with open(INPUT, "wb") as f:
                f.write(old)
        elif os.path.exists(INPUT):
            os.remove(INPUT)


def parse_numeric_stdout(stdout, expected_count):
    lines = stdout.splitlines()
    assert len(lines) == expected_count, (
        f"Expected {expected_count} output lines, got {len(lines)}: {stdout!r}"
    )
    values = []
    for i, line in enumerate(lines, 1):
        assert line.strip() == line and line, f"Invalid output line {i}: {line!r}"
        try:
            value = float(line)
        except ValueError:
            pytest.fail(f"Output line {i} is not a valid float: {line!r}")
        assert math.isfinite(value), f"Output line {i} is not finite"
        values.append(value)
    return values


def make_runtime_cases():
    rng = secrets.SystemRandom()
    cases = [
        (2, [1.0, 2.0, 37.125], 2.0, False),
        (0, [-7.75], 1.25, False),
        (5, [0.5, -1.25, 2.0, 0.75, -0.5, 3.125], -1.5, True),
    ]
    for i in range(7):
        degree = rng.randint(1, 6)
        coeffs = [rng.randint(-4000, 4000) / 1000.0 for _ in range(degree + 1)]
        if coeffs[-1] == 0:
            coeffs[-1] = 1.375
        x = rng.randint(-2500, 2500) / 1000.0
        cases.append((degree, coeffs, x, bool(i % 2)))
    return cases


def render_cases(cases):
    lines = []
    expected = []
    for degree, coeffs, x, trailing_space in cases:
        rendered_coeffs = [f"{c:.6f}" for c in coeffs]
        rendered_x = f"{x:.6f}"
        gap = " " if trailing_space else ""
        lines.append(
            f"DEG: {degree} | COEFFS: {','.join(rendered_coeffs)}{gap}| X: {rendered_x}"
        )
        parsed_coeffs = [float(c) for c in rendered_coeffs]
        parsed_x = float(rendered_x)
        expected.append(sum(c * (parsed_x ** i) for i, c in enumerate(parsed_coeffs)))
    return "\n".join(lines) + "\n", expected


def test_output_log_exists_and_correct():
    assert os.path.exists(INPUT), f"Input file missing: {INPUT}"
    assert os.path.exists(OUTPUT), f"Output log missing: {OUTPUT}"

    expected_results = compute_expected_output(INPUT)
    with open(OUTPUT, 'r') as f:
        output_lines = [line.strip() for line in f if line.strip()]

    assert len(output_lines) == len(expected_results), "Number of output lines does not match number of input lines"
    for i, (out_val, exp_val) in enumerate(zip(output_lines, expected_results)):
        try:
            out_float = float(out_val)
        except ValueError:
            pytest.fail(f"Output line {i+1} is not a valid float: {out_val}")
        assert abs(out_float - exp_val) < 1e-6, f"Line {i+1} mismatch: expected {exp_val}, got {out_float}"


def test_original_fixture_and_output_were_not_emptied_or_replaced():
    with open(INPUT, "r", newline="") as f:
        assert f.read() == ORIGINAL_INPUT, "input.txt was modified"
    with open(OUTPUT, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == len(ORIGINAL_RESULTS)
    assert all(line and line.strip() == line for line in lines)
    values = [float(line) for line in lines]
    for actual, expected in zip(values, ORIGINAL_RESULTS):
        assert math.isfinite(actual)
        assert abs(actual - expected) < 1e-6


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), "Compiled binary 'poly_eval' is missing"
    assert os.access(BINARY, os.X_OK), "Compiled binary 'poly_eval' is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "poly_eval is not a compiled ELF binary"


def test_makefile_fixed():
    makefile_path = os.path.join(PROJECT, "Makefile")
    assert os.path.exists(makefile_path), "Makefile is missing"
    with open(makefile_path, 'r') as f:
        content = f.read()
    assert re.search(r'g\+\+.*-o\s+poly_eval.*(libfastmath\.a|fastmath\.o|fastmath\.cpp)', content), "Makefile does not link fastmath correctly"


def test_poly_eval_cpp_fixes():
    cpp_path = os.path.join(PROJECT, "poly_eval.cpp")
    assert os.path.exists(cpp_path), "poly_eval.cpp is missing"
    with open(cpp_path, 'r') as f:
        content = f.read()
    assert "delete[]" in content or "std::vector" in content or "unique_ptr" in content, "Memory leak not fixed (missing delete[] or smart pointer/vector)"
    assert "degree + 1" in content or "degree+1" in content or "std::vector" in content, "Array allocation size not fixed (should be degree + 1)"


def test_rebuilt_program_on_runtime_generated_inputs():
    input_text, expected = render_cases(make_runtime_cases())
    with temporary_input(input_text):
        proc = subprocess.run(
            [BINARY], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
        )
    assert proc.returncode == 0, f"poly_eval failed: {proc.stderr}"
    assert proc.stderr == "", f"poly_eval wrote to stderr: {proc.stderr!r}"
    actual = parse_numeric_stdout(proc.stdout, len(expected))
    for i, (got, want) in enumerate(zip(actual, expected), 1):
        assert math.isclose(got, want, rel_tol=2e-5, abs_tol=2e-5), (
            f"Runtime case {i}: expected {want}, got {got}"
        )


def test_no_per_line_memory_leak_under_valgrind():
    cases = [(4, [1.25, -2.5, 3.75, -4.125, 5.5], 1.75, False)] * 40
    input_text, _ = render_cases(cases)
    with temporary_input(input_text):
        proc = subprocess.run(
            [
                "valgrind", "--quiet", "--leak-check=full",
                "--show-leak-kinds=all",
                "--errors-for-leak-kinds=definite,indirect,possible",
                "--error-exitcode=99", BINARY,
            ],
            cwd=PROJECT, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=45
        )
    assert proc.returncode == 0, "valgrind detected memory errors or leaks:\n" + proc.stderr
    parse_numeric_stdout(proc.stdout, len(cases))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
