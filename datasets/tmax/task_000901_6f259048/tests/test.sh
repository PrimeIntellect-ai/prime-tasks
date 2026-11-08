#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

AUTH_TOKEN_PATH = "/home/user/auth.token"
AUTH_SERVICE_BIN = "/home/user/auth_service"
AUTH_SERVICE_SRC = "/home/user/auth_service.cpp"
SERVICE_LOG_PATH = "/home/user/service.log"
REPORT_PATH = "/home/user/report.txt"
OLD_TOKEN = "OLD_TOKEN_XYZ_89324"
EXPECTED_LOG = """[2023-10-01 10:00:01] INFO Connection from 192.168.1.50
[2023-10-01 10:00:02] DEBUG Auth attempt with token: [REDACTED]
[2023-10-01 10:00:02] INFO Access Granted to 192.168.1.50
[2023-10-01 10:05:12] DEBUG Auth attempt with token: invalid_token_123
[2023-10-01 10:05:12] INFO Access Denied to 10.0.0.5
[2023-10-01 10:10:00] DEBUG Auth attempt with token: [REDACTED]
[2023-10-01 10:10:00] INFO Access Granted to 172.16.0.4
"""


def read_token():
    with open(AUTH_TOKEN_PATH, "r") as f:
        return f.read().strip()


def assert_elf_executable(path):
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a regular file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def run_service(path, token, expected_output, expected_code):
    result = subprocess.run(
        [path, token], capture_output=True, text=True, timeout=5
    )
    assert result.stdout.strip() == expected_output, (
        f"{path} returned {result.stdout!r} for token {token!r}; "
        f"expected {expected_output!r}."
    )
    assert result.returncode == expected_code, (
        f"{path} returned status {result.returncode}; expected {expected_code}."
    )


def exercise_dynamic_token_loading(path):
    previous = None
    for _ in range(3):
        current = secrets.token_hex(16)
        second_line = secrets.token_hex(16)
        unrelated = secrets.token_hex(16)
        while len({current, second_line, unrelated, previous}) < (3 if previous is None else 4):
            current = secrets.token_hex(16)
            second_line = secrets.token_hex(16)
            unrelated = secrets.token_hex(16)

        # A second line verifies that only the first line is the expected token.
        with open(AUTH_TOKEN_PATH, "w") as f:
            f.write(current + "\n" + second_line + "\n")

        run_service(path, current, "Access Granted", 0)
        run_service(path, second_line, "Access Denied", 1)
        run_service(path, unrelated, "Access Denied", 1)
        if previous is not None:
            run_service(path, previous, "Access Denied", 1)
        previous = current


def test_auth_token():
    assert os.path.exists(AUTH_TOKEN_PATH), f"File {AUTH_TOKEN_PATH} does not exist."
    assert os.path.isfile(AUTH_TOKEN_PATH), f"{AUTH_TOKEN_PATH} is not a file."

    token = read_token()
    assert re.match(r"^[0-9a-f]{32}$", token), (
        f"Token in {AUTH_TOKEN_PATH} is not a 32-character lowercase hex string."
    )


def test_service_log_redaction():
    assert os.path.exists(SERVICE_LOG_PATH), f"File {SERVICE_LOG_PATH} does not exist."

    with open(SERVICE_LOG_PATH, "r") as f:
        content = f.read()

    assert OLD_TOKEN not in content, (
        f"Old token '{OLD_TOKEN}' was not completely redacted from {SERVICE_LOG_PATH}."
    )
    redacted_count = content.count("[REDACTED]")
    assert redacted_count == 2, (
        f"Expected exactly 2 instances of '[REDACTED]' in {SERVICE_LOG_PATH}, "
        f"found {redacted_count}."
    )
    assert content == EXPECTED_LOG, (
        "service.log content changed beyond replacing each old token with [REDACTED]."
    )


def test_auth_service_execution():
    assert_elf_executable(AUTH_SERVICE_BIN)
    valid_token = read_token()

    # Preserve the original valid and invalid execution assertions.
    run_service(AUTH_SERVICE_BIN, valid_token, "Access Granted", 0)
    run_service(
        AUTH_SERVICE_BIN,
        "invalid_token_1234567890123456789",
        "Access Denied",
        1,
    )


def test_source_code_fixed_and_artifacts_read_token_file():
    assert os.path.exists(AUTH_SERVICE_SRC), f"Source code {AUTH_SERVICE_SRC} does not exist."
    assert os.path.isfile(AUTH_SERVICE_SRC), f"{AUTH_SERVICE_SRC} is not a file."

    with open(AUTH_SERVICE_SRC, "r") as f:
        content = f.read()
    assert OLD_TOKEN not in content, (
        f"The hardcoded token '{OLD_TOKEN}' is still present in {AUTH_SERVICE_SRC}."
    )

    original_token_bytes = open(AUTH_TOKEN_PATH, "rb").read()
    try:
        with tempfile.TemporaryDirectory() as td:
            rebuilt = os.path.join(td, "auth_service_from_source")
            compiled = subprocess.run(
                ["g++", AUTH_SERVICE_SRC, "-o", rebuilt],
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert compiled.returncode == 0, (
                "auth_service.cpp did not compile with g++:\n" + compiled.stderr
            )
            assert_elf_executable(rebuilt)

            # Exercise both the submitted binary and an independently compiled copy
            # using verifier-generated rotations unknown to the submission.
            exercise_dynamic_token_loading(AUTH_SERVICE_BIN)
            exercise_dynamic_token_loading(rebuilt)
    finally:
        with open(AUTH_TOKEN_PATH, "wb") as f:
            f.write(original_token_bytes)


def test_report_content():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) >= 2, f"Report file {REPORT_PATH} does not have at least 2 lines."
    assert len(lines) == 2, f"Report file {REPORT_PATH} must contain exactly two lines."

    cwe_line = lines[0]
    assert cwe_line in ["CWE-798", "CWE-259"], (
        f"First line of report must be CWE-798 or CWE-259, got '{cwe_line}'."
    )

    valid_token = read_token()
    token_line = lines[1]
    assert token_line == valid_token, (
        f"Second line of report must be the new token '{valid_token}', got '{token_line}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
