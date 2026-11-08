#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import string
import subprocess
import tempfile

import pytest


def test_audit_report():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) >= 3, "Audit report must contain at least 3 lines"

    cwe_id = lines[0].upper()
    assert cwe_id == "CWE-22", f"Expected CWE-22 on line 1, got {lines[0]}"

    attacker_ip = lines[1]
    assert attacker_ip == "172.16.8.99", f"Expected attacker IP 172.16.8.99 on line 2, got {lines[1]}"

    malicious_file = "/home/user/secret_key.txt"
    assert os.path.isfile(malicious_file), f"Malicious file {malicious_file} is missing"

    with open(malicious_file, "rb") as mf:
        expected_hash = hashlib.sha256(mf.read()).hexdigest()

    file_hash = lines[2].lower()
    assert file_hash == expected_hash, f"Expected hash {expected_hash} on line 3, got {lines[2]}"


def test_patched_executable_exists():
    exe_path = "/home/user/upload_handler_patched"
    assert os.path.isfile(exe_path), f"Patched executable not found at {exe_path}"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Patched executable must be a compiled ELF binary"


def test_patched_executable_valid_input():
    exe_path = "/home/user/upload_handler_patched"
    test_file = "valid_test_file.txt"
    test_content = "valid_data_123"

    os.makedirs("/home/user/uploads", exist_ok=True)

    result = subprocess.run(
        [exe_path, test_file, test_content],
        cwd="/home/user",
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Expected exit code 0 for valid input, got {result.returncode}"

    output_file = f"/home/user/uploads/{test_file}"
    assert os.path.isfile(output_file), f"Expected file to be created at {output_file}"

    with open(output_file, "r") as f:
        content = f.read()
    assert content == test_content, f"Expected file content '{test_content}', got '{content}'"


def test_patched_executable_invalid_input_dotdot():
    exe_path = "/home/user/upload_handler_patched"

    result = subprocess.run(
        [exe_path, "../evil.txt", "data"],
        cwd="/home/user",
        capture_output=True,
        text=True
    )

    assert result.returncode == 1, f"Expected exit code 1 for input with '..', got {result.returncode}"
    assert "Invalid filename" in result.stderr, "Expected 'Invalid filename' in stderr"


def test_patched_executable_invalid_input_slash():
    exe_path = "/home/user/upload_handler_patched"

    result = subprocess.run(
        [exe_path, "/etc/passwd", "data"],
        cwd="/home/user",
        capture_output=True,
        text=True
    )

    assert result.returncode == 1, f"Expected exit code 1 for input with '/', got {result.returncode}"
    assert "Invalid filename" in result.stderr, "Expected 'Invalid filename' in stderr"


@pytest.fixture(scope="module")
def source_executable():
    source = "/home/user/upload_handler.c"
    assert os.path.isfile(source), f"Patched source not found at {source}"

    fd, output = tempfile.mkstemp(prefix="compiled_upload_handler_", dir="/tmp")
    os.close(fd)
    os.unlink(output)
    result = subprocess.run(
        ["gcc", source, "-o", output],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Patched source did not compile with gcc: {result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    try:
        yield output
    finally:
        if os.path.exists(output):
            os.unlink(output)


def _token(length=18):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def _remove_file(path):
    if os.path.lexists(path):
        assert not os.path.isdir(path), f"Unexpected directory at test target {path}"
        os.unlink(path)


def _assert_invalid(executable, filename, output_path):
    _remove_file(output_path)
    result = subprocess.run(
        [executable, filename, "blocked_" + _token()],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=5
    )
    assert result.returncode == 1, f"Expected exit code 1 for invalid filename {filename!r}, got {result.returncode}"
    assert "Invalid filename" in result.stderr, f"Expected 'Invalid filename' in stderr for {filename!r}"
    assert not os.path.lexists(output_path), f"Invalid filename {filename!r} wrote {output_path}"


def _exercise_randomized_behavior(executable):
    os.makedirs("/home/user/uploads", exist_ok=True)

    for _ in range(10):
        filename = "valid_" + _token() + ".txt"
        content = "content_" + _token(24)
        output = os.path.join("/home/user/uploads", filename)
        _remove_file(output)
        result = subprocess.run(
            [executable, filename, content],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=5
        )
        assert result.returncode == 0, f"Valid filename {filename!r} was rejected"
        assert os.path.isfile(output), f"Valid filename {filename!r} did not create its upload"
        with open(output, "r") as f:
            assert f.read() == content
        os.unlink(output)

    for _ in range(12):
        base = "dot_" + _token() + ".txt"
        position = secrets.randbelow(len(base) + 1)
        filename = base[:position] + ".." + base[position:]
        _assert_invalid(executable, filename, os.path.join("/home/user/uploads", filename))

    for _ in range(12):
        parent = "dir_" + _token(12)
        leaf = "file_" + _token(12) + ".txt"
        os.makedirs(os.path.join("/home/user/uploads", parent), exist_ok=True)
        filename = parent + "/" + leaf
        _assert_invalid(executable, filename, os.path.join("/home/user/uploads", parent, leaf))

    for _ in range(8):
        leaf = "outside_" + _token(14) + ".txt"
        filename = "../" + leaf
        _assert_invalid(executable, filename, os.path.join("/home/user", leaf))


def test_randomized_patched_binary_behavior():
    _exercise_randomized_behavior("/home/user/upload_handler_patched")


def test_patched_source_behavior(source_executable):
    _exercise_randomized_behavior(source_executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
