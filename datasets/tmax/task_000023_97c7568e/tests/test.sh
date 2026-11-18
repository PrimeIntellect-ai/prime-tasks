#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

PROJECT = "/home/user/pdb_feature_extractor"
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
INPUT = "/home/user/input.pdb"


def write_pdb(points):
    with open(INPUT, "w") as f:
        for i, (x, y, z) in enumerate(points, 1):
            f.write(
                f"ATOM  {i:5d}  C   MOL     1    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C\n"
            )


def covariance(points):
    n = float(len(points))
    means = [sum(p[i] for p in points) / n for i in range(3)]
    cov = [[0.0] * 3 for _ in range(3)]
    for p in points:
        delta = [p[i] - means[i] for i in range(3)]
        for i in range(3):
            for j in range(3):
                cov[i][j] += delta[i] * delta[j]
    return [[value / n for value in row] for row in cov]


def cholesky_trace(matrix):
    lower = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(i + 1):
            residual = matrix[i][j] - sum(lower[i][k] * lower[j][k] for k in range(j))
            if i == j:
                assert residual > 0.0
                lower[i][j] = math.sqrt(residual)
            else:
                lower[i][j] = residual / lower[j][j]
    return sum(lower[i][i] for i in range(3))


def expected_trace(points, jitter):
    matrix = covariance(points)
    if jitter:
        for i in range(3):
            matrix[i][i] += 1e-5
    return cholesky_trace(matrix)


def run_program():
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"'cargo run' failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    matches = re.findall(
        r"Trace:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)",
        result.stdout,
    )
    assert matches, f"cargo run did not print a numeric Trace value: {result.stdout!r}"
    return float(matches[-1])


def test_feature_trace_output():
    trace_file = "/home/user/feature_trace.txt"
    assert os.path.isfile(trace_file), f"Output file {trace_file} is missing"

    with open(trace_file, "r") as f:
        content = f.read().strip()

    try:
        trace_val = float(content)
    except ValueError:
        assert False, f"Content of {trace_file} is not a valid float: '{content}'"

    expected_trace_value = math.sqrt(0.50001) + math.sqrt(0.50001) + math.sqrt(0.00001)
    assert math.isclose(trace_val, expected_trace_value, rel_tol=1e-4, abs_tol=1e-4), \
        f"Trace value {trace_val} is not within tolerance of expected {expected_trace_value}"


def test_rust_test_exists_and_passes():
    assert os.path.isfile(MAIN_RS), f"File {MAIN_RS} is missing"

    with open(MAIN_RS, "r") as f:
        content = f.read()

    assert "test_planar_jitter" in content, "The test 'test_planar_jitter' was not found in src/main.rs"

    result = subprocess.run(
        ["cargo", "test"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )

    assert result.returncode == 0, f"'cargo test' failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert "test_planar_jitter" in result.stdout or "test_planar_jitter" in result.stderr, \
        "The test 'test_planar_jitter' does not appear to have been run by cargo test"


def test_program_uses_exact_fallback_jitter():
    old_input = None
    if os.path.exists(INPUT):
        with open(INPUT, "rb") as f:
            old_input = f.read()

    try:
        original_points = [
            (1.0, 0.0, 0.0),
            (0.0, 1.0, 0.0),
            (-1.0, 0.0, 0.0),
            (0.0, -1.0, 0.0),
        ]
        write_pdb(original_points)
        actual = run_program()
        expected = expected_trace(original_points, jitter=True)
        assert math.isclose(actual, expected, rel_tol=1e-8, abs_tol=1e-8), \
            f"cargo run produced {actual}; expected planar fallback trace {expected}"

        # Runtime-randomized planar covariance with a nonzero xy cross term.
        a = (700 + secrets.randbelow(1801)) / 1000.0
        b = (700 + secrets.randbelow(1801)) / 1000.0
        d = (200 + secrets.randbelow(801)) / 1000.0
        z = (-1000 + secrets.randbelow(2001)) / 1000.0
        planar_points = [(a, d, z), (-a, -d, z), (0.0, b, z), (0.0, -b, z)]
        write_pdb(planar_points)
        actual = run_program()
        expected = expected_trace(planar_points, jitter=True)
        assert math.isclose(actual, expected, rel_tol=1e-8, abs_tol=1e-8), \
            f"Planar input produced {actual}; exact 1e-5 fallback jitter requires {expected}"

        # A full-rank covariance must use the initial Cholesky result, without jitter.
        x = (800 + secrets.randbelow(1701)) / 1000.0
        y = (800 + secrets.randbelow(1701)) / 1000.0
        z = (800 + secrets.randbelow(1701)) / 1000.0
        full_rank_points = [
            (x, 0.0, 0.0), (-x, 0.0, 0.0),
            (0.0, y, 0.0), (0.0, -y, 0.0),
            (0.0, 0.0, z), (0.0, 0.0, -z),
        ]
        write_pdb(full_rank_points)
        actual = run_program()
        expected = expected_trace(full_rank_points, jitter=False)
        assert math.isclose(actual, expected, rel_tol=1e-8, abs_tol=1e-8), \
            f"Full-rank input produced {actual}; jitter must only be added after Cholesky failure (expected {expected})"
    finally:
        if old_input is None:
            if os.path.exists(INPUT):
                os.remove(INPUT)
        else:
            with open(INPUT, "wb") as f:
                f.write(old_input)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
