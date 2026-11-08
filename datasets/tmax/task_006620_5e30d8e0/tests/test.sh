#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import struct
import subprocess
import pytest

ROOT = "/home/user/telemetry_service"
SOURCE = os.path.join(ROOT, "main.cpp")
EXECUTABLE = os.path.join(ROOT, "telemetry")
ORIGINAL_INPUT = os.path.join(ROOT, "input.bin")


def run_program(executable, input_file):
    try:
        return subprocess.run(
            [executable, input_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            text=True,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} timed out while processing {input_file}")
    except Exception as exc:
        pytest.fail(f"Failed to run {executable}: {exc}")


@pytest.fixture(scope="session")
def rebuilt_executable():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    output = "/tmp/telemetry_rebuilt_from_submission"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O0", "-g", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        text=True,
    )
    assert result.returncode == 0, (
        "The submitted main.cpp does not compile.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    return output


def write_native_packet(path, sensor_value, magic=0xDEADBEEF):
    # On the target C++ ABI, Packet has four padding bytes before its double.
    packet = struct.pack("<I", magic) + b"\x00" * 4 + struct.pack("<d", sensor_value)
    assert len(packet) == 16
    path.write_bytes(packet)


def assert_graceful(result, context):
    assert result.returncode == 0, (
        f"Expected exit code 0 for {context}, got {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def test_crash_value_file():
    path = "/home/user/crash_value.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    fixture = open(ORIGINAL_INPUT, "rb").read()
    assert len(fixture) >= 12, "The supplied telemetry fixture is truncated."
    assert struct.unpack_from("<I", fixture, 0)[0] == 0xDEADBEEF
    expected = struct.unpack_from("<d", fixture, 4)[0]

    with open(path, "r") as value_file:
        content = value_file.read().strip()

    assert content == format(expected, ".17g"), (
        f"Expected crash_value.txt to contain the precise serialized double "
        f"{format(expected, '.17g')!r}, but found {content!r}."
    )


def test_executable_exists_and_is_native_binary():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.path.isfile(EXECUTABLE), f"Path {EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "telemetry must be a compiled ELF executable."


def test_executable_runs_supplied_input_successfully():
    assert os.path.exists(ORIGINAL_INPUT), f"Input file {ORIGINAL_INPUT} is missing."
    assert_graceful(run_program(EXECUTABLE, ORIGINAL_INPUT), "the supplied input.bin")


@pytest.mark.parametrize("sensor_value", [-1.5, -0.2, 10.0, 1.0e300, float("inf"), float("nan")])
def test_out_of_bounds_values_are_ignored(tmp_path, rebuilt_executable, sensor_value):
    input_file = tmp_path / "packet.bin"
    write_native_packet(input_file, sensor_value)

    for executable in (EXECUTABLE, rebuilt_executable):
        result = run_program(executable, str(input_file))
        assert_graceful(result, f"out-of-bounds sensor value {sensor_value!r}")
        assert "Processed index:" not in result.stdout, (
            f"{executable} processed an out-of-bounds sensor value {sensor_value!r} "
            "instead of safely ignoring it."
        )


def test_valid_value_is_still_processed(tmp_path, rebuilt_executable):
    input_file = tmp_path / "valid_packet.bin"
    write_native_packet(input_file, 4.5)

    for executable in (EXECUTABLE, rebuilt_executable):
        result = run_program(executable, str(input_file))
        assert_graceful(result, "valid sensor value 4.5")
        assert "Processed index: 45" in result.stdout, (
            f"{executable} did not retain the original behavior for a valid packet.\n"
            f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
