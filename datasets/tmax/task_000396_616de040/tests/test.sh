#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

QA_ENV_DIR = "/home/user/qa_env"
C_FILE = os.path.join(QA_ENV_DIR, "rate_check.c")
EXECUTABLE = os.path.join(QA_ENV_DIR, "rate_check")
VIOLATIONS_LOG = os.path.join(QA_ENV_DIR, "violations.log")
DIFF_LOG = os.path.join(QA_ENV_DIR, "diff.log")


def test_c_file_exists():
    assert os.path.isfile(C_FILE), f"C source file {C_FILE} does not exist."


def test_executable_exists_and_executable():
    assert os.path.isfile(EXECUTABLE), f"Executable file {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_violations_log_content():
    assert os.path.isfile(VIOLATIONS_LOG), f"Violations log {VIOLATIONS_LOG} does not exist."
    with open(VIOLATIONS_LOG, "r") as f:
        content = f.read().strip().split()

    expected_content = ["11", "14", "15", "20"]
    assert content == expected_content, f"Content of {VIOLATIONS_LOG} does not match expected output. Got: {content}"


def test_diff_log_is_empty():
    assert os.path.isfile(DIFF_LOG), f"Diff log {DIFF_LOG} does not exist."
    assert os.path.getsize(DIFF_LOG) == 0, f"Diff log {DIFF_LOG} is not empty, indicating a mismatch in diff."


def test_rate_check_logic(tmp_path):
    """Retain the original integration check against the submitted executable."""
    assert os.path.isfile(EXECUTABLE), f"Executable file {EXECUTABLE} does not exist."

    custom_input = "0x00000004\n0x00000001\n0x00000010\n0x00000002\n0x00000003\n"

    try:
        result = subprocess.run(
            [EXECUTABLE],
            input=custom_input,
            text=True,
            capture_output=True,
            timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Execution of rate_check timed out.")
    except Exception as e:
        pytest.fail(f"Failed to execute rate_check: {e}")

    output = result.stdout.strip().split()
    assert output == ["4"], f"Program logic failed on custom input. Expected ['4'], got {output}"


def expected_output(values):
    ordered = sorted(values)
    violations = [ordered[i] for i in range(3, len(ordered))
                  if ordered[i] - ordered[i - 3] <= 10]
    return "".join(f"{value}\n" for value in violations)


def run_case(program, values, rng):
    supplied = list(values)
    rng.shuffle(supplied)
    input_text = "".join(f"0x{value:08X}\n" for value in supplied)
    try:
        result = subprocess.run(
            [program], input=input_text, text=True, capture_output=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {program} timed out")
    except Exception as exc:
        pytest.fail(f"Failed to execute {program}: {exc}")

    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}; stderr: {result.stderr!r}"
    )
    expected = expected_output(values)
    assert result.stdout == expected, (
        f"Incorrect output for input {input_text!r}. "
        f"Expected {expected!r}, got {result.stdout!r}"
    )


def test_source_compiles_and_both_binaries_handle_derived_cases(tmp_path):
    rebuilt = tmp_path / "rate_check_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", C_FILE, "-o", str(rebuilt)],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert compile_result.returncode == 0, (
        f"rate_check.c did not compile successfully: {compile_result.stderr}"
    )

    rng = secrets.SystemRandom()
    cases = [
        [],
        [7],
        [9, 1, 20],
        [0, 10, 20, 10, 11, 21, 30],
        [0, 10, 20, 10],
        [42, 42, 42, 42, 42],
        [0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFFF7, 0xFFFFFFF6, 0],
    ]

    # Generate unpredictable valid inputs, including dense windows, duplicates,
    # sparse timestamps, boundary distances, and larger input collections.
    for _ in range(16):
        base = rng.randrange(0, 0xFFFFFFFF - 1000)
        count = rng.randrange(4, 45)
        cases.append([base + rng.randrange(0, 160) for _ in range(count)])

    current = rng.randrange(0, 10000)
    walk = []
    for _ in range(180):
        current += rng.randrange(0, 16)
        walk.append(current)
    cases.append(walk)

    for program in (EXECUTABLE, str(rebuilt)):
        for values in cases:
            run_case(program, values, rng)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
