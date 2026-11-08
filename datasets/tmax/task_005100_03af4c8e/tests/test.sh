#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import pytest


def test_calc_engine_executable_exists():
    path = "/home/user/calc_engine"
    assert os.path.isfile(path), f"Executable {path} is missing. Did you compile the code?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Executable {path} is not a compiled ELF binary."


def test_output_txt_exists_and_correct():
    path = "/home/user/output.txt"
    assert os.path.isfile(path), f"Output file {path} is missing. Did you run the compiled program?"

    with open(path, "r") as f:
        lines = f.read().strip().split()

    assert len(lines) == 4, f"Expected 4 lines of output in {path}, but found {len(lines)}."

    try:
        values = [float(line) for line in lines]
    except ValueError:
        pytest.fail(f"Output file {path} contains non-numeric data.")

    expected_values = [0.5, 2.0, 0.0, 1.0]

    for i, (actual, expected) in enumerate(zip(values, expected_values)):
        assert abs(actual - expected) < 1e-6, f"Line {i+1} in {path} is {actual}, expected {expected}."


def run_and_check(executable, cases):
    input_path = "/home/user/input_batch.dat"
    output_path = "/home/user/output.txt"

    with open(input_path, "w") as f:
        for x, y in cases:
            f.write(f"{x:.17g} {y:.17g}\n")

    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        [executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} failed on generated input with exit code {result.returncode}: "
        f"{result.stderr}"
    )
    assert os.path.isfile(output_path), f"{executable} did not create {output_path}."

    with open(output_path, "r") as f:
        tokens = f.read().strip().split()
    assert len(tokens) == len(cases), (
        f"Expected {len(cases)} generated results, found {len(tokens)}."
    )
    try:
        actual = [float(token) for token in tokens]
    except ValueError:
        pytest.fail("Generated output contains non-numeric data.")

    expected = [0.0 if x - y == 0.0 else 1.0 / (x - y) for x, y in cases]
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert math.isfinite(got), f"Generated result {i + 1} is not finite: {got}."
        assert math.isclose(got, want, rel_tol=1e-6, abs_tol=1e-6), (
            f"Generated result {i + 1} is {got}, expected {want}."
        )


def test_binary_and_fixed_source_on_generated_inputs():
    source = "/home/user/calc_engine.cpp"
    assert os.path.isfile(source), f"Source file {source} is missing."

    # Dyadic differences are represented exactly. Values include exact-zero and
    # small nonzero differences, ensuring only exact equality is treated as zero.
    differences = [0.0, 0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5,
                   0.25, -0.25, 0.015625, -0.015625]
    cases = []
    for diff in differences:
        x = float(secrets.randbelow(2001) - 1000)
        y = x - diff
        cases.append((x, y))
    secrets.SystemRandom().shuffle(cases)

    # Exercise the submitted final artifact, rather than trusting stale output.
    run_and_check("/home/user/calc_engine", cases)

    # Independently compile and exercise the submitted source to verify the fix
    # is present there as required by the ticket.
    rebuilt = "/tmp/calc_engine_rebuilt"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O0", "-g", source, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"The submitted source does not compile: {compile_result.stderr}"
    )
    run_and_check(rebuilt, cases)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
