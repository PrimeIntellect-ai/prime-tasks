#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess
import tempfile

import pytest

APP_DIR = "/home/user/audit_app"
SOURCE_PATH = os.path.join(APP_DIR, "logger.cpp")
LOGGER_PATH = os.path.join(APP_DIR, "logger")


def test_cwe_report():
    """Verify that cwe_report.txt contains the correct CWE ID."""
    report_path = os.path.join(APP_DIR, "cwe_report.txt")
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, "r") as f:
        first_line = f.readline().strip()

    assert first_line == "CWE-134", f"Expected CWE-134 in {report_path}, found: {first_line}"


def test_logger_code_fix():
    """Verify that logger.cpp has been fixed to prevent the format string vulnerability."""
    code_path = SOURCE_PATH
    assert os.path.isfile(code_path), f"File {code_path} is missing."

    with open(code_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "snprintf(buffer, sizeof(buffer), argv[1]);" not in content, \
        "The vulnerable snprintf call is still present in logger.cpp."
    assert "%s" in content, "The fix should utilize a safe format string like '%s'."


def _exercise_logger(executable):
    random_marker = secrets.token_hex(24)
    inputs = [
        "USER_ACTION: Admin logged in",
        f"AUDIT_{random_marker}_%s_%x_%p_%n_%%",
        f"{random_marker} %08x %999s END",
    ]

    for supplied_text in inputs:
        with tempfile.TemporaryDirectory() as run_dir:
            result = subprocess.run(
                [executable, supplied_text],
                cwd=run_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Logger failed for a valid input (exit {result.returncode}): "
                f"{result.stderr.decode(errors='replace')}"
            )

            output_path = os.path.join(run_dir, "raw_audit.log")
            assert os.path.isfile(output_path), \
                "Logger did not create raw_audit.log in its working directory."
            with open(output_path, "rb") as output_file:
                actual = output_file.read()
            expected = supplied_text.encode("utf-8") + b"\n"
            assert actual == expected, (
                "Logger did not preserve user input literally; format directives may "
                "still be interpreted."
            )


def test_submitted_logger_is_built_and_safe():
    """Compile the submitted source and exercise both it and the required artifact."""
    assert os.path.isfile(SOURCE_PATH), f"File {SOURCE_PATH} is missing."

    logger_stat = os.lstat(LOGGER_PATH)
    assert stat.S_ISREG(logger_stat.st_mode), \
        f"{LOGGER_PATH} must be a regular compiled executable."
    assert os.access(LOGGER_PATH, os.X_OK), f"{LOGGER_PATH} is not executable."
    with open(LOGGER_PATH, "rb") as logger_file:
        assert logger_file.read(4) == b"\x7fELF", \
            f"{LOGGER_PATH} is not a compiled ELF executable."

    with tempfile.TemporaryDirectory() as build_dir:
        rebuilt_logger = os.path.join(build_dir, "logger_from_source")
        build = subprocess.run(
            ["g++", "-std=c++17", SOURCE_PATH, "-o", rebuilt_logger],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"logger.cpp did not compile with g++: {build.stderr}"

        _exercise_logger(rebuilt_logger)
        _exercise_logger(LOGGER_PATH)


def test_secure_audit_permissions():
    """Verify that secure_audit.enc has exactly 0400 permissions."""
    enc_path = os.path.join(APP_DIR, "secure_audit.enc")
    assert os.path.isfile(enc_path), f"File {enc_path} is missing."

    file_stat = os.stat(enc_path)
    permissions = stat.S_IMODE(file_stat.st_mode)

    assert permissions == 0o400, f"Expected permissions 0400 for {enc_path}, but got {oct(permissions)}."


def test_raw_audit_deleted():
    """Verify that the plaintext raw_audit.log has been deleted."""
    raw_path = os.path.join(APP_DIR, "raw_audit.log")
    assert not os.path.exists(raw_path), f"Plaintext log {raw_path} still exists and was not deleted."


def test_encryption_correctness():
    """Verify that secure_audit.enc decrypts to the expected plaintext using the derived key and IV."""
    enc_path = os.path.join(APP_DIR, "secure_audit.enc")
    assert os.path.isfile(enc_path), f"File {enc_path} is missing."

    token = "COMPLIANCE_TOKEN_2024"
    key = hashlib.sha256(token.encode("utf-8")).hexdigest()
    iv = "00000000000000000000000000000000"

    cmd = [
        "openssl", "enc", "-aes-256-cbc", "-d",
        "-in", enc_path,
        "-K", key,
        "-iv", iv,
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=10)
        decrypted_text = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to decrypt {enc_path}. Openssl error: {e.stderr}")

    expected_content = "USER_ACTION: Admin logged in\n"
    assert decrypted_text == expected_content, \
        f"Decrypted content did not match. Expected '{expected_content}', got '{decrypted_text}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
