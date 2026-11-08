#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/home/user/artifact_validator"
SOURCE_PATH = "/home/user/artifact_validator.c"
HIDDEN_TESTS_DIR = "/home/user/hidden_tests"


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF executable."


def test_source_exists_and_compiles():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", "-O2", "-o", "/tmp/artifact_validator_from_source", SOURCE_PATH],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Source failed to compile:\n{result.stdout}\n{result.stderr}"


def run_validator(req_file):
    req_path = os.path.join(HIDDEN_TESTS_DIR, req_file)
    assert os.path.isfile(req_path), f"Test file {req_path} is missing."

    result = subprocess.run(
        [BINARY_PATH, req_path],
        capture_output=True,
        text=True
    )
    return result.stdout.strip()


def test_valid_request():
    output = run_validator("req1.txt")
    expected = "VALID /artifacts/release/v2.1.0/bin.tar.gz"
    assert output == expected, f"Expected '{expected}', but got '{output}' for req1.txt"


def test_traversal_rejection():
    output = run_validator("req2.txt")
    expected = "REJECTED TRAVERSAL"
    assert output == expected, f"Expected '{expected}', but got '{output}' for req2.txt"


def test_invalid_route_rejection():
    output = run_validator("req3.txt")
    expected = "REJECTED INVALID_ROUTE"
    assert output == expected, f"Expected '{expected}', but got '{output}' for req3.txt"


def test_bad_token_short():
    output = run_validator("req4.txt")
    expected = "REJECTED BAD_TOKEN"
    assert output == expected, f"Expected '{expected}', but got '{output}' for req4.txt"


def test_bad_token_missing():
    output = run_validator("req5.txt")
    expected = "REJECTED BAD_TOKEN"
    assert output == expected, f"Expected '{expected}', but got '{output}' for req5.txt"


def invoke_with_request(executable, request):
    fd, path = tempfile.mkstemp(prefix="validator_dynamic_", suffix="_" + secrets.token_hex(6))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(request.encode("ascii"))
        return subprocess.run([executable, path], capture_output=True, text=True, timeout=5)
    finally:
        os.unlink(path)


def assert_exact(executable, request, expected):
    result = invoke_with_request(executable, request)
    assert result.returncode == 0, f"Validator returned {result.returncode}; stderr={result.stderr!r}"
    assert result.stdout == expected + "\n", (
        f"Expected exact stdout {expected + chr(10)!r}, got {result.stdout!r}; stderr={result.stderr!r}"
    )


@pytest.mark.parametrize("executable", [BINARY_PATH, "/tmp/artifact_validator_from_source"])
def test_dynamic_general_parser_behavior(executable):
    token1 = secrets.token_hex(8)
    token2 = secrets.token_hex(8).upper()
    name1 = secrets.token_hex(7)
    name2 = secrets.token_hex(6)

    plain_uri = f"/artifacts/releases/{name1}/package.tar.gz"
    plain_request = (
        f"GET {plain_uri} HTTP/1.1\r\n"
        f"Host: dynamic-{secrets.token_hex(4)}.local\r\n"
        "Accept: application/octet-stream\r\n"
        f"X-Build-Token: {token1}\r\n"
        "Connection: close\r\n\r\n"
    )
    assert_exact(executable, plain_request, f"VALID {plain_uri}")

    encoded_uri = f"/artifacts/releases%2f{name2}%2Ebin"
    decoded_uri = f"/artifacts/releases/{name2}.bin"
    encoded_request = (
        f"GET {encoded_uri} HTTP/1.1\n"
        "X-Extra-Header: arbitrary\n"
        f"X-Build-Token: {token2}\n"
        "Host: artifacts.local\n\n"
    )
    assert_exact(executable, encoded_request, f"VALID {decoded_uri}")

    traversal_request = (
        f"GET /artifacts/{name1}/%2e%2E%2fsecret.txt HTTP/1.1\r\n"
        "Host: artifacts.local\r\n"
        f"X-Build-Token: {token1}\r\n\r\n"
    )
    assert_exact(executable, traversal_request, "REJECTED TRAVERSAL")

    plain_traversal_request = (
        f"GET /artifacts/{name2}/../private/data HTTP/1.1\n"
        f"X-Build-Token: {token2}\n\n"
    )
    assert_exact(executable, plain_traversal_request, "REJECTED TRAVERSAL")

    invalid_route = f"/artifact-{secrets.token_hex(5)}/file.zip"
    invalid_route_request = (
        f"GET {invalid_route} HTTP/1.1\r\n"
        f"X-Build-Token: {token1}\r\n\r\n"
    )
    assert_exact(executable, invalid_route_request, "REJECTED INVALID_ROUTE")

    near_prefix = f"/artifactsx/{secrets.token_hex(5)}.zip"
    near_prefix_request = (
        f"GET {near_prefix} HTTP/1.1\n"
        f"X-Build-Token: {token2}\n\n"
    )
    assert_exact(executable, near_prefix_request, "REJECTED INVALID_ROUTE")

    for bad_token in [secrets.token_hex(7), secrets.token_hex(8) + "0", "G" + secrets.token_hex(8)[1:]]:
        request = (
            f"GET /artifacts/{secrets.token_hex(5)}.tgz HTTP/1.1\r\n"
            "Host: artifacts.local\r\n"
            f"X-Build-Token: {bad_token}\r\n\r\n"
        )
        assert_exact(executable, request, "REJECTED BAD_TOKEN")

    missing_token_request = (
        f"GET /artifacts/{secrets.token_hex(5)}.tgz HTTP/1.1\n"
        "Host: artifacts.local\n"
        "Accept: */*\n\n"
    )
    assert_exact(executable, missing_token_request, "REJECTED BAD_TOKEN")

    non_get_request = (
        f"POST /artifacts/{secrets.token_hex(5)}.tgz HTTP/1.1\r\n"
        f"X-Build-Token: {token1}\r\n\r\n"
    )
    result = invoke_with_request(executable, non_get_request)
    assert result.returncode == 0, f"Validator returned {result.returncode} for a rejected method."
    assert re.fullmatch(r"REJECTED [A-Z_]+\n", result.stdout), (
        f"A non-GET request must produce exactly one rejection line, got {result.stdout!r}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
