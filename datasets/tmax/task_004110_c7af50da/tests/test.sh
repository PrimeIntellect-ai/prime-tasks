#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import subprocess
import tempfile
import pytest

AUDIT_DIR = "/home/user/audit"
EXECUTABLE = os.path.join(AUDIT_DIR, "auth_helper_fixed")
SOURCE = os.path.join(AUDIT_DIR, "auth_helper.c")
REPORT = os.path.join(AUDIT_DIR, "report.txt")
SERVER_CERT = os.path.join(AUDIT_DIR, "server.crt")
CA_CERT = os.path.join(AUDIT_DIR, "ca.crt")


def run_helper(path, auth_pass_marker, args=()):
    env = os.environ.copy()
    if auth_pass_marker is None:
        env.pop("AUTH_PASS", None)
    else:
        env["AUTH_PASS"] = auth_pass_marker
    try:
        return subprocess.run(
            [path, *args], env=env, capture_output=True, text=True, timeout=5
        )
    except Exception as exc:
        pytest.fail(f"Failed to execute {path}: {exc}")


def assert_success(path, secret, args=()):
    result = run_helper(path, secret, args)
    assert result.returncode == 0, (
        f"Expected exit code 0 when AUTH_PASS is set, got {result.returncode}."
    )
    expected = f"Processing with secret: {secret}\n"
    assert result.stdout == expected, (
        f"Unexpected output. Expected {expected!r}, got {result.stdout!r}."
    )
    assert result.stderr == "", f"Unexpected stderr: {result.stderr!r}"


def assert_missing_or_empty_fails(path, value, args=()):
    result = run_helper(path, value, args)
    assert result.returncode == 1, (
        f"Expected exit code 1 for missing/empty AUTH_PASS, got {result.returncode}."
    )
    assert result.stdout == "", f"Unexpected stdout on failure: {result.stdout!r}"
    assert result.stderr == "", f"Unexpected stderr on failure: {result.stderr!r}"


def test_auth_helper_fixed_exists_and_executable():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "auth_helper_fixed is not a compiled ELF executable."


def test_auth_helper_fixed_behavior_with_env_var():
    # Preserve the original behavioral assertion.
    assert_success(EXECUTABLE, "verify_pass_123")

    # Unpredictable inputs prevent a fixed-output implementation from passing.
    for _ in range(4):
        assert_success(EXECUTABLE, "audit_" + secrets.token_urlsafe(24))
    assert_success(EXECUTABLE, "secret with spaces %s %n !@#$")


def test_auth_helper_fixed_behavior_without_env_var():
    # Preserve the original missing-variable assertion and also cover empty values.
    assert_missing_or_empty_fails(EXECUTABLE, None)
    assert_missing_or_empty_fails(EXECUTABLE, "")


def test_argv_is_not_used_as_the_password():
    decoy = "argv_secret_" + secrets.token_urlsafe(20)
    env_secret = "env_secret_" + secrets.token_urlsafe(20)

    # AUTH_PASS must win even when password-like argv values are supplied.
    assert_success(EXECUTABLE, env_secret, (decoy, "another-argument"))

    # Supplying a secret only through argv must not make the program succeed.
    assert_missing_or_empty_fails(EXECUTABLE, None, (decoy,))
    assert_missing_or_empty_fails(EXECUTABLE, "", (decoy,))


def test_modified_source_compiles_and_has_required_behavior():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "auth_helper_rebuilt")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"Modified auth_helper.c does not compile with gcc:\n{compile_result.stderr}"
        )

        for _ in range(3):
            secret = "source_test_" + secrets.token_urlsafe(24)
            decoy = "argv_decoy_" + secrets.token_urlsafe(12)
            assert_success(rebuilt, secret, (decoy,))
        assert_missing_or_empty_fails(rebuilt, None, ("argv_only_secret",))
        assert_missing_or_empty_fails(rebuilt, "", ("argv_only_secret",))


def test_report_exists_and_format_and_findings_are_correct():
    assert os.path.isfile(REPORT), f"Report file {REPORT} is missing."
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(SERVER_CERT), f"Certificate {SERVER_CERT} is missing."
    assert os.path.isfile(CA_CERT), f"CA certificate {CA_CERT} is missing."

    with open(REPORT, "r", encoding="utf-8") as handle:
        raw_lines = handle.read().splitlines()
    assert len(raw_lines) == 3, f"Expected exactly 3 lines in {REPORT}, found {len(raw_lines)}."
    assert all(line == line.strip() and line for line in raw_lines), (
        "Report lines must be nonempty and contain no surrounding whitespace."
    )

    # Preserve the original CWE assertion.
    assert raw_lines[0].upper() == "CWE-214", (
        f"Line 1 should be 'CWE-214', got {raw_lines[0]!r}."
    )
    assert raw_lines[0] == "CWE-214", "Line 1 must use the exact requested spelling."

    # Derive the certificate result by actually asking OpenSSL to validate the chain.
    verify_result = subprocess.run(
        ["openssl", "verify", "-CAfile", CA_CERT, SERVER_CERT],
        capture_output=True,
        text=True,
        timeout=10,
    )
    expected_certificate_result = "VALID" if verify_result.returncode == 0 else "INVALID"
    assert raw_lines[1] == expected_certificate_result, (
        "Line 2 does not match OpenSSL certificate validation; "
        f"expected {expected_certificate_result}, got {raw_lines[1]!r}. "
        f"OpenSSL output: {verify_result.stdout}{verify_result.stderr}"
    )
    # Preserve the original expected result for the supplied certificate chain.
    assert raw_lines[1].upper() == "VALID", (
        f"Line 2 should be 'VALID', got {raw_lines[1]!r}."
    )

    with open(SOURCE, "rb") as handle:
        expected_hash = hashlib.sha256(handle.read()).hexdigest()
    assert raw_lines[2].lower() == expected_hash.lower(), (
        f"Line 3 should be the SHA-256 hash of auth_helper.c ({expected_hash}), "
        f"got {raw_lines[2]!r}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
