#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import struct
import subprocess

import pytest

SOURCE = "/home/user/processor.c"
EXECUTABLE = "/home/user/processor"
RESULT = "/home/user/result.txt"
OUTPUT_RE = re.compile(r"Sum: (-?\d+\.\d{5})\nVariance: (-?\d+\.\d{5})\n?\Z")


def float32(value):
    return struct.unpack("=f", struct.pack("=f", value))[0]


STORED_VALUE = float32(0.1)


def run_and_validate(path, elements, threads, timeout=30):
    proc = subprocess.run(
        [path, str(elements), str(threads)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert proc.returncode == 0, (
        f"{path} exited with {proc.returncode} for {elements} elements and "
        f"{threads} threads. stderr:\n{proc.stderr}"
    )

    match = OUTPUT_RE.fullmatch(proc.stdout)
    assert match, (
        "Output must consist exactly of the required two printf lines with five "
        f"decimal places; got:\n{proc.stdout!r}"
    )

    actual_sum = float(match.group(1))
    actual_variance = float(match.group(2))
    expected_sum = elements * STORED_VALUE

    # This permits ordinary double summation and final five-decimal rounding, but
    # is far tighter than the error from float accumulation or lost updates.
    sum_tolerance = max(0.00002, elements * 2e-10)
    assert abs(actual_sum - expected_sum) <= sum_tolerance, (
        f"Incorrect sum for {elements} stored 0.1f values: got {actual_sum}, "
        f"expected approximately {expected_sum}"
    )
    assert abs(actual_variance) <= 0.00001, (
        f"Identical input values must have zero variance, got {actual_variance}"
    )
    return proc.stdout


def test_processor_executable_exists_and_is_binary():
    assert os.path.isfile(EXECUTABLE), (
        f"Executable {EXECUTABLE} is missing. Did you compile the code?"
    )
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            f"{EXECUTABLE} is not the compiled executable requested by the task."
        )


def test_processor_c_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()

    assert "double" in content, (
        "The code does not seem to use 'double' precision as required."
    )
    assert "end = num_elements + 1000;" not in content, (
        "The out-of-bounds bug is still present in the code."
    )


def test_submitted_executable_and_saved_result():
    first = run_and_validate(EXECUTABLE, 10000000, 4)
    second = run_and_validate(EXECUTABLE, 10000000, 4)
    assert second == first, "Program output is not deterministic across identical runs."

    assert os.path.isfile(RESULT), (
        f"File {RESULT} is missing. Did you save the output?"
    )
    with open(RESULT, "r") as f:
        saved = f.read()
    assert saved == first, (
        f"{RESULT} must contain the exact standard output produced by running "
        f"{EXECUTABLE} with 10000000 elements and 4 threads."
    )


def test_source_builds_and_handles_derived_inputs(tmp_path):
    rebuilt = tmp_path / "processor"
    compile_proc = subprocess.run(
        ["gcc", "-O2", "-pthread", SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_proc.returncode == 0, (
        f"The submitted source does not compile with the required command:\n"
        f"{compile_proc.stderr}"
    )

    # Exercise non-divisible work sizes selected by the verifier as well as the
    # required invocation, so fabricated output and incomplete chunk handling fail.
    rng = random.SystemRandom()
    cases = [(10000000, 4)]
    for _ in range(2):
        threads = rng.randint(3, 9)
        elements = rng.randint(50000, 150000)
        if elements % threads == 0:
            elements += 1
        cases.append((elements, threads))

    for elements, threads in cases:
        run_and_validate(str(rebuilt), elements, threads)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
