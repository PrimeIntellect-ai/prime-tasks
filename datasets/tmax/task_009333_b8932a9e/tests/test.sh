#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
import pytest

AUTH_SERVER = "/home/user/auth_server"
SOURCE = "/home/user/auth_server.c"
NONE_MARKER = "eyJhbGciOiJub25lIn0"


def run_server(path, token):
    return subprocess.run([path, token], capture_output=True, text=True, timeout=5)


def expected_result(token):
    if NONE_MARKER in token:
        return "REJECTED: INSECURE_ALG\n", 1
    if ".VALID_SIG" in token:
        return "ACCEPTED: VALID_SIGNATURE\n", 0
    return "REJECTED: INVALID_SIGNATURE\n", 1


@pytest.fixture(scope="session")
def rebuilt_server():
    assert os.path.isfile(SOURCE), f"Missing source file: {SOURCE}"
    fd, output = tempfile.mkstemp(prefix="rebuilt_auth_server_", dir="/tmp")
    os.close(fd)
    os.unlink(output)
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", output],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Patched source does not compile with gcc: {result.stderr}"
    yield output
    try:
        os.unlink(output)
    except FileNotFoundError:
        pass


def test_exploit_id_correct():
    path = "/home/user/exploit_id.txt"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "TKN-03", f"Expected exploit_id.txt to contain 'TKN-03', but got '{content}'"


def test_audit_trail_correct():
    path = "/home/user/audit_trail.log"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[TKN-01] ACCEPTED: VALID_SIGNATURE",
        "[TKN-02] REJECTED: INVALID_SIGNATURE",
        "[TKN-03] REJECTED: INSECURE_ALG",
        "[TKN-04] ACCEPTED: VALID_SIGNATURE"
    ]

    assert lines == expected_lines, f"Audit trail content does not match expected output. Got: {lines}"


def test_audit_trail_matches_binary_and_token_file():
    with open("/home/user/tokens.txt", "r") as f:
        token_rows = [line.rstrip("\n") for line in f if line.strip()]
    with open("/home/user/audit_trail.log", "r") as f:
        audit_rows = [line.strip() for line in f if line.strip()]

    derived_rows = []
    exploit_ids = []
    for row in token_rows:
        token_id, token = row.split(":", 1)
        result = run_server(AUTH_SERVER, token)
        expected_stdout, expected_code = expected_result(token)
        assert result.stdout == expected_stdout
        assert result.returncode == expected_code
        derived_rows.append(f"[{token_id}] {result.stdout.rstrip()}")
        if NONE_MARKER in token:
            exploit_ids.append(token_id)

    assert audit_rows == derived_rows
    assert len(exploit_ids) == 1
    with open("/home/user/exploit_id.txt", "r") as f:
        assert f.read().strip() == exploit_ids[0]


def test_auth_server_binary_exists():
    path = AUTH_SERVER
    assert os.path.isfile(path), f"Missing compiled binary: {path}"
    assert os.access(path, os.X_OK), f"Binary {path} is not executable"


def test_auth_server_is_elf():
    with open(AUTH_SERVER, "rb") as f:
        header = f.read(20)
    assert len(header) >= 20 and header[:4] == b"\x7fELF", "auth_server is not an ELF executable"
    assert header[4] in (1, 2), "Invalid ELF class"
    assert header[5] in (1, 2), "Invalid ELF byte order"
    byte_order = "<" if header[5] == 1 else ">"
    elf_type = struct.unpack(byte_order + "H", header[16:18])[0]
    assert elf_type in (2, 3), f"ELF is not an executable or PIE (type {elf_type})"


def test_auth_server_patched_behavior():
    path = AUTH_SERVER
    assert os.path.isfile(path), f"Missing compiled binary: {path}"

    malicious_token = "eyJhbGciOiJub25lIn0.malicious_payload."
    result = subprocess.run([path, malicious_token], capture_output=True, text=True)
    assert "REJECTED: INSECURE_ALG" in result.stdout, "Patched binary did not output 'REJECTED: INSECURE_ALG' for alg=none token"
    assert result.returncode == 1, f"Patched binary should exit with status 1 for malicious token, got {result.returncode}"


def test_auth_server_normal_behavior():
    path = AUTH_SERVER
    assert os.path.isfile(path), f"Missing compiled binary: {path}"

    valid_token = "eyJhbGciOiJIUzI1NiJ9.payload.VALID_SIG"
    result = subprocess.run([path, valid_token], capture_output=True, text=True)
    assert "ACCEPTED: VALID_SIGNATURE" in result.stdout, "Patched binary failed to accept valid token"
    assert result.returncode == 0, f"Patched binary should exit with status 0 for valid token, got {result.returncode}"


def test_randomized_behavior_and_patched_source(rebuilt_server):
    tokens = []
    for _ in range(12):
        prefix = secrets.token_urlsafe(18)
        suffix = secrets.token_urlsafe(18)
        tokens.extend([
            f"{prefix}.{NONE_MARKER}.{suffix}",
            f"{prefix}.{NONE_MARKER}.{suffix}.VALID_SIG",
            f"{prefix}.{suffix}.VALID_SIG",
            f"{prefix}.{suffix}.INVALID_SIG",
            f"{prefix}.{suffix}",
        ])

    for token in tokens:
        expected_stdout, expected_code = expected_result(token)
        for executable in (AUTH_SERVER, rebuilt_server):
            result = run_server(executable, token)
            assert result.stdout == expected_stdout, (
                f"Unexpected output for randomized token using {executable}: {result.stdout!r}"
            )
            assert result.stderr == "", f"Unexpected stderr from {executable}: {result.stderr!r}"
            assert result.returncode == expected_code, (
                f"Unexpected status for randomized token using {executable}: {result.returncode}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
