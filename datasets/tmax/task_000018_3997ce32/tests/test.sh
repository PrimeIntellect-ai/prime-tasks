#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

SCRIPT_PATH = "/home/user/evaluate_order.sh"
SIGNAL_PATH = "/home/user/signal.txt"
RESULT_PATH = "/home/user/result.txt"
ORIGINAL_SIGNAL = [
    "10000000000000000.0",
    "-10000000000000000.0",
    "1.0",
    "2.0",
]


def expected_difference(lines):
    values = [float(line) for line in lines]

    sequential = 0.0
    for value in values:
        sequential += value

    ordered = 0.0
    for value in sorted(values, key=abs):
        ordered += value

    return abs(sequential - ordered)


def run_and_read(lines):
    with open(SIGNAL_PATH, "w") as signal_file:
        signal_file.write("\n".join(lines) + "\n")

    if os.path.lexists(RESULT_PATH):
        os.remove(RESULT_PATH)

    completed = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"The script exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), (
        f"The result file {RESULT_PATH} does not exist after running the script."
    )

    with open(RESULT_PATH, "r") as result_file:
        content = result_file.read().strip()

    try:
        difference = float(content)
    except ValueError:
        assert False, (
            f"The content of {RESULT_PATH} is not a valid floating-point number. "
            f"Got: {content}"
        )

    assert math.isfinite(difference), f"The reported difference is not finite: {content}"
    return difference


def test_script_exists_and_executable():
    """Check if the evaluation script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."


def test_result_file_content():
    """Run the script and check the result for the provided signal."""
    difference = run_and_read(ORIGINAL_SIGNAL)
    expected = expected_difference(ORIGINAL_SIGNAL)
    assert abs(difference - expected) < 1e-6, (
        f"Expected the absolute difference to be {expected}, but got {difference}."
    )


def test_script_computes_results_for_other_inputs():
    """Ensure the executable computes the result rather than relying on a stale file."""
    cases = [
        ["10000000000000000.0", "1.0", "1.0", "-10000000000000000.0"],
        ["4.0", "-1.0", "2.5"],
    ]
    try:
        for lines in cases:
            difference = run_and_read(lines)
            expected = expected_difference(lines)
            assert abs(difference - expected) < 1e-6, (
                f"For input {lines}, expected {expected}, but got {difference}."
            )
    finally:
        with open(SIGNAL_PATH, "w") as signal_file:
            signal_file.write("\n".join(ORIGINAL_SIGNAL) + "\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
