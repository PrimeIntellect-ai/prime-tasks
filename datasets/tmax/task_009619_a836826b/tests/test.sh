#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import struct
import subprocess
from pathlib import Path

import pytest

SOURCE = Path("/home/user/src/etl_pipeline.c")
BINARY = Path("/tmp/etl_pipeline_submission")
EMBEDDINGS = Path("/home/user/data/embeddings.bin")
METADATA = Path("/home/user/data/metadata.txt")
OUTPUT = Path("/home/user/output/normalized_dataset.csv")


def test_c_source_exists():
    path = "/home/user/src/etl_pipeline.c"
    assert os.path.isfile(path), f"C source file {path} does not exist. Did you create it?"


def test_output_csv_exists_and_correct():
    path = "/home/user/output/normalized_dataset.csv"
    assert os.path.isfile(path), f"Output CSV {path} does not exist. Did you compile and run your program?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "id,token,e0,e1,e2,e3",
        "0,tok_alpha,0.600000,0.000000,0.800000,0.000000",
        "2,tok_gamma,0.000000,0.800000,0.600000,0.000000"
    ]
    expected_content = "\n".join(expected_lines)

    # Compare line by line to give a clear error message
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in CSV, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in CSV does not match expected.\nExpected: {expected}\nActual:   {actual}"


def expected_csv(vectors, tokens):
    lines = ["id,token,e0,e1,e2,e3"]
    for index, (vector, token) in enumerate(zip(vectors, tokens)):
        norm = math.sqrt(sum(component * component for component in vector))
        if norm == 0.0:
            continue
        values = ",".join(f"{component / norm:.6f}" for component in vector)
        lines.append(f"{index},{token},{values}")
    return lines


def run_case(vectors):
    tokens = [f"hidden_{secrets.token_hex(6)}" for _ in vectors]

    with EMBEDDINGS.open("wb") as binary_file:
        for vector in vectors:
            binary_file.write(struct.pack("<4f", *vector))
    METADATA.write_text("\n".join(tokens) + "\n")

    if OUTPUT.exists():
        OUTPUT.unlink()

    result = subprocess.run(
        [str(BINARY)], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled ETL program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT.is_file(), "Running the compiled ETL program did not create the output CSV."

    actual_lines = [
        line.strip() for line in OUTPUT.read_text().splitlines() if line.strip()
    ]
    expected_lines = expected_csv(vectors, tokens)
    assert actual_lines == expected_lines, (
        "Program output was incorrect for a verifier-generated input.\n"
        f"Expected: {expected_lines}\nActual:   {actual_lines}"
    )


def test_compile_and_execute_source_on_generated_inputs():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", str(SOURCE), "-o", str(BINARY), "-lm"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "The submitted C source did not compile with gcc.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)

    first = [
        (1.0, 2.0, 2.0, 0.0),
        (0.0, 0.0, 0.0, 0.0),
        (-3.0, 4.0, 0.0, 0.0),
        (0.0, 0.0, 0.0, -7.0),
        (8.0, 0.0, 6.0, 0.0),
    ]
    random.SystemRandom().shuffle(first)
    run_case(first)

    # A second invocation with different data verifies that output is produced by
    # processing the current inputs rather than by retaining the original fixture.
    second = [
        (5.0, 0.0, 0.0, 0.0),
        (0.0, 0.0, 0.0, 0.0),
        (0.0, -12.0, 5.0, 0.0),
        (0.0, 0.0, 0.0, 0.0),
    ]
    random.SystemRandom().shuffle(second)
    run_case(second)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
