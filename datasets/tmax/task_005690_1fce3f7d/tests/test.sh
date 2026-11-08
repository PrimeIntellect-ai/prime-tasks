#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

BASE = "/home/user/ticket_882"
SOURCE = os.path.join(BASE, "factorize.c")
EXECUTABLE = os.path.join(BASE, "factorize")


def expected_factors(n):
    factors = []
    remaining = n
    divisor = 2
    while divisor * divisor <= remaining:
        while remaining % divisor == 0:
            factors.append(divisor)
            remaining //= divisor
        divisor += 1
    if remaining > 1:
        factors.append(remaining)
    return factors


def run_and_check(executable, n):
    try:
        result = subprocess.run(
            [executable, str(n)], capture_output=True, text=True, timeout=2
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"The factorize program timed out for input {n}.")

    assert result.returncode == 0, (
        f"The factorize program failed for input {n}. Stderr: {result.stderr}"
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f"Unexpected output for {n}: {result.stdout!r}"
    match = re.fullmatch(r"(\d+):\s*(\d+(?:\s+\d+)*)", lines[0])
    assert match, f"Malformed factorization output for {n}: {result.stdout!r}"
    assert int(match.group(1)) == n, f"Output was labeled with the wrong input for {n}."
    actual = [int(value) for value in match.group(2).split()]
    assert actual == expected_factors(n), (
        f"Incorrect factors for {n}: expected {expected_factors(n)}, got {actual}."
    )


def test_failing_input_txt():
    file_path = os.path.join(BASE, "failing_input.txt")
    assert os.path.exists(file_path), f"File {file_path} does not exist."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "256", (
        f"Expected failing_input.txt to contain '256', but found '{content}'."
    )


def test_factorize_c_fixed():
    assert os.path.exists(SOURCE), f"Source code file {SOURCE} does not exist."

    with open(SOURCE, "r") as f:
        content = f.read()

    assert "factors[8]" not in content.replace(" ", ""), (
        "The source code still contains the buggy buffer size 8."
    )
    assert "assert(count<8)" not in content.replace(" ", ""), (
        "The source code still contains the buggy assertion for size 8."
    )


def test_factorize_executable():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"Path {EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "factorize is not a compiled ELF executable."

    try:
        result = subprocess.run(
            [EXECUTABLE, "256"], capture_output=True, text=True, timeout=2
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The factorize program timed out when running with input 256.")
    assert result.returncode == 0, (
        f"The factorize program failed with input 256. Stderr: {result.stderr}"
    )
    assert "256: 2 2 2 2 2 2 2 2" in result.stdout, (
        "The factorize program did not output the correct factors for 256."
    )

    try:
        result_512 = subprocess.run(
            [EXECUTABLE, "512"], capture_output=True, text=True, timeout=2
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The factorize program timed out when running with input 512.")
    assert result_512.returncode == 0, (
        f"The factorize program failed with input 512. Stderr: {result_512.stderr}"
    )
    assert "512: 2 2 2 2 2 2 2 2 2" in result_512.stdout, (
        "The factorize program did not output the correct factors for 512."
    )


def test_submitted_and_rebuilt_programs_across_range():
    build_dir = tempfile.mkdtemp(prefix="factorize_verify_")
    rebuilt = os.path.join(build_dir, "factorize")
    compile_result = subprocess.run(
        ["/usr/bin/gcc", "-o", rebuilt, SOURCE],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert compile_result.returncode == 0, (
        f"factorize.c does not compile with gcc: {compile_result.stderr}"
    )

    cases = {
        100, 101, 128, 255, 256, 257, 360, 499, 500, 512,
        729, 1024, 2048, 4096, 6561, 7776, 8192, 9999, 10000,
    }
    rng = secrets.SystemRandom()
    while len(cases) < 100:
        cases.add(rng.randint(100, 10000))

    for executable in (EXECUTABLE, rebuilt):
        for n in sorted(cases):
            run_and_check(executable, n)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
