#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import subprocess
from pathlib import Path

TOKEN_FILE = Path("/home/user/audit_token.txt")
DUMP_FILE = Path("/home/user/api_dump.txt")
CPP_FILE = Path("/home/user/parser.cpp")
PARSER_FILE = Path("/home/user/parser")
EXPECTED_TOKEN = "555345523d61756469746f723b5045524d3d4752414e545f4155444954"


def test_audit_token_correct():
    """Verify that the extracted audit token is exactly correct."""
    assert TOKEN_FILE.is_file(), f"{TOKEN_FILE} does not exist."
    content = TOKEN_FILE.read_text()
    assert content == EXPECTED_TOKEN, (
        f"The content of {TOKEN_FILE} is incorrect or contains extra "
        f"whitespace/newlines. Expected: {EXPECTED_TOKEN}, Got: {content!r}"
    )


def test_parser_cpp_exists():
    """Verify that the C++ source file exists."""
    assert CPP_FILE.is_file(), f"{CPP_FILE} does not exist."


def test_parser_executable_exists():
    """Verify that the compiled parser executable exists and is executable."""
    assert PARSER_FILE.is_file(), f"{PARSER_FILE} does not exist."
    st = PARSER_FILE.stat()
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"{PARSER_FILE} is not marked as executable."
    assert PARSER_FILE.read_bytes()[:4] == b"\x7fELF", (
        f"{PARSER_FILE} is not a compiled executable."
    )


def independently_decrypt_dump():
    fingerprint_output = subprocess.check_output(
        ["ssh-keygen", "-l", "-E", "md5", "-f", "/home/user/.ssh/id_rsa.pub"],
        text=True,
        timeout=10,
    )
    fingerprint = fingerprint_output.split()[1]
    assert fingerprint.startswith("MD5:")
    password = fingerprint[len("MD5:"):].replace(":", "")
    return subprocess.check_output(
        [
            "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
            "-in", "/home/user/api_dump.enc", "-pass", f"pass:{password}",
        ],
        stderr=subprocess.PIPE,
        timeout=10,
    )


def test_api_dump_txt_exists():
    """Verify that the API dump is the actual decryption and contains HTTP traffic."""
    assert DUMP_FILE.is_file(), f"{DUMP_FILE} does not exist."
    raw = DUMP_FILE.read_bytes()
    content = raw.decode(errors="ignore")
    assert "GET /api/v1" in content, (
        f"{DUMP_FILE} does not appear to be correctly decrypted "
        "(missing expected HTTP requests)."
    )
    assert "Authorization: Bearer" in content, (
        f"{DUMP_FILE} does not contain Authorization headers."
    )
    assert raw == independently_decrypt_dump(), (
        f"{DUMP_FILE} is not the exact plaintext obtained by decrypting api_dump.enc."
    )


def make_fixtures():
    marker1 = secrets.token_hex(12)
    marker2 = secrets.token_hex(12)

    expected1 = f"USER={marker1};PERM=GRANT_AUDIT;NONCE={secrets.token_hex(8)}".encode().hex()
    misleading_header = f"USER=wrong-{marker1};PERM=GRANT_AUDIT".encode().hex()
    near_match = f"USER={marker1};PERM=GRANT_AUDI".encode().hex()
    fixture1 = (
        "GET /api/noise HTTP/1.1\n"
        "Host: localhost\n"
        f"X-Authorization: Bearer {misleading_header}\n"
        f"Authorization: Bearer {near_match}\n"
        "Accept: */*\n\n"
        "GET /api/audit HTTP/1.1\n"
        "Host: localhost\n"
        f"Authorization: Bearer {expected1}\n"
        "Accept: */*\n\n"
    ).encode()

    # Upper-case hex verifies that the original encoded spelling is preserved.
    expected2 = f"RANDOM={marker2};PERM=GRANT_AUDIT;END=yes".encode().hex().upper()
    invalid2 = f"RANDOM={marker2};PERM=GRANT-ADMIN".encode().hex()
    fixture2 = (
        "POST /v2/check HTTP/1.1\n"
        "Host: example.invalid\n"
        f"Authorization: Bearer {invalid2}\n"
        "Content-Length: 0\n\n"
        "GET /v2/audit HTTP/1.1\n"
        "Host: example.invalid\n"
        f"Authorization: Bearer {expected2}\n"
        "Accept: application/json\n\n"
    ).encode()

    return [(fixture1, expected1.encode()), (fixture2, expected2.encode())]


def run_parser_cases(executable, fixtures):
    for dump, expected in fixtures:
        DUMP_FILE.write_bytes(dump)
        if TOKEN_FILE.exists():
            TOKEN_FILE.unlink()
        result = subprocess.run(
            [str(executable)],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{executable} exited with {result.returncode}; stderr={result.stderr!r}"
        )
        assert TOKEN_FILE.is_file(), f"{executable} did not create {TOKEN_FILE}."
        actual = TOKEN_FILE.read_bytes()
        assert actual == expected, (
            f"{executable} produced {actual!r}; expected the original encoded "
            f"token {expected!r}."
        )


def test_parser_behavior_and_source():
    """Execute both the submitted binary and a fresh build on derived test traffic."""
    original_dump = DUMP_FILE.read_bytes()
    original_token = TOKEN_FILE.read_bytes()
    rebuilt = Path("/tmp/parser_from_submitted_source")
    fixtures = make_fixtures()

    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", str(CPP_FILE), "-o", str(rebuilt)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "parser.cpp does not compile: " + compile_result.stderr.decode(errors="replace")
        )
        run_parser_cases(PARSER_FILE, fixtures)
        run_parser_cases(rebuilt, fixtures)
    finally:
        DUMP_FILE.write_bytes(original_dump)
        TOKEN_FILE.write_bytes(original_token)
        if rebuilt.exists():
            rebuilt.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
