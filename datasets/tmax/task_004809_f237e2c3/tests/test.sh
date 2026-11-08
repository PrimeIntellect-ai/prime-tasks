#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from decimal import Decimal, getcontext

import pytest

PROJECT = "/home/user/project"
SCRIPT = os.path.join(PROJECT, "build_model.sh")
SENSOR = os.path.join(PROJECT, "sensor_data.txt")
OUTPUT = os.path.join(PROJECT, "final_output.txt")
TRACE = os.path.join(PROJECT, "trace.log")

ORIGINAL_DATA = """12.5
15.0
ERR_TIMEOUT
18.5
CORRUPT_DATA
14.0
"""


def run_script(data):
    with open(SENSOR, "w") as f:
        f.write(data)

    for path in (OUTPUT, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [SCRIPT],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"build_model.sh exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def read_nonempty_trace_lines():
    assert os.path.isfile(TRACE), f"{TRACE} is missing."
    with open(TRACE, "r") as f:
        return [line.strip() for line in f if line.strip()]


@pytest.fixture(scope="module", autouse=True)
def execute_original_script():
    with open(SENSOR, "rb") as f:
        saved_sensor = f.read()
    try:
        run_script(ORIGINAL_DATA)
        yield
    finally:
        with open(SENSOR, "wb") as f:
            f.write(saved_sensor)


def test_final_output_exists_and_correct():
    output_path = "/home/user/project/final_output.txt"
    assert os.path.isfile(output_path), f"{output_path} is missing."

    with open(output_path, "r") as f:
        content = f.read().strip()

    assert content == "14.9927", f"Expected final output to be exactly '14.9927', but got '{content}'."


def test_trace_log_exists_and_correct():
    trace_path = "/home/user/project/trace.log"
    assert os.path.isfile(trace_path), f"{trace_path} is missing."

    with open(trace_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Iteration 1: 7.5000",
        "Iteration 2: 11.2500",
        "Iteration 3: 13.1250",
        "Iteration 4: 14.0625",
        "Iteration 5: 14.5312",
        "Iteration 6: 14.7656",
        "Iteration 7: 14.8828",
        "Iteration 8: 14.9414",
        "Iteration 9: 14.9707",
        "Iteration 10: 14.9854",
        "Iteration 11: 14.9927"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} trace lines, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}: expected '{expected}', got '{actual}'."


def test_script_is_executable():
    script_path = "/home/user/project/build_model.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def expected_for_average(average):
    getcontext().prec = 50
    baseline = Decimal("0")
    expected_trace = []
    iteration = 1
    while True:
        old = baseline
        baseline = (baseline + average) / Decimal("2")
        expected_trace.append(f"Iteration {iteration}: {baseline:.4f}")
        if abs(baseline - old) < Decimal("0.01"):
            break
        iteration += 1
        assert iteration <= 100
    return f"{baseline:.4f}", expected_trace


def test_script_recomputes_from_unseen_mixed_input():
    targets = [
        Decimal(8 + secrets.randbelow(29)),
        Decimal(-(5 + secrets.randbelow(20))),
    ]

    for target in targets:
        valid_values = [
            target - Decimal("2.50"),
            target + Decimal("1.25"),
            target + Decimal("3.75"),
            target - Decimal("2.50"),
        ]
        data = "\n".join([
            str(valid_values[0]),
            "ERR_TIMEOUT",
            str(valid_values[1]),
            "12oops",
            str(valid_values[2]),
            "CORRUPT_DATA",
            str(valid_values[3]),
            "",
        ]) + "\n"

        run_script(data)
        expected_output, expected_trace = expected_for_average(target)

        assert os.path.isfile(OUTPUT), f"{OUTPUT} is missing after executing the script."
        with open(OUTPUT, "r") as f:
            actual_output = f.read().strip()
        assert actual_output == expected_output, (
            f"For generated valid readings {valid_values}, expected final output "
            f"{expected_output!r}, got {actual_output!r}."
        )

        actual_trace = read_nonempty_trace_lines()
        assert actual_trace == expected_trace, (
            f"Trace did not contain every correctly formatted iteration for "
            f"generated valid readings {valid_values}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
