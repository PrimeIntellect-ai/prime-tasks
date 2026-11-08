#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

BINARY = "/home/user/sensor_daemon"
SOURCE = "/home/user/sensor_daemon.c"
REBUILT = "/tmp/verifier_sensor_daemon"


def test_sensor_daemon_binary_exists():
    path = "/home/user/sensor_daemon"
    assert os.path.isfile(path), f"Expected compiled binary {path} does not exist."
    assert os.access(path, os.X_OK), f"Expected binary {path} to be executable."


def test_output_log_content():
    path = "/home/user/output.log"
    assert os.path.isfile(path), f"Expected output log {path} does not exist. Did the program run successfully?"

    with open(path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "Window: 1700000000.000000 to 1700000000.200000, avg: 10.000000",
        "Window: 1700000001.000000 to 1700000001.100000, avg: 20.000000",
        "Window: 1700000003.000000 to 1700000003.150000, avg: 30.000000"
    ]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in output.log, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."


def test_valgrind_clean():
    binary = "/home/user/sensor_daemon"
    csv_file = "/home/user/data.csv"

    assert os.path.isfile(binary), "Binary missing, cannot run valgrind."
    assert os.path.isfile(csv_file), "CSV file missing, cannot run valgrind."

    cmd = [
        "valgrind",
        "--leak-check=full",
        "--error-exitcode=1",
        binary,
        csv_file
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        pytest.fail("Valgrind execution timed out. The infinite loop bug might not be fixed.")

    assert result.returncode == 0, (
        "Valgrind reported memory leaks or errors. "
        f"Return code: {result.returncode}\n"
        f"Stderr:\n{result.stderr}"
    )


def build_source():
    result = subprocess.run(
        ["gcc", "-g", "-O0", SOURCE, "-o", REBUILT],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"sensor_daemon.c failed to compile:\n{result.stderr}"
    assert os.path.isfile(REBUILT) and os.access(REBUILT, os.X_OK)


def test_modified_source_compiles():
    assert os.path.isfile(SOURCE), f"Expected source file {SOURCE} does not exist."
    build_source()


# Generate cases at verification time so a program cannot pass by emitting the
# three lines from the shipped data.csv. Values are kept exactly representable
# for stable comparison with C's %f formatting.
TOKEN = secrets.token_hex(8)
BASE = secrets.randbelow(4_000_000_000) + 3_000_000_000
VALUE1 = secrets.randbelow(80) + 10
VALUE2 = secrets.randbelow(80) + 110
DYNAMIC_CSV = f"/tmp/sensor_input_{TOKEN}.csv"
DYNAMIC_DATA = (
    f"{BASE}.0,{BASE}.25,{VALUE1}.0\n"
    "not,a,valid,sensor,record\n"
    f"{BASE + 1}.0,{BASE + 1}.25,-7.0\n"
    f"{BASE + 2}.0,{BASE + 2}.5,{VALUE2}.0\n"
    "missing_fields,12\n"
    f"{BASE + 4}.5,{BASE + 4}.0,44.0\n"
)
DYNAMIC_EXPECTED = [
    f"Window: {float(BASE):.6f} to {BASE + 0.25:.6f}, avg: {float(VALUE1):.6f}",
    f"Window: {float(BASE + 2):.6f} to {BASE + 2.5:.6f}, avg: {float(VALUE2):.6f}",
]


def write_dynamic_csv():
    with open(DYNAMIC_CSV, "w") as f:
        f.write(DYNAMIC_DATA)


def assert_dynamic_output():
    path = "/home/user/output.log"
    assert os.path.isfile(path), "Program did not create /home/user/output.log"
    with open(path, "r") as f:
        actual = f.read().strip().splitlines()
    assert actual == DYNAMIC_EXPECTED, (
        "Output for verifier-generated CSV was incorrect.\n"
        f"Expected: {DYNAMIC_EXPECTED}\nActual: {actual}"
    )


@pytest.mark.parametrize("binary", [BINARY, REBUILT])
def test_generated_csv_behavior(binary):
    if binary == REBUILT:
        build_source()
    write_dynamic_csv()
    try:
        os.remove("/home/user/output.log")
    except FileNotFoundError:
        pass
    try:
        result = subprocess.run(
            [binary, DYNAMIC_CSV], capture_output=True, text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Execution on large UNIX timestamps timed out; the timestamp loop may still hang.")
    assert result.returncode == 0, (
        f"Program failed on verifier-generated CSV with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert_dynamic_output()


@pytest.mark.parametrize("binary", [BINARY, REBUILT])
def test_generated_invalid_records_are_valgrind_clean(binary):
    if binary == REBUILT:
        build_source()
    write_dynamic_csv()
    cmd = [
        "valgrind",
        "--leak-check=full",
        "--show-leak-kinds=all",
        "--errors-for-leak-kinds=all",
        "--error-exitcode=1",
        binary,
        DYNAMIC_CSV,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        pytest.fail("Valgrind execution on large UNIX timestamps timed out.")
    assert result.returncode == 0, (
        "Valgrind found an error or leak while processing generated corrupt/invalid records. "
        f"Return code: {result.returncode}\nStderr:\n{result.stderr}"
    )
    assert "ERROR SUMMARY: 0 errors" in result.stderr, result.stderr
    assert_dynamic_output()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
