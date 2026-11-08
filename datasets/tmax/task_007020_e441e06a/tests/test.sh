#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import time
import pytest


def max_subarray_sum(arr):
    if not arr:
        return 0
    max_so_far = float('-inf')
    curr_max = 0
    for x in arr:
        curr_max = max(x, curr_max + x)
        max_so_far = max(max_so_far, curr_max)
    return max_so_far


def read_integer_file(path):
    with open(path, "r") as f:
        tokens = f.read().split()
    values = []
    for token in tokens:
        try:
            values.append(int(token))
        except ValueError:
            pytest.fail(f"{path} contains a non-integer token: {token!r}")
    return tokens, values


def test_optimized_cpp_exists():
    assert os.path.exists("/home/user/optimized.cpp"), "/home/user/optimized.cpp does not exist."
    assert os.path.isfile("/home/user/optimized.cpp"), "/home/user/optimized.cpp is not a file."


def test_run_tests_sh_exists_and_executable():
    script_path = "/home/user/run_tests.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_run_tests_script_executes_successfully():
    try:
        proc = subprocess.run(
            ["/home/user/run_tests.sh"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("run_tests.sh did not finish within 180 seconds.")
    assert proc.returncode == 0, (
        "run_tests.sh exited with a non-zero status.\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )


def test_generated_input_files_are_valid():
    small_path = "/home/user/small.txt"
    large_path = "/home/user/large.txt"
    assert os.path.isfile(small_path), f"{small_path} does not exist. Did run_tests.sh create it?"
    assert os.path.isfile(large_path), f"{large_path} does not exist. Did run_tests.sh create it?"

    small_tokens, small = read_integer_file(small_path)
    assert len(small_tokens) == 150, f"small.txt must contain exactly 150 integers, got {len(small_tokens)}."
    assert any(x < 0 for x in small), "small.txt must include negative integers."

    large_tokens, large = read_integer_file(large_path)
    assert len(large_tokens) == 1_000_000, (
        f"large.txt must contain exactly 1,000,000 integers, got {len(large_tokens)}."
    )
    assert all(-1000 <= x <= 1000 for x in large), (
        "Every integer in large.txt must be in the range -1000 to 1000."
    )
    assert any(x < 0 for x in large), "large.txt must contain negative integers."
    assert any(x > 0 for x in large), "large.txt must contain positive integers."


def test_result_log_and_correctness():
    log_path = "/home/user/result.log"
    large_txt_path = "/home/user/large.txt"

    assert os.path.exists(large_txt_path), f"{large_txt_path} does not exist. Did run_tests.sh create it?"
    assert os.path.exists(log_path), f"{log_path} does not exist. Did run_tests.sh run successfully?"

    with open(large_txt_path, "r") as f:
        content = f.read().split()

    arr = []
    for x in content:
        try:
            arr.append(int(x))
        except ValueError:
            pass

    expected_sum = max_subarray_sum(arr)
    expected_output = f"Max subarray sum: {expected_sum}"

    with open(log_path, "r") as f:
        log_content = f.read().strip()

    assert expected_output in log_content, f"Expected '{expected_output}' in {log_path}, but got '{log_content}'"


def test_optimized_binary_on_independent_inputs():
    cpp_path = "/home/user/optimized.cpp"
    bin_path = "/tmp/test_optimized_behavior_bin"
    compile_proc = subprocess.run(["g++", "-O3", cpp_path, "-o", bin_path], capture_output=True)
    assert compile_proc.returncode == 0, f"Failed to compile optimized.cpp:\n{compile_proc.stderr.decode()}"

    rng = random.SystemRandom()
    cases = [
        [],
        [7],
        [-9],
        [-8, -3, -12, -4],
        [4, -1, 2, 1, -7, 5],
        [1000, -1000, 1000, -999, 1000],
        [rng.randint(-1000, 1000) for _ in range(10007)],
    ]

    for arr in cases:
        with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
            f.write(" ".join(map(str, arr)))
            input_path = f.name
        try:
            proc = subprocess.run([bin_path, input_path], capture_output=True, text=True, timeout=5)
        finally:
            os.unlink(input_path)

        assert proc.returncode == 0, f"optimized binary failed on an independent input: {proc.stderr}"
        expected = f"Max subarray sum: {max_subarray_sum(arr)}\n"
        assert proc.stdout == expected, f"Expected exact output {expected!r}, got {proc.stdout!r}."


def test_optimized_performance():
    cpp_path = "/home/user/optimized.cpp"
    bin_path = "/tmp/test_optimized_bin"
    large_txt_path = "/home/user/large.txt"

    assert os.path.exists(cpp_path), "optimized.cpp is missing."
    assert os.path.exists(large_txt_path), "large.txt is missing."

    # Compile the optimized code
    compile_proc = subprocess.run(["g++", "-O3", cpp_path, "-o", bin_path], capture_output=True)
    assert compile_proc.returncode == 0, f"Failed to compile optimized.cpp:\n{compile_proc.stderr.decode()}"

    _, arr = read_integer_file(large_txt_path)
    expected_output = f"Max subarray sum: {max_subarray_sum(arr)}\n"

    # Run and time it
    start_time = time.time()
    run_proc = subprocess.run([bin_path, large_txt_path], capture_output=True, text=True)
    end_time = time.time()

    assert run_proc.returncode == 0, "optimized_bin failed to execute."
    assert run_proc.stdout == expected_output, (
        f"optimized_bin produced {run_proc.stdout!r}, expected {expected_output!r}."
    )

    elapsed = end_time - start_time
    assert elapsed < 1.0, f"Optimized binary took too long: {elapsed:.2f} seconds. Expected < 1.0s."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
