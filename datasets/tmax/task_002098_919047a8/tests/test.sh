#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

SIM_FILE = "/home/user/src/simulation.c"
LOG_FILE = "/home/user/results.log"
VERIFIED_BINARY = "/tmp/simulation_verified"
EXPECTED_OUTPUT = "Total StdDev Sum: 0.000000"


def run_binary(command, timeout=60):
    if os.path.exists(LOG_FILE):
        os.unlink(LOG_FILE)
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(SIM_FILE), f"Source file {SIM_FILE} is missing."

    build = subprocess.run(
        ["gcc", "-O0", "-g", SIM_FILE, "-o", VERIFIED_BINARY, "-pthread", "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"The corrected source did not compile:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(VERIFIED_BINARY) and os.access(VERIFIED_BINARY, os.X_OK), \
        "Compilation did not produce an executable program."

    first_run = run_binary([VERIFIED_BINARY])
    assert first_run.returncode == 0, \
        f"The compiled program crashed or failed:\n{first_run.stdout}\n{first_run.stderr}"


def test_results_log_exists():
    """Test that the results.log file was created by the compiled program."""
    assert os.path.isfile(LOG_FILE), f"File {LOG_FILE} was not created. The program may not have been run or crashed."


def test_results_log_content():
    """Test that the results.log file contains the correct deterministic output."""
    with open(LOG_FILE, "r") as f:
        content = f.read().strip()

    assert EXPECTED_OUTPUT in content, f"Expected '{EXPECTED_OUTPUT}' in {LOG_FILE}, but got: '{content}'"
    assert content == EXPECTED_OUTPUT, f"Unexpected extra or malformed output in {LOG_FILE}: '{content}'"


def test_source_code_fixes():
    """Retain the original checks for evidence of synchronization fixes."""
    assert os.path.isfile(SIM_FILE), f"Source file {SIM_FILE} is missing."

    with open(SIM_FILE, "r") as f:
        content = f.read()

    assert "pthread_mutex_lock" in content, "The source code does not contain 'pthread_mutex_lock'. The race condition must be fixed using the provided mutex."
    assert "pthread_mutex_unlock" in content, "The source code does not contain 'pthread_mutex_unlock'."


def test_repeated_execution_is_successful_and_deterministic():
    """Execute fresh runs rather than trusting a pre-created results file."""
    outputs = []
    for _ in range(3):
        completed = run_binary([VERIFIED_BINARY])
        assert completed.returncode == 0, \
            f"The compiled program crashed or failed:\n{completed.stdout}\n{completed.stderr}"
        assert os.path.isfile(LOG_FILE), "The executed program did not create results.log."
        with open(LOG_FILE, "r") as f:
            outputs.append(f.read().strip())

    assert outputs == [EXPECTED_OUTPUT] * 3, f"Program output was incorrect or inconsistent: {outputs}"


def test_aggregation_has_no_detectable_data_race():
    """Helgrind verifies that the shared aggregation update is actually synchronized."""
    completed = run_binary([
        "valgrind",
        "--tool=helgrind",
        "--error-exitcode=97",
        "--quiet",
        VERIFIED_BINARY,
    ], timeout=120)

    assert completed.returncode == 0, \
        "The program failed under Helgrind or contains a data race:\n" + completed.stdout + "\n" + completed.stderr
    assert os.path.isfile(LOG_FILE), "The program did not create results.log when executed under Helgrind."
    with open(LOG_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_OUTPUT, f"Helgrind execution produced incorrect output: '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
