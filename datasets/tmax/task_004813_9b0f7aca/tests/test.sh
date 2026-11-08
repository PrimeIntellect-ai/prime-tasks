#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import string
import subprocess
import tempfile
import pytest

APP_DIR = "/home/user/legacy_auth_app"
SOURCE_PATH = os.path.join(APP_DIR, "app.c")
CGI_PATH = os.path.join(APP_DIR, "auth_app.cgi")
INVALID_OUTPUT = "<html><body>Invalid input</body></html>"


def run_app(path, query, timeout=5):
    env = os.environ.copy()
    if query is None:
        env.pop("QUERY_STRING", None)
    else:
        env["QUERY_STRING"] = query
    return subprocess.run(
        [path], env=env, capture_output=True, text=True, timeout=timeout
    )


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Compiled CGI application not found at {path}"
    assert os.access(path, os.X_OK), f"CGI application at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"CGI application at {path} is not a compiled ELF executable"


def test_audit_report():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert len(lines) >= 3, f"Audit report must contain at least 3 lines, found {len(lines)}"
    assert lines[0] == "CWE-79", f"Line 1 (XSS CWE) is incorrect: {lines[0]}"
    assert lines[1] in ["CWE-77", "CWE-78"], f"Line 2 (Command Injection CWE) is incorrect: {lines[1]}"
    assert lines[2] in ["666", "0666"], f"Line 3 (Initial permissions) is incorrect: {lines[2]}"


def test_credentials_rotated_and_permissions():
    creds_path = os.path.join(APP_DIR, "creds.conf")
    assert os.path.isfile(creds_path), f"Credentials file missing at {creds_path}"

    with open(creds_path, "r") as f:
        content = f.read()

    assert "DB_PASS=SuperSecretRotate99!" in content, "Credentials were not rotated correctly in creds.conf"

    st = os.stat(creds_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Permissions on creds.conf are incorrect. Expected 0600, got {oct(perms)}"


def test_compiled_cgi_functionality():
    assert_elf_executable(CGI_PATH)

    env = os.environ.copy()
    env["QUERY_STRING"] = "username=admin123"
    result_valid = subprocess.run([CGI_PATH], env=env, capture_output=True, text=True, timeout=5)
    assert "Invalid input" not in result_valid.stdout, "Valid input was incorrectly rejected."

    env["QUERY_STRING"] = "username=admin;"
    result_invalid = subprocess.run([CGI_PATH], env=env, capture_output=True, text=True, timeout=5)
    assert result_invalid.returncode == 1, f"Expected exit code 1 for invalid input, got {result_invalid.returncode}"
    assert INVALID_OUTPUT in result_invalid.stdout, "CGI did not print correct invalid input message for non-alphanumeric input."

    env["QUERY_STRING"] = "username="
    result_empty = subprocess.run([CGI_PATH], env=env, capture_output=True, text=True, timeout=5)
    assert result_empty.returncode == 1, f"Expected exit code 1 for empty username, got {result_empty.returncode}"
    assert INVALID_OUTPUT in result_empty.stdout, "CGI did not print correct invalid input message for empty username."

    env["QUERY_STRING"] = "otherparam=123"
    result_missing = subprocess.run([CGI_PATH], env=env, capture_output=True, text=True, timeout=5)
    assert result_missing.returncode == 1, f"Expected exit code 1 for missing username, got {result_missing.returncode}"
    assert INVALID_OUTPUT in result_missing.stdout, "CGI did not print correct invalid input message for missing username."


def exercise_strict_behavior(path):
    alphabet = string.ascii_letters + string.digits
    valid_names = [
        "A",
        "z9",
        "".join(secrets.choice(alphabet) for _ in range(19)),
        "".join(secrets.choice(alphabet) for _ in range(47)),
    ]

    marker = f"/tmp/auth_injection_{secrets.token_hex(12)}"
    invalid_queries = [
        None,
        "",
        "otherparam=" + secrets.token_hex(8),
        "username=",
        "username=" + secrets.token_hex(5) + ";touch " + marker,
        "username=<script>alert(1)</script>",
        "username=user_name",
        "username=user-name",
        "username=user%20name",
        "username=user&role=admin",
        "USERNAME=admin",
    ]

    for query in invalid_queries:
        try:
            os.unlink("/tmp/auth.log")
        except FileNotFoundError:
            pass
        result = run_app(path, query)
        assert result.returncode == 1, f"Invalid query {query!r} returned {result.returncode}"
        assert result.stdout == INVALID_OUTPUT, (
            f"Invalid query {query!r} must produce exactly {INVALID_OUTPUT!r}; got {result.stdout!r}"
        )
        assert result.stderr == "", f"Invalid query {query!r} unexpectedly wrote to stderr"
        assert not os.path.exists("/tmp/auth.log"), f"Invalid query {query!r} was logged or executed"

    assert not os.path.exists(marker), "Command-injection payload was executed"

    for username in valid_names:
        try:
            os.unlink("/tmp/auth.log")
        except FileNotFoundError:
            pass
        result = run_app(path, "username=" + username)
        expected_stdout = (
            "Content-Type: text/html\n\n"
            f"<html><body>Login failed for user: {username}</body></html>\n"
        )
        assert result.returncode == 0, f"Valid username {username!r} returned {result.returncode}"
        assert result.stdout == expected_stdout, (
            f"Valid username {username!r} did not produce normal CGI output: {result.stdout!r}"
        )
        assert result.stderr == "", f"Valid username {username!r} unexpectedly wrote to stderr"
        assert os.path.isfile("/tmp/auth.log"), "Valid login attempt was not logged"
        with open("/tmp/auth.log", "r") as f:
            log_content = f.read()
        assert log_content == f"Login attempt for {username}\n", (
            f"Unexpected login record for valid username {username!r}: {log_content!r}"
        )


def test_submitted_binary_strict_randomized_behavior():
    assert_elf_executable(CGI_PATH)
    exercise_strict_behavior(CGI_PATH)


def test_patched_source_recompiles_and_has_strict_randomized_behavior():
    assert os.path.isfile(SOURCE_PATH), f"Patched source not found at {SOURCE_PATH}"
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "auth_app_from_source")
        compile_result = subprocess.run(
            ["gcc", SOURCE_PATH, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"Patched app.c did not compile successfully:\n{compile_result.stderr}"
        )
        assert_elf_executable(rebuilt)
        exercise_strict_behavior(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
