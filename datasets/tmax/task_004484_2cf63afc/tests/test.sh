#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import pytest

ORIGINAL_TRAFFIC = """GET /api/v1/users HTTP/1.1
Host: api.example.com
Authorization: Bearer 1a2b3c4d5e6f7a8b9c0d1a2b3c4d5e6f7a8b9c0d1a2b3c4d5e6f7a8b9c0d1a2b
Accept: application/json

POST /api/v1/update HTTP/1.1
Host: api.example.com
Authorization: Bearer ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
Content-Type: application/json

{\"status\": \"active\"}

GET /public/info HTTP/1.1
Host: api.example.com
Accept: */*
"""


def derived_pin():
    matches = [pin for pin in range(10000) if (pin * 12345) % 98765 == 61850]
    assert len(matches) == 1, f"Expected one mathematical solution, found {matches}."
    return f"{matches[0]:04d}"


def test_cracked_pin():
    """Check if the cracked PIN is correctly found and saved."""
    pin_file = "/home/user/cracked_pin.txt"
    assert os.path.isfile(pin_file), f"File {pin_file} is missing."

    with open(pin_file, 'r') as f:
        content = f.read().strip()

    assert content == "3133", f"Expected PIN '3133', but got '{content}' in {pin_file}."
    assert content == derived_pin(), "The saved PIN does not satisfy the supplied equation."


def test_crack_c_exists():
    """Check if the C program source file exists."""
    c_file = "/home/user/crack.c"
    assert os.path.isfile(c_file), f"C program file {c_file} is missing."


def test_crack_c_compiles_and_finds_pin():
    """Compile and execute the submitted C artifact and verify its result."""
    c_file = "/home/user/crack.c"
    pin_file = "/home/user/cracked_pin.txt"
    assert os.path.isfile(c_file), f"C program file {c_file} is missing."
    assert os.path.isfile(pin_file), f"File {pin_file} is missing."

    with open(pin_file, "rb") as f:
        saved_pin = f.read()
    saved_mode = stat.S_IMODE(os.stat(pin_file).st_mode)
    expected = derived_pin()

    with tempfile.TemporaryDirectory() as tmpdir:
        executable = os.path.join(tmpdir, "crack")
        compiled = subprocess.run(
            ["gcc", "-std=c11", "-O2", c_file, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, f"crack.c did not compile:\n{compiled.stderr}"
        assert os.path.isfile(executable) and os.access(executable, os.X_OK), \
            "Compilation did not produce an executable."

        os.remove(pin_file)
        try:
            ran = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert ran.returncode == 0, \
                f"Compiled crack program failed with code {ran.returncode}:\n{ran.stderr}"

            reported = []
            if os.path.isfile(pin_file):
                with open(pin_file, "r") as f:
                    reported.append(f.read().strip())
            reported.extend(re.findall(r"(?<!\d)\d{4}(?!\d)", ran.stdout))

            assert expected in reported, \
                f"The executed C program did not produce the derived PIN {expected}. stdout was: {ran.stdout!r}"
        finally:
            with open(pin_file, "wb") as f:
                f.write(saved_pin)
            os.chmod(pin_file, saved_mode)


def test_redacted_log_exists_and_permissions():
    """Check if the redacted.log exists and has 0400 permissions."""
    log_file = "/home/user/redacted.log"
    assert os.path.isfile(log_file), f"File {log_file} is missing."

    file_stat = os.stat(log_file)
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o400, f"Expected permissions 0400 for {log_file}, but got {oct(permissions)}."


def test_redacted_log_content():
    """Check if the sensitive tokens are redacted correctly in redacted.log."""
    log_file = "/home/user/redacted.log"
    assert os.path.isfile(log_file), f"File {log_file} is missing."

    with open(log_file, 'r') as f:
        content = f.read()

    # Check that REDACTED was inserted
    assert "Authorization: Bearer REDACTED" in content, \
        "The string 'Authorization: Bearer REDACTED' was not found in the redacted log."

    # Check that no 64-character hex strings remain after Bearer
    unredacted_match = re.search(r"Bearer [0-9a-fA-F]{64}", content)
    assert unredacted_match is None, \
        f"Found unredacted token in {log_file}: {unredacted_match.group(0)}"

    expected = re.sub(
        r"(?<=Authorization: Bearer )[0-9a-fA-F]{64}",
        "REDACTED",
        ORIGINAL_TRAFFIC,
    )
    assert content == expected, \
        "redacted.log must preserve the complete traffic log and replace every bearer token only."
    assert content.count("Authorization: Bearer REDACTED") == 2, \
        "Both authorization tokens must be redacted."


def test_redacted_log_preserves_other_content():
    """Ensure that the rest of the log content is preserved."""
    log_file = "/home/user/redacted.log"
    assert os.path.isfile(log_file), f"File {log_file} is missing."

    with open(log_file, 'r') as f:
        content = f.read()

    assert "GET /api/v1/users HTTP/1.1" in content, "Missing original content 'GET /api/v1/users HTTP/1.1'."
    assert "POST /api/v1/update HTTP/1.1" in content, "Missing original content 'POST /api/v1/update HTTP/1.1'."
    assert '{"status": "active"}' in content, "Missing original JSON payload."
    assert "GET /public/info HTTP/1.1" in content, "Missing original content 'GET /public/info HTTP/1.1'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
