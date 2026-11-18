#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

SOURCE_PATH = "/home/user/service.c"
EXECUTABLE_PATH = "/home/user/service_fixed"
PAYLOAD_PATH = "/home/user/bad_payload.txt"


def get_expected_payload():
    dump_path = "/home/user/memory.dump"
    assert os.path.isfile(dump_path), f"File not found: {dump_path}"

    with open(dump_path, "rb") as f:
        content = f.read()

    match = re.search(b"(CRASH_PAYLOAD:[A-Za-z0-9_]+)", content)
    assert match is not None, "Could not find CRASH_PAYLOAD in memory.dump"
    return match.group(1).decode("utf-8")


def run_service(path, input_data, timeout=3.0, env=None):
    try:
        return subprocess.run(
            [path],
            input=input_data,
            text=True,
            timeout=timeout,
            capture_output=True,
            env=env,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out (infinite recursion not fixed).")


def assert_parser_behavior(path):
    token = "DATA_" + secrets.token_hex(16)
    cases = [
        (token, f"Processed: {token}\n"),
        ("Z" + token, f"Processed: {token}\n"),
        ("Z" * 120 + token, f"Processed: {token}\n"),
    ]

    for input_data, expected_stdout in cases:
        result = run_service(path, input_data + "\n")
        assert result.returncode == 0, (
            f"{path} crashed or returned {result.returncode} for telemetry input. "
            f"Stderr: {result.stderr}"
        )
        assert result.stdout == expected_stdout, (
            f"{path} did not parse nested telemetry correctly. "
            f"Expected {expected_stdout!r}, got {result.stdout!r}"
        )


def test_bad_payload_file():
    assert os.path.isfile(PAYLOAD_PATH), f"File not found: {PAYLOAD_PATH}"

    with open(PAYLOAD_PATH, "r") as f:
        content = f.read().strip()

    expected_payload = get_expected_payload()
    assert content == expected_payload, (
        f"Contents of {PAYLOAD_PATH} do not match the expected payload."
    )


def test_service_fixed_executable():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found: {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File is not executable: {EXECUTABLE_PATH}"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "service_fixed is not a compiled ELF executable"


def test_service_fixed_execution():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found: {EXECUTABLE_PATH}"
    assert os.path.isfile(PAYLOAD_PATH), f"Payload file not found: {PAYLOAD_PATH}"

    with open(PAYLOAD_PATH, "r") as f:
        payload_data = f.read()

    result = run_service(EXECUTABLE_PATH, payload_data)
    assert result.returncode == 0, (
        f"service_fixed crashed or returned non-zero exit code: {result.returncode}. "
        f"Stderr: {result.stderr}"
    )
    assert result.stdout == f"Processed: {payload_data}\n", (
        "service_fixed did not process the extracted malicious payload as expected"
    )


def test_fixed_binary_parses_nested_telemetry():
    assert_parser_behavior(EXECUTABLE_PATH)


def test_repaired_source_compiles_and_is_leak_free():
    assert os.path.isfile(SOURCE_PATH), f"File not found: {SOURCE_PATH}"
    with open(SOURCE_PATH, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bparse_telemetry\b", source), (
        "service.c no longer contains parse_telemetry"
    )

    sanitized_binary = "/tmp/service_from_submitted_source"
    compile_result = subprocess.run(
        [
            "gcc", "-O0", "-g", "-fsanitize=address", "-fno-omit-frame-pointer",
            SOURCE_PATH, "-o", sanitized_binary,
        ],
        text=True,
        capture_output=True,
        timeout=15.0,
    )
    assert compile_result.returncode == 0, (
        f"Updated service.c does not compile with gcc: {compile_result.stderr}"
    )

    token = "DATA_" + secrets.token_hex(16)
    nested_input = "Z" * 120 + token + "\n"
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
    env["LSAN_OPTIONS"] = "exitcode=23"
    result = run_service(sanitized_binary, nested_input, timeout=5.0, env=env)
    assert result.returncode == 0, (
        "The submitted service.c still crashes, recurses indefinitely, or leaks memory "
        f"when parsing nested telemetry. Stderr: {result.stderr}"
    )
    assert result.stdout == f"Processed: {token}\n", (
        "The submitted service.c does not advance through nested Z telemetry layers"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
