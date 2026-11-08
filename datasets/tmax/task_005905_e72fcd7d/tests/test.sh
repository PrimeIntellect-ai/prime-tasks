#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile

import pytest

SRC_PATH = "/home/user/src/preprocess.c"
BIN_PATH = "/home/user/bin/preprocess"


def expected_output(values):
    mean = sum(values) / len(values)
    variance = sum((x - mean) ** 2 for x in values) / len(values)
    std_dev = math.sqrt(variance)
    if std_dev == 0:
        normalized = [0.0 for _ in values]
    else:
        normalized = [(x - mean) / std_dev for x in values]
    return "".join(f"{z:.6f}\n" for z in normalized)


def run_case(program, value_strings):
    values = [float(value) for value in value_strings]
    with tempfile.TemporaryDirectory(prefix="preprocess_verify_") as directory:
        input_path = os.path.join(directory, "input.txt")
        output_path = os.path.join(directory, "output.txt")
        with open(input_path, "w", encoding="utf-8") as handle:
            handle.write("".join(f"{value}\n" for value in value_strings))

        result = subprocess.run(
            [program, input_path, output_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"{program} exited with status {result.returncode}. "
            f"stderr: {result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(output_path), f"{program} did not create its output file."
        with open(output_path, "r", encoding="utf-8") as handle:
            actual = handle.read()
        assert actual == expected_output(values), (
            f"Incorrect normalization from {program}.\n"
            f"Expected:\n{expected_output(values)}\nGot:\n{actual}"
        )


def generated_cases():
    rng = secrets.SystemRandom()
    mixed = [f"{rng.randint(-500000, 500000) / 1000:.3f}" for _ in range(47)]
    if len(set(mixed)) == 1:
        mixed[-1] = "1.375"

    large = [f"{rng.randint(-100000, 100000) / 100:.2f}" for _ in range(10000)]
    if len(set(large)) == 1:
        large[-1] = "2.25"

    return [
        ["10.0", "20.0", "30.0", "40.0", "50.0"],
        ["-7.25"] * 13,
        ["-12.5", "0", "3.25", "8.75", "101.5", "-44.0"],
        mixed,
        large,
    ]


@pytest.fixture(scope="session")
def rebuilt_program():
    directory = tempfile.mkdtemp(prefix="preprocess_build_")
    output_path = os.path.join(directory, "preprocess_from_source")
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SRC_PATH, "-o", output_path, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        "preprocess.c did not compile successfully.\n"
        + result.stderr.decode(errors="replace")
    )
    return output_path


def test_preprocess_c_exists():
    """Verify that the C source code exists."""
    assert os.path.isfile(SRC_PATH), (
        f"Source file {SRC_PATH} is missing. You must write the C program."
    )


def test_preprocess_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    assert os.path.isfile(BIN_PATH), (
        f"Executable {BIN_PATH} is missing. You must compile the program."
    )
    assert os.access(BIN_PATH, os.X_OK), f"File {BIN_PATH} is not executable."
    with open(BIN_PATH, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", (
            f"{BIN_PATH} is not a compiled ELF executable."
        )


def test_regression_script_passes():
    result = subprocess.run(
        ["/home/user/test/regression_test.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        "Regression test failed.\n"
        + result.stdout.decode(errors="replace")
        + result.stderr.decode(errors="replace")
    )


def test_program_behavior(rebuilt_program):
    for case in generated_cases():
        run_case(BIN_PATH, case)
        run_case(rebuilt_program, case)


def test_requires_exactly_two_arguments(rebuilt_program):
    for program in (BIN_PATH, rebuilt_program):
        no_args = subprocess.run(
            [program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
        )
        assert no_args.returncode != 0, f"{program} accepted zero arguments."

        with tempfile.TemporaryDirectory(prefix="preprocess_args_") as directory:
            input_path = os.path.join(directory, "input.txt")
            output_path = os.path.join(directory, "output.txt")
            with open(input_path, "w", encoding="utf-8") as handle:
                handle.write("1\n2\n")
            extra_args = subprocess.run(
                [program, input_path, output_path, "extra"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert extra_args.returncode != 0, f"{program} accepted an extra argument."


def test_prepared_data_correctness():
    """Verify that the prepared data file exists and contains the correct Z-score normalized values."""
    raw_data_path = "/home/user/raw_training_data.txt"
    prepared_data_path = "/home/user/prepared_data.txt"

    assert os.path.isfile(raw_data_path), f"Raw data file {raw_data_path} is missing."
    assert os.path.isfile(prepared_data_path), f"Prepared data file {prepared_data_path} is missing. Did you run the program on the raw data?"

    with open(raw_data_path, 'r') as f:
        raw_lines = [line.strip() for line in f if line.strip()]

    raw_values = []
    for line in raw_lines:
        try:
            raw_values.append(float(line))
        except ValueError:
            pytest.fail(f"Could not parse '{line}' as a float in {raw_data_path}.")

    n = len(raw_values)
    assert n > 0, "Raw data file is empty."

    mean = sum(raw_values) / n
    variance = sum((x - mean) ** 2 for x in raw_values) / n
    std_dev = math.sqrt(variance)

    expected_z_scores = []
    for x in raw_values:
        if std_dev == 0:
            expected_z_scores.append(0.0)
        else:
            expected_z_scores.append((x - mean) / std_dev)

    expected_lines = [f"{z:.6f}" for z in expected_z_scores]

    with open(prepared_data_path, 'r') as f:
        prepared_lines = [line.strip() for line in f if line.strip()]

    assert len(prepared_lines) == len(expected_lines), (
        f"Prepared data has {len(prepared_lines)} lines, but expected {len(expected_lines)}."
    )

    for i, (prep, exp) in enumerate(zip(prepared_lines, expected_lines)):
        assert prep == exp, (
            f"Line {i+1} mismatch in {prepared_data_path}: expected {exp}, got {prep}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
