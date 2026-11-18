#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

import pytest

HOME = "/home/user"
EDGES = os.path.join(HOME, "edges.csv")
EXECUTABLE = os.path.join(HOME, "analyze_network")


def run_command(command, timeout=60):
    return subprocess.run(
        command,
        cwd=HOME,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def reference_power_iteration(matrix):
    n = len(matrix)
    vector = [1.0] * n
    old_value = 0.0
    value = 0.0

    for _ in range(1000):
        new_vector = [
            sum(matrix[i][j] * vector[j] for j in range(n))
            for i in range(n)
        ]
        norm = math.sqrt(sum(x * x for x in new_vector))
        assert norm > 0.0
        new_vector = [x / norm for x in new_vector]

        multiplied = [
            sum(matrix[i][j] * new_vector[j] for j in range(n))
            for i in range(n)
        ]
        value = sum(new_vector[i] * multiplied[i] for i in range(n))

        if abs(value - old_value) < 1e-6:
            break
        old_value = value
        vector = new_vector

    return value


def write_matrix_as_edges(matrix):
    with open(EDGES, "w") as f:
        for source, row in enumerate(matrix):
            for target, weight in enumerate(row):
                f.write(f"{source},{target},{weight:.2f}\n")


def read_and_check_eigenvalue(expected):
    eigenvalue_file = os.path.join(HOME, "eigenvalue.log")
    assert os.path.isfile(eigenvalue_file), f"{eigenvalue_file} was not created"
    with open(eigenvalue_file, "r") as f:
        text = f.read().strip()
    assert re.fullmatch(r"-?\d+\.\d{4}", text), \
        f"Eigenvalue must be formatted to exactly 4 decimal places, got {text!r}"
    observed = float(text)
    assert abs(observed - expected) <= 0.00011, \
        f"Expected eigenvalue approximately {expected:.8f}, got {observed:.4f}"


def random_symmetric_matrix(n, low_hundredths, span_hundredths):
    rng = secrets.SystemRandom()
    matrix = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i, n):
            value = (low_hundredths + rng.randrange(span_hundredths)) / 100.0
            matrix[i][j] = value
            matrix[j][i] = value
    return matrix


def test_files_exist():
    assert os.path.isfile("/home/user/analyze_network.cpp"), "analyze_network.cpp is missing"
    assert os.path.isfile("/home/user/Makefile"), "Makefile is missing"
    assert os.path.isfile("/home/user/run_pipeline.sh"), "run_pipeline.sh is missing"


def test_makefile_flags():
    with open("/home/user/Makefile", "r") as f:
        content = f.read()
    assert "-O3" in content, "Makefile must include -O3 flag"
    assert "-pg" in content, "Makefile must include -pg flag"


def test_pipeline_execution_and_outputs():
    assert os.access("/home/user/run_pipeline.sh", os.X_OK), "run_pipeline.sh is not executable"

    # Force the pipeline to build the submitted source rather than use a stale artifact.
    for path in (EXECUTABLE, os.path.join(HOME, "gmon.out"),
                 os.path.join(HOME, "eigenvalue.log"),
                 os.path.join(HOME, "profile_results.txt")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run_command(["/bin/bash", "./run_pipeline.sh"])
    assert result.returncode == 0, f"run_pipeline.sh failed with error:\n{result.stderr}"

    assert os.path.isfile(EXECUTABLE), "Makefile did not create analyze_network"
    assert os.access(EXECUTABLE, os.X_OK), "analyze_network is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analyze_network is not a compiled ELF executable"

    eigenvalue_file = "/home/user/eigenvalue.log"
    assert os.path.isfile(eigenvalue_file), f"{eigenvalue_file} was not created"
    with open(eigenvalue_file, "r") as f:
        val = f.read().strip()
    assert val == "3.0000", f"Expected eigenvalue 3.0000, got {val}"

    profile_file = "/home/user/profile_results.txt"
    assert os.path.isfile(profile_file), f"{profile_file} was not created"
    with open(profile_file, "r") as f:
        profile_content = f.read()
    assert "Flat profile" in profile_content or "Call graph" in profile_content, \
        "profile_results.txt does not appear to contain valid gprof output"


def test_executable_computes_changed_networks():
    # Values are generated only during verification, and the two cases have
    # different dynamic dimensions and eigenvalues far from the fixture's 3.0.
    cases = [
        random_symmetric_matrix(3, 15, 41),
        random_symmetric_matrix(6, 110, 91),
    ]

    for matrix in cases:
        write_matrix_as_edges(matrix)
        expected = reference_power_iteration(matrix)
        try:
            os.remove(os.path.join(HOME, "eigenvalue.log"))
        except FileNotFoundError:
            pass

        result = run_command([EXECUTABLE])
        assert result.returncode == 0, \
            f"analyze_network failed on changed edge data:\n{result.stderr}"
        read_and_check_eigenvalue(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
