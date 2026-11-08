#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

SOURCE = "/home/user/auth_api.cpp"
BINARY = "/home/user/auth_api"
REBUILT_BINARY = "/tmp/auth_api_rebuilt"


def token_for(username, timestamp):
    val = sum(ord(char) * (i + 1) for i, char in enumerate(username))
    return (val * timestamp) % 999983


def expected_response(username, timestamp):
    body = f'{{"username": "{username}", "token": {token_for(username, timestamp)}}}'
    return f"HTTP/1.1 200 OK\nContent-Type: application/json\n\n{body}"


def assert_exact_response(binary, username, timestamp):
    result = subprocess.run(
        [binary, f"{username}:{timestamp}"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Execution failed with return code {result.returncode}: {result.stderr}"
    assert result.stderr == "", f"Unexpected stderr output: {result.stderr!r}"

    expected = expected_response(username, timestamp)
    # Accept standard LF or HTTP-style CRLF, with at most one final line ending.
    valid_outputs = {
        expected,
        expected + "\n",
        expected.replace("\n", "\r\n"),
        expected.replace("\n", "\r\n") + "\r\n",
    }
    assert result.stdout in valid_outputs, (
        f"Response did not exactly match the required HTTP response.\n"
        f"Expected: {expected!r}\nActual: {result.stdout!r}"
    )


def test_source_file_exists():
    assert os.path.isfile(SOURCE), "/home/user/auth_api.cpp does not exist."


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY), "Compiled binary /home/user/auth_api does not exist."
    assert os.access(BINARY, os.X_OK), "/home/user/auth_api is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/auth_api is not a compiled ELF binary."


def test_source_compiles():
    result = subprocess.run(
        ["g++", SOURCE, "-o", REBUILT_BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Source failed to compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(REBUILT_BINARY) and os.access(REBUILT_BINARY, os.X_OK)


def test_auth_api_output_sysadmin():
    assert_exact_response(BINARY, "sysadmin", 1715000000)
    assert token_for("sysadmin", 1715000000) == 964796


def test_auth_api_output_testuser():
    assert token_for("testuser", 1234567890) == 878467
    assert_exact_response(BINARY, "testuser", 1234567890)


def test_varied_and_large_inputs():
    cases = [
        ("a", 0),
        ("admin", 1700000000),
        ("OverflowCheck", 9223372036854775807),
    ]
    alphabet = string.ascii_letters + string.digits + "_-"
    for _ in range(8):
        username = "u" + "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(20) + 1))
        timestamp = secrets.randbelow(9223372036854775808)
        cases.append((username, timestamp))

    for username, timestamp in cases:
        assert_exact_response(BINARY, username, timestamp)
        assert_exact_response(REBUILT_BINARY, username, timestamp)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
