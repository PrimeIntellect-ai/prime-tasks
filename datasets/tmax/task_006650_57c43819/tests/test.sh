#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from decimal import Decimal, localcontext

import pytest

EXECUTABLE = "/home/user/analytics"
SOURCE = "/home/user/analytics.cpp"
OUTPUT = "/home/user/variance_out.txt"
DATASET = "/home/user/query_results.txt"
REBUILT = "/tmp/analytics_rebuilt"
OUTPUT_RE = re.compile(rb"^-?\d+\.\d{6}\n$")


def run_program(path, input_data):
    result = subprocess.run(
        [path],
        input=input_data.encode("ascii"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}; stderr: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert OUTPUT_RE.fullmatch(result.stdout), (
        f"{path} must print only one fixed-point number with exactly six "
        f"decimal places followed by a newline; got {result.stdout!r}"
    )
    return Decimal(result.stdout.decode("ascii").strip())


def sample_variance(values):
    with localcontext() as ctx:
        ctx.prec = 80
        numbers = [Decimal(value) for value in values]
        if len(numbers) <= 1:
            return Decimal(0)
        mean = sum(numbers) / Decimal(len(numbers))
        return sum((number - mean) ** 2 for number in numbers) / Decimal(len(numbers) - 1)


@pytest.fixture(scope="session")
def rebuilt_executable():
    result = subprocess.run(
        ["g++", "-O3", SOURCE, "-o", REBUILT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        "analytics.cpp does not compile with g++ -O3: "
        + result.stderr.decode(errors="replace")
    )
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)
    return REBUILT


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as executable_file:
        assert executable_file.read(4) == b"\x7fELF", (
            f"{EXECUTABLE} is not a compiled ELF executable."
        )


def test_variance_output_correct():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r") as output_file:
        content = output_file.read().strip()
    expected_variance = "8.341675"
    assert content == expected_variance, (
        f"Expected variance output to be '{expected_variance}', but got '{content}'."
    )
    with open(OUTPUT, "rb") as output_file:
        assert output_file.read() == b"8.341675\n", (
            "variance_out.txt must contain exactly the variance followed by one newline."
        )


def test_analytics_cpp_modified():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with open(SOURCE, "r") as source_file:
        content = source_file.read()
    buggy_line = "double variance = (sum_sq - ((sum * sum) / count)) / (count - 1);"
    assert buggy_line not in content, "analytics.cpp still contains the original naive formula."


def test_submitted_program_produces_recorded_dataset_output(rebuilt_executable):
    with open(DATASET, "r") as data_file:
        dataset = data_file.read()
    assert run_program(EXECUTABLE, dataset) == Decimal("8.341675")
    assert run_program(rebuilt_executable, dataset) == Decimal("8.341675")


def test_variance_computation_on_derived_inputs(rebuilt_executable):
    rng = random.Random(937421)

    ordinary = [Decimal(rng.randint(-80, 120)) / Decimal(4) for _ in range(53)]
    ordinary_strings = [format(value, "f") for value in ordinary]

    offsets = [Decimal(rng.randint(-100, 100)) / Decimal(10) for _ in range(137)]
    rng.shuffle(offsets)
    high_mean_strings = [format(Decimal("100000000") + value, "f") for value in offsets]

    cases = [
        (ordinary_strings, Decimal("0.000002")),
        (high_mean_strings, Decimal("0.002")),
        (["100000000.0", "100000001.0", "99999999.0", "100000002.0", "99999998.0"], Decimal("0.002")),
    ]

    for values, tolerance in cases:
        expected = sample_variance(values)
        input_data = "\n".join(values) + "\n"
        for program in (EXECUTABLE, rebuilt_executable):
            actual = run_program(program, input_data)
            assert abs(actual - expected) <= tolerance, (
                f"{program} computed {actual} for a dataset whose sample variance is "
                f"{expected}; this indicates an unstable or incorrect variance calculation."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
