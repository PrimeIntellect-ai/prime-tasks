#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import re
import subprocess
from decimal import Decimal

import pytest


def test_clean_data_file():
    """Test that clean_data.csv exists and has the correct content."""
    file_path = '/home/user/clean_data.csv'
    assert os.path.isfile(file_path), f"File missing: {file_path}"

    expected_content = """10.0,2.0,3.5
5.0,2.5,1.0
0.0,0.0,0.0
8.0,4.0,2.0
-3.0,1.5,0.5
2.0,2.0,2.0"""

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {file_path} is incorrect."


def test_rust_project_structure():
    """Test that the Rust project was initialized correctly."""
    cargo_toml = '/home/user/data_analyzer/Cargo.toml'
    main_rs = '/home/user/data_analyzer/src/main.rs'

    assert os.path.isfile(cargo_toml), f"Rust project Cargo.toml missing at {cargo_toml}"
    assert os.path.isfile(main_rs), f"Rust project main.rs missing at {main_rs}"

    with open(cargo_toml, 'r') as f:
        content = f.read()

    assert 'ndarray' in content, "Cargo.toml is missing the 'ndarray' dependency."
    assert 'csv' in content, "Cargo.toml is missing the 'csv' dependency."


def test_trace_output():
    """Test that trace.txt exists and has the correct calculated value."""
    file_path = '/home/user/trace.txt'
    assert os.path.isfile(file_path), f"File missing: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == "256.00", f"Content of {file_path} is incorrect. Expected '256.00', got '{content}'."


def test_rust_program_executes_and_computes_generated_inputs():
    """Build and run the submitted Rust program against verifier-generated matrices."""
    project_dir = '/home/user/data_analyzer'
    clean_path = '/home/user/clean_data.csv'
    trace_path = '/home/user/trace.txt'

    with open(clean_path, 'rb') as f:
        original_clean = f.read()
    original_trace = None
    if os.path.isfile(trace_path):
        with open(trace_path, 'rb') as f:
            original_trace = f.read()

    rng = random.SystemRandom()
    probes = []
    for row_count in (2, 7):
        matrix = []
        for _ in range(row_count):
            # Half-integers are exactly representable and still exercise decimals
            # and negative values without ambiguous rounding.
            matrix.append([Decimal(rng.randint(-40, 40)) / 2 for _ in range(3)])
        probes.append(matrix)

    try:
        for matrix in probes:
            with open(clean_path, 'w', newline='') as f:
                for row in matrix:
                    f.write(','.join(format(value, 'f') for value in row) + '\n')

            if os.path.exists(trace_path):
                os.remove(trace_path)

            result = subprocess.run(
                ['cargo', 'run', '--quiet'],
                cwd=project_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=180,
            )
            assert result.returncode == 0, (
                "The Rust project failed to build or run.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isfile(trace_path), "Running the Rust program did not create /home/user/trace.txt"

            with open(trace_path, 'r') as f:
                actual = f.read().strip()

            expected_value = sum(value * value for row in matrix for value in row)
            expected = f"{expected_value:.2f}"
            assert re.fullmatch(r'-?\d+\.\d{2}', actual), (
                f"Trace output is not formatted to exactly two decimal places: {actual!r}"
            )
            assert actual == expected, (
                f"Rust program produced {actual!r} for generated input; expected {expected!r}."
            )
    finally:
        with open(clean_path, 'wb') as f:
            f.write(original_clean)
        if original_trace is None:
            if os.path.exists(trace_path):
                os.remove(trace_path)
        else:
            with open(trace_path, 'wb') as f:
                f.write(original_trace)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
