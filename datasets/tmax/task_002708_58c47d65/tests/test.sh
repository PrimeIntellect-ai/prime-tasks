#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import subprocess

import pytest

LIB_PATH = "/home/user/legacy_math/libmath_core.so"
lib = ctypes.CDLL(LIB_PATH)
lib.compute_transform.argtypes = [ctypes.c_uint64]
lib.compute_transform.restype = ctypes.c_uint64


def expected_transform(value):
    return int(lib.compute_transform(value))


def grpc_transform(value):
    cmd = [
        "grpcurl",
        "-plaintext",
        "-d", json.dumps({"value": value}),
        "127.0.0.1:50051",
        "transform_api.TransformService/ApplyTransform",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except FileNotFoundError:
        pytest.fail("grpcurl command not found.")
    except subprocess.TimeoutExpired:
        pytest.fail("grpcurl command timed out. Is the gRPC server running?")

    assert result.returncode == 0, f"grpcurl failed with error: {result.stderr}"
    try:
        response_json = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse gRPC response as JSON. Output was: {result.stdout}")

    assert "result" in response_json, f"gRPC response has no result field: {result.stdout}"
    return int(response_json["result"])


def test_answer_txt_exists_and_correct():
    answer_file = "/home/user/answer.txt"
    assert os.path.isfile(answer_file), f"File {answer_file} does not exist."
    with open(answer_file, "r") as f:
        content = f.read().strip()
    expected = str(expected_transform(1337))
    assert content == expected, f"Expected '{expected}' in {answer_file}, but got '{content}'."


def test_benchmark_sh_exists_and_executable():
    script_file = "/home/user/benchmark.sh"
    assert os.path.isfile(script_file), f"File {script_file} does not exist."
    assert os.access(script_file, os.X_OK), f"File {script_file} is not executable."


def test_benchmark_result_exists_and_not_empty():
    result_file = "/home/user/benchmark_result.txt"
    assert os.path.isfile(result_file), f"File {result_file} does not exist."
    assert os.path.getsize(result_file) > 0, f"File {result_file} is empty."


def test_grpc_server_running_and_correct():
    values = [5]
    values.extend(secrets.randbelow(1_000_000_000) + 1 for _ in range(4))
    for value in values:
        actual = grpc_transform(value)
        expected = expected_transform(value)
        assert actual == expected, (
            f"For input {value}, expected result '{expected}', but got '{actual}'."
        )


def test_benchmark_script_executes_successfully():
    answer_file = "/home/user/answer.txt"
    result_file = "/home/user/benchmark_result.txt"

    with open(result_file, "rb") as f:
        previous_result = f.read()
    if os.path.exists(answer_file):
        os.remove(answer_file)

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/legacy_math" + (
        ":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else ""
    )
    try:
        completed = subprocess.run(
            ["/home/user/benchmark.sh"],
            capture_output=True,
            text=True,
            timeout=120,
            env=env,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("benchmark.sh timed out.")

    assert completed.returncode == 0, (
        f"benchmark.sh failed with stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )
    assert os.path.isfile(answer_file), "benchmark.sh did not create /home/user/answer.txt."
    with open(answer_file, "r") as f:
        answer = f.read().strip()
    expected = str(expected_transform(1337))
    assert answer == expected, f"Expected benchmark answer '{expected}', but got '{answer}'."

    assert os.path.isfile(result_file), "benchmark.sh removed or failed to create benchmark_result.txt."
    with open(result_file, "rb") as f:
        new_result = f.read()
    assert new_result.startswith(previous_result), "benchmark.sh did not append to benchmark_result.txt."
    assert len(new_result) > len(previous_result), "benchmark.sh did not append a benchmark result."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
