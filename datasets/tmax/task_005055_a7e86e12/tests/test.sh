#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import time

PROJECT = "/home/user/math_proj"
SCRIPT = os.path.join(PROJECT, "run_analysis.sh")
RESULT = os.path.join(PROJECT, "result.txt")
LIBRARY = os.path.join(PROJECT, "lib", "math_v2.sh")


def reference_collatz(n):
    steps = 0
    while n != 1:
        if n % 2 == 0:
            n //= 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps


def expected_result():
    max_len = 0
    max_num = 0
    for n in range(1, 501):
        length = reference_collatz(n)
        if length > max_len:
            max_len = length
            max_num = n
    return f"Max Length: {max_len}, Number: {max_num}"


def test_00_run_analysis_completes_under_two_seconds():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"File {SCRIPT} is not executable."

    if os.path.exists(RESULT):
        os.remove(RESULT)

    start = time.monotonic()
    try:
        completed = subprocess.run(
            ["./run_analysis.sh"],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2.0,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("run_analysis.sh did not complete in under 2 seconds")
    elapsed = time.monotonic() - start

    assert completed.returncode == 0, (
        f"run_analysis.sh exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert elapsed < 2.0, f"run_analysis.sh took {elapsed:.3f} seconds; it must take under 2 seconds"
    assert os.path.isfile(RESULT), "run_analysis.sh did not create result.txt"


def test_result_file_exists_and_correct():
    result_path = "/home/user/math_proj/result.txt"
    assert os.path.isfile(result_path), f"File {result_path} is missing. Did you run the script?"

    with open(result_path, "r") as f:
        content = f.read().strip()

    expected = "Max Length: 143, Number: 327"
    assert expected_result() == expected
    assert content == expected, f"Expected '{expected}' in {result_path}, but got '{content}'"


def test_run_analysis_fixed():
    script_path = "/home/user/math_proj/run_analysis.sh"
    assert os.path.isfile(script_path), f"File {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert "math_v1.sh" not in content, "run_analysis.sh should no longer source the broken math_v1.sh library."
    assert "math_v2.sh" in content, "run_analysis.sh must still source math_v2.sh."


def test_math_v2_optimized():
    lib_path = "/home/user/math_proj/lib/math_v2.sh"
    assert os.path.isfile(lib_path), f"File {lib_path} is missing."

    with open(lib_path, "r") as f:
        content = f.read()

    assert "expr " not in content, "The collatz function in math_v2.sh is still using the slow 'expr' command. Use Bash native arithmetic (e.g., $((...)))."
    assert "collatz" in content, "The collatz function must still be defined in math_v2.sh."


def test_collatz_function_behavior_with_builtins_only():
    expected = [reference_collatz(n) for n in range(1, 501)]
    command = 'source "$1" && for n in {1..500}; do collatz "$n"; done'
    env = os.environ.copy()
    env["PATH"] = "/nonexistent"

    try:
        completed = subprocess.run(
            ["/bin/bash", "-c", command, "bash", LIBRARY],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5.0,
            env=env,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("The collatz function is too slow or did not terminate")

    assert completed.returncode == 0, (
        f"math_v2.sh could not be sourced or collatz failed without external commands. "
        f"stderr: {completed.stderr}"
    )
    try:
        actual = [int(line.strip()) for line in completed.stdout.splitlines()]
    except ValueError:
        raise AssertionError(f"collatz produced non-integer output: {completed.stdout!r}")

    assert actual == expected, "collatz returned incorrect sequence lengths for inputs 1 through 500"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
