#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

CPP_PATH = "/home/user/telemetry/telemetry_processor.cpp"
BINARY_PATH = "/home/user/telemetry/telemetry_processor"
DATA_PATH = "/home/user/telemetry/data.bin"
ERROR_MESSAGE = "Buffer overflow during varint decoding"


def run_binary(binary, data):
    return subprocess.run(
        [binary, data], capture_output=True, text=True, timeout=5
    )


def encode_varint(value):
    encoded = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            encoded.append(byte | 0x80)
        else:
            encoded.append(byte)
            return encoded


def make_records(rng, count):
    data = bytearray()
    total = 0
    for i in range(count):
        if i == 0 or total == 0 or rng.randrange(2) == 0:
            record_type = 1
            value = rng.randint(1, 100000)
            total += value
        else:
            record_type = 2
            value = rng.randint(1, total)
            total -= value
        data.append(record_type)
        data.extend(encode_varint(value))
    return data, total


def assert_valid_run(binary, path, expected):
    result = run_binary(binary, path)
    output = result.stdout + result.stderr
    assert result.returncode == 0, (
        f"{binary} failed on valid input with return code {result.returncode}: {output}"
    )
    assert f"Processing Complete. Total Sum: {expected}" in output, (
        f"Incorrect output for derived valid input. Expected Total Sum {expected}, got: {output}"
    )


def assert_truncated_run(binary, path, expected):
    result = run_binary(binary, path)
    output = result.stdout + result.stderr
    assert result.returncode == 0, (
        f"{binary} did not handle a truncated varint gracefully. "
        f"Return code {result.returncode}: {output}"
    )
    assert f"Error: {ERROR_MESSAGE}" in output, (
        f"Output did not contain the exact bounds error: {output}"
    )
    assert f"Processing Aborted. Total Sum: {expected}" in output, (
        f"Incorrect partial sum for derived malformed input. Expected {expected}, got: {output}"
    )


def test_solution_file_content():
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"{solution_path} does not exist. Did you save your answer?"

    with open(solution_path, "r") as f:
        content = f.read().strip()

    assert content == "20937", f"Expected solution to be '20937', but found '{content}'"


def test_cpp_code_fixed():
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} does not exist."

    with open(CPP_PATH, "r") as f:
        code = f.read()

    assert ERROR_MESSAGE in code, (
        f"The C++ code does not contain the exact expected exception message: '{ERROR_MESSAGE}'"
    )


def test_binary_compiled_and_runs():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} does not exist. Did you run 'make'?"
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."
    assert os.path.isfile(DATA_PATH), f"{DATA_PATH} does not exist. Did you run generate_traffic.py?"

    result = run_binary(BINARY_PATH, DATA_PATH)
    assert result.returncode == 0, (
        f"telemetry_processor crashed or exited with an error. Return code: {result.returncode}"
    )

    output = result.stdout + result.stderr
    assert ERROR_MESSAGE in output, (
        "Output did not contain the expected error message from the caught exception."
    )
    assert "20937" in output, "Output did not contain the expected Total Sum (20937)."


def test_source_and_artifact_on_derived_inputs():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "telemetry_processor_rebuilt")
        compile_result = subprocess.run(
            ["g++", "-O2", "-Wall", "-std=c++14", "-o", rebuilt, CPP_PATH],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "Submitted source does not compile:\n"
            + compile_result.stdout
            + compile_result.stderr
        )

        binaries = [BINARY_PATH, rebuilt]
        for case in range(4):
            records, expected = make_records(rng, rng.randint(8, 35))

            valid_path = os.path.join(tmpdir, f"valid_{case}.bin")
            with open(valid_path, "wb") as f:
                f.write(records)

            malformed_path = os.path.join(tmpdir, f"malformed_{case}.bin")
            with open(malformed_path, "wb") as f:
                f.write(records)
                f.write(bytes([0x01]))
                f.write(bytes([0x80 | rng.randrange(128) for _ in range(rng.randint(1, 6))]))

            for binary in binaries:
                assert_valid_run(binary, valid_path, expected)
                assert_truncated_run(binary, malformed_path, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
