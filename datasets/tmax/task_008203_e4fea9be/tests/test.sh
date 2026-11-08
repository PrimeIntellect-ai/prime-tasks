#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import ctypes.util
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

BASE = "/home/user/nightly"
SOURCE = os.path.join(BASE, "process.c")
PROCESS = os.path.join(BASE, "process")
SOLUTION = os.path.join(BASE, "solution.txt")
INPUTS = os.path.join(BASE, "inputs.txt")

ORIGINAL_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <value>\n", argv[0]);
        return 1;
    }

    float x = atof(argv[1]);

    // Calculate 1 / (sqrt(x^2 + 1) - 1)
    // For very small x, x^2 + 1 evaluates to exactly 1.0f in 32-bit float,
    // leading to sqrtf(1.0f) - 1.0f = 0.0f, and a division by zero crash (SIGFPE).
    float denominator = sqrtf(x * x + 1.0f) - 1.0f;
    float result = 1.0f / denominator;

    // Simulate crash on division by zero (some systems print Inf instead of SIGFPE for floats, 
    // so we force a crash if denominator is 0 to ensure the behavior matches the description)
    if (denominator == 0.0f) {
        int *p = NULL;
        *p = 0; // Force segfault/core dump
    }

    printf("%.2f\n", result);

    return 0;
}
'''

EXPECTED_INPUTS = ["2.5000", "1.1000", "0.0001", "5.4000"]
OUTPUT_PATTERN = re.compile(r"^-?[0-9]+\.[0-9]{2}$")
SOLUTION_PATTERN = re.compile(r"^20000000[01]\.[0-9]{2}$")


def run_program(path, value):
    return subprocess.run(
        [path, value], cwd=BASE, text=True, capture_output=True, timeout=3
    )


def read_inputs():
    with open(INPUTS, "r") as f:
        return [line.strip() for line in f if line.strip()]


def original_float_denominator(value):
    libm_name = ctypes.util.find_library("m")
    assert libm_name, "Unable to locate libm"
    libm = ctypes.CDLL(libm_name)
    libm.sqrtf.argtypes = [ctypes.c_float]
    libm.sqrtf.restype = ctypes.c_float

    x = ctypes.c_float(float(value)).value
    squared = ctypes.c_float(x * x).value
    summed = ctypes.c_float(squared + 1.0).value
    root = libm.sqrtf(ctypes.c_float(summed))
    return ctypes.c_float(root - 1.0).value


def crashing_input():
    values = read_inputs()
    crashing = [v for v in values if original_float_denominator(v) == 0.0]
    assert len(crashing) == 1, f"Expected exactly one numerically unstable input, found {crashing}"
    return crashing[0]


def assert_correct_calculation(path, value):
    completed = run_program(path, value)
    assert completed.returncode == 0, (
        f"{path} failed for input {value}: return code {completed.returncode}, "
        f"stderr={completed.stderr!r}"
    )
    output = completed.stdout.strip()
    assert OUTPUT_PATTERN.fullmatch(output), (
        f"{path} did not print one finite value to two decimal places for {value}: {completed.stdout!r}"
    )

    x = float(value)
    expected = (math.sqrt(1.0 + x * x) + 1.0) / (x * x)
    actual = float(output)
    # This permits both a direct higher-precision calculation and an algebraically
    # stabilized calculation while rejecting the original cancellation failure.
    assert math.isclose(actual, expected, rel_tol=2e-6, abs_tol=0.02), (
        f"Incorrect result for {value}: got {actual}, expected approximately {expected}"
    )
    return output


@pytest.fixture(scope="session")
def rebuilt_process():
    fd, path = tempfile.mkstemp(prefix="verifier_process_", dir=BASE)
    os.close(fd)
    os.unlink(path)
    completed = subprocess.run(
        ["gcc", "-o", path, "process.c", "-lm"],
        cwd=BASE, text=True, capture_output=True, timeout=15
    )
    assert completed.returncode == 0, f"process.c does not compile: {completed.stderr}"
    yield path
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def test_solution_file_exists():
    """Check if solution.txt exists."""
    assert os.path.isfile(SOLUTION), "The file /home/user/nightly/solution.txt does not exist."


def test_solution_content():
    """Check if solution.txt contains the correct calculated value."""
    with open(SOLUTION, "r") as f:
        content = f.read().strip()

    # Retain the original accepted range while later tests verify the value by execution.
    assert SOLUTION_PATTERN.match(content), (
        f"The content of solution.txt ({content!r}) does not match the expected format or value."
    )


def test_process_executable_exists():
    """Check if the recompiled process executable exists."""
    assert os.path.isfile(PROCESS), "The recompiled executable /home/user/nightly/process does not exist."
    assert os.access(PROCESS, os.X_OK), "The file /home/user/nightly/process is not executable."


def test_inputs_are_intact_and_crashing_value_is_derived():
    assert os.path.isfile(INPUTS), "inputs.txt is missing"
    assert read_inputs() == EXPECTED_INPUTS, "inputs.txt was modified"
    assert crashing_input() == "0.0001"


def test_source_was_modified_and_compiles(rebuilt_process):
    assert os.path.isfile(SOURCE), "process.c is missing"
    with open(SOURCE, "r") as f:
        submitted = f.read()
    assert submitted.strip() != ORIGINAL_SOURCE.strip(), "process.c still contains the original crashing implementation"
    assert os.path.isfile(rebuilt_process) and os.access(rebuilt_process, os.X_OK)


def test_executable_is_the_recompiled_source(rebuilt_process):
    with open(PROCESS, "rb") as f:
        submitted_binary = f.read()
    with open(rebuilt_process, "rb") as f:
        rebuilt_binary = f.read()
    assert submitted_binary == rebuilt_binary, (
        "The process executable is not the binary produced by compiling the submitted process.c"
    )


def test_solution_is_exact_output_for_crashing_input(rebuilt_process):
    value = crashing_input()
    submitted_output = assert_correct_calculation(PROCESS, value)
    rebuilt_output = assert_correct_calculation(rebuilt_process, value)
    assert submitted_output == rebuilt_output
    with open(SOLUTION, "r") as f:
        saved = f.read().strip()
    assert saved == submitted_output, (
        f"solution.txt contains {saved!r}, but the fixed program prints {submitted_output!r} for {value}"
    )


def test_precision_fix_handles_additional_small_values(rebuilt_process):
    rng = random.SystemRandom()
    probes = ["0.0000500", "0.0002000"]
    probes.extend(f"{rng.randint(300, 2200) / 10000000:.7f}" for _ in range(6))
    for value in probes:
        submitted_output = assert_correct_calculation(PROCESS, value)
        rebuilt_output = assert_correct_calculation(rebuilt_process, value)
        assert submitted_output == rebuilt_output
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
