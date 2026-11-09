#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/project"
EXE = os.path.join(PROJECT, "spectral_analyzer")
SOURCE = os.path.join(PROJECT, "spectral_analyzer.cpp")
DATASET = os.path.join(PROJECT, "dataset.txt")
LOG = os.path.join(PROJECT, "results.log")
BUILT_FROM_SOURCE = "/tmp/spectral_analyzer_from_source"


def test_executable_exists():
    assert os.path.isfile(EXE), f"Executable {EXE} does not exist. Did you compile the C++ code?"
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."


def test_results_log_exists():
    assert os.path.isfile(LOG), f"Results log {LOG} does not exist. Did you pipe the output?"


def test_results_log_content():
    if not os.path.isfile(LOG):
        pytest.fail(f"Results log {LOG} does not exist.")

    with open(LOG, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Mean: 1000000.3000",
        "Variance: 0.0200",
        "Calibration Coefficient: 1.1414"
    ]
    actual_lines = [line.strip() for line in content.split("\n") if line.strip()]

    assert len(actual_lines) == 3, f"Expected 3 lines of output, got {len(actual_lines)}. Content:\n{content}"
    assert actual_lines[0] == expected_lines[0], f"Expected first line to be '{expected_lines[0]}', got '{actual_lines[0]}'"
    assert actual_lines[1] == expected_lines[1], f"Expected second line to be '{expected_lines[1]}', got '{actual_lines[1]}'"
    assert actual_lines[2] == expected_lines[2], f"Expected third line to be '{expected_lines[2]}', got '{actual_lines[2]}'"


def run_program(executable, dataset):
    completed = subprocess.run(
        [executable, dataset],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"{executable} failed with exit code {completed.returncode}: {completed.stderr}"
    )
    return completed.stdout


def parse_output(output):
    pattern = re.compile(
        r"\AMean: (-?\d+\.\d{4})\n"
        r"Variance: (-?\d+\.\d{4})\n"
        r"Calibration Coefficient: (-?\d+\.\d{4})\n?\Z"
    )
    match = pattern.fullmatch(output)
    assert match, f"Output does not have exactly the required three-line, four-decimal format:\n{output}"
    return tuple(float(value) for value in match.groups())


def expected_values(values):
    mean = math.fsum(values) / len(values)
    variance = math.fsum((value - mean) ** 2 for value in values) / len(values)
    coefficient = math.sqrt(variance) + mean / 1000000.0
    return mean, variance, coefficient


def assert_correct_output(executable, values):
    fd, path = tempfile.mkstemp(prefix="variance_dataset_", suffix=".txt")
    try:
        with os.fdopen(fd, "w") as dataset:
            dataset.write("\n".join(repr(value) for value in values) + "\n")
        actual = parse_output(run_program(executable, path))
        expected = expected_values(values)
        for label, got, wanted in zip(("mean", "variance", "coefficient"), actual, expected):
            assert abs(got - wanted) <= 0.000051, (
                f"Incorrect {label} for dataset {values}: got {got:.4f}, expected {wanted:.4f}"
            )
    finally:
        os.unlink(path)


def test_results_were_produced_by_fixed_executable():
    with open(LOG, "r") as f:
        logged = f.read()
    assert run_program(EXE, DATASET).strip() == logged.strip(), (
        "results.log is not the output produced by the submitted executable on dataset.txt"
    )


def test_source_compiles_with_required_options():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    completed = subprocess.run(
        ["g++", "-O3", "-std=c++11", "-o", BUILT_FROM_SOURCE, SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"Submitted source does not compile as required:\n{completed.stderr}"


@pytest.mark.parametrize("values", [
    [1000000000000.0 + x for x in (-10.0, -3.0, 0.0, 4.0, 9.0)],
    [100000000000000.0 + x for x in (-32.0, -8.0, 0.0, 8.0, 32.0)],
])
def test_stable_variance_on_additional_datasets(values):
    assert os.path.isfile(BUILT_FROM_SOURCE), "Verifier could not build the submitted source."
    assert_correct_output(BUILT_FROM_SOURCE, values)
    assert_correct_output(EXE, values)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
