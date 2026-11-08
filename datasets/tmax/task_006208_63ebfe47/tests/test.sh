#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import secrets
import subprocess

import pytest

HOME = "/home/user"
INPUT = f"{HOME}/data/input_vectors.txt"
OUTPUT = f"{HOME}/output_angles.txt"
BUILD = f"{HOME}/build.sh"
PROCESS = f"{HOME}/process_geometry.py"

CANONICAL_LINES = [
    "1.0, 0.0, 0.0 | 0.0, 1.0, 0.0",
    "2.5, 3.1, 0.0 | -1.0, 2.0, 5.0",
    "0.0, 0.0, 1.0 | 0.0, 0.0, -1.0",
    "1.0, 1.0, 1.0 | 2.0, 2.0, 2.0",
    "0.5, 0.5, 0.5 | -0.5, -0.5, 0.5",
    "3.0, 4.0, 0.0 | 0.0, 3.0, 4.0",
    "0.1, 0.2, 0.3 | 0.3, 0.6, 0.9",
    "5.0, 12.0, 0.0 | 12.0, 5.0, 0.0",
]


def parse_vector_line(line):
    left, right = line.split("|")
    return tuple(map(float, left.split(","))), tuple(map(float, right.split(",")))


def expected_angle_degrees(line):
    v1, v2 = parse_vector_line(line)
    dot = sum(a * b for a, b in zip(v1, v2))
    mag1 = math.sqrt(sum(a * a for a in v1))
    mag2 = math.sqrt(sum(b * b for b in v2))
    cosine = max(-1.0, min(1.0, dot / (mag1 * mag2)))
    return math.degrees(math.acos(cosine))


def write_input(lines):
    with open(INPUT, "w") as f:
        f.write("\n".join(lines) + "\n")


def read_angles(expected_count):
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} is missing."
    with open(OUTPUT) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == expected_count, (
        f"Expected {expected_count} output lines, but got {len(lines)}."
    )
    try:
        values = [float(line) for line in lines]
    except ValueError as exc:
        pytest.fail(f"output_angles.txt contains a non-numeric value: {exc}")
    assert all(math.isfinite(value) for value in values), "Angles must all be finite."
    return values


def assert_angles(lines, actual):
    expected = [expected_angle_degrees(line) for line in lines]
    for index, (got, want) in enumerate(zip(actual, expected), 1):
        assert math.isclose(got, want, rel_tol=1e-9, abs_tol=1e-7), (
            f"Incorrect angle on line {index}: expected {want} degrees, got {got}."
        )


def run_build(lines):
    write_input(lines)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([BUILD], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, (
        f"build.sh failed. stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    values = read_angles(len(lines))
    assert_angles(lines, values)


def test_failing_line_identified():
    path = f"{HOME}/failing_line.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path) as f:
        content = f.read().strip()
    assert content == "7", f"Expected failing line to be '7', but got {content!r}."


def test_mre_contains_extracted_logic_and_reproduces_error():
    path = f"{HOME}/mre.py"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path) as f:
        source = f.read()

    tree = ast.parse(source, filename=path)
    assert not any(isinstance(node, ast.Raise) for node in ast.walk(tree)), (
        "mre.py must reproduce the domain error through the extracted math logic, "
        "not by explicitly raising it."
    )
    assert "0.1" in source and "0.2" in source and "0.3" in source
    assert "0.6" in source and "0.9" in source, (
        "mre.py must hardcode the values from failing input line 7."
    )
    assert "|" in source and ".split" in source and "float" in source, (
        "mre.py must include the extracted vector parsing logic."
    )
    called_attributes = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert "sqrt" in called_attributes and "acos" in called_attributes, (
        "mre.py must include the extracted magnitude and angle math logic."
    )

    result = subprocess.run(
        ["python3", path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode != 0, "mre.py should fail, but it exited successfully."
    assert "ValueError: math domain error" in result.stderr, (
        "mre.py did not reproduce the exact 'ValueError: math domain error'."
    )


def test_build_and_all_canonical_outputs():
    assert os.path.isfile(BUILD), f"File {BUILD} is missing."
    assert os.access(BUILD, os.X_OK), f"File {BUILD} is not executable."
    assert os.path.isfile(PROCESS), f"File {PROCESS} is missing."
    run_build(CANONICAL_LINES)


def test_pipeline_processes_unseen_vectors_in_degrees():
    rng = secrets.SystemRandom()
    lines = []

    # Fresh nonparallel vectors prevent a fixed eight-line output from passing.
    while len(lines) < 7:
        v1 = tuple(rng.randint(-900, 900) / 37.0 for _ in range(3))
        v2 = tuple(rng.randint(-900, 900) / 41.0 for _ in range(3))
        if sum(x*x for x in v1) == 0 or sum(x*x for x in v2) == 0:
            continue
        cross = (
            v1[1]*v2[2] - v1[2]*v2[1],
            v1[2]*v2[0] - v1[0]*v2[2],
            v1[0]*v2[1] - v1[1]*v2[0],
        )
        if sum(x*x for x in cross) < 1e-12:
            continue
        lines.append(
            f"{v1[0]}, {v1[1]}, {v1[2]} | {v2[0]}, {v2[1]}, {v2[2]}"
        )

    # Exercise both clamp endpoints, including the original floating-point edge case.
    a, b, c = (rng.randint(1, 700) / 113.0 for _ in range(3))
    scale = rng.randint(2, 9)
    lines.extend([
        f"{a}, {b}, {c} | {a*scale}, {b*scale}, {c*scale}",
        f"{a}, {b}, {c} | {-a*scale}, {-b*scale}, {-c*scale}",
        "0.1, 0.2, 0.3 | 0.3, 0.6, 0.9",
    ])

    try:
        run_build(lines)
    finally:
        write_input(CANONICAL_LINES)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
