#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile
import pytest

HOME_DIR = "/home/user"
LOGS_DIR = os.path.join(HOME_DIR, "logs")
AUTH_LOG = os.path.join(LOGS_DIR, "auth.log")
AUTH_CLEAN_LOG = os.path.join(LOGS_DIR, "auth_clean.log")
SUCCESS_TXT = os.path.join(HOME_DIR, "success.txt")
KEYGEN_C = os.path.join(HOME_DIR, "keygen.c")
KEYGEN_BIN = os.path.join(HOME_DIR, "keygen")
LEGACY_AUTH = os.path.join(HOME_DIR, "legacy_auth")

SALT = "wX9kP2mR4vLz"
EXPECTED_SUCCESS = "ACCESS GRANTED. FLAG: DEVSEC_POLICY_ENFORCED_99\n"
ORIGINAL_LOG = """[INFO] User admin logged in.
[DEBUG] Token validation failed. Salt used was wX9kP2mR4vLz
[INFO] User test failed login.
[DEBUG] Initialization complete. Loaded salt: wX9kP2mR4vLz
"""


def expected_token(username):
    return "".join(
        f"{ord(c) ^ ord(SALT[i % len(SALT)]):02x}"
        for i, c in enumerate(username)
    )


def run_keygen(path, username):
    result = subprocess.run(
        [path, username], capture_output=True, text=True, timeout=2
    )
    assert result.returncode == 0, (
        f"{path} failed for username {username!r}: {result.stderr}"
    )
    assert result.stdout.strip() == expected_token(username), (
        f"Keygen output incorrect for username {username!r}. "
        f"Expected {expected_token(username)!r}, got {result.stdout.strip()!r}."
    )


def test_success_txt_exists_and_content():
    assert os.path.isfile(SUCCESS_TXT), f"File not found: {SUCCESS_TXT}"
    with open(SUCCESS_TXT, "r") as f:
        content = f.read().strip()

    expected = "ACCESS GRANTED. FLAG: DEVSEC_POLICY_ENFORCED_99"
    assert content == expected, f"Content of {SUCCESS_TXT} is incorrect. Expected '{expected}', got '{content}'."


def test_auth_clean_log_exists_and_content():
    assert os.path.isfile(AUTH_CLEAN_LOG), f"File not found: {AUTH_CLEAN_LOG}"

    with open(AUTH_CLEAN_LOG, "r") as f:
        content = f.read()

    expected_lines = [
        "[INFO] User admin logged in.",
        "[DEBUG] Token validation failed. Salt used was [REDACTED]",
        "[INFO] User test failed login.",
        "[DEBUG] Initialization complete. Loaded salt: [REDACTED]"
    ]

    for line in expected_lines:
        assert line in content, f"Expected redacted log line '{line}' not found in {AUTH_CLEAN_LOG}."

    assert SALT not in content, f"The secret salt '{SALT}' was found in {AUTH_CLEAN_LOG}, it should be redacted."

    with open(AUTH_LOG, "r") as f:
        original = f.read()
    assert original == ORIGINAL_LOG, "The original auth.log was modified."
    assert content == original.replace(SALT, "[REDACTED]"), (
        "auth_clean.log must preserve the complete source log and replace every salt occurrence exactly."
    )


def test_keygen_exists_and_functional():
    assert os.path.isfile(KEYGEN_C), f"C source file not found: {KEYGEN_C}"
    assert os.path.isfile(KEYGEN_BIN), f"Compiled binary not found: {KEYGEN_BIN}"
    assert os.access(KEYGEN_BIN, os.X_OK), f"File is not executable: {KEYGEN_BIN}"
    with open(KEYGEN_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{KEYGEN_BIN} is not a compiled ELF executable."

    # Preserve the original fixed functional assertion.
    run_keygen(KEYGEN_BIN, "testuser")

    # Exercise wrapping and arbitrary usernames selected only at verification time.
    alphabet = string.ascii_letters + string.digits + "_-"
    usernames = [
        "".join(secrets.choice(alphabet) for _ in range(length))
        for length in (1, 11, 12, 13, 29, 47)
    ]
    for username in usernames:
        run_keygen(KEYGEN_BIN, username)

    # Compile the submitted source independently and apply the same dynamic tests,
    # ensuring keygen.c is valid C and implements the behavior of the executable.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "keygen_rebuilt")
        build = subprocess.run(
            ["gcc", KEYGEN_C, "-o", rebuilt],
            capture_output=True, text=True, timeout=10
        )
        assert build.returncode == 0, f"keygen.c failed to compile with gcc: {build.stderr}"
        for username in ["testuser"] + usernames:
            run_keygen(rebuilt, username)


def test_real_authentication_flow_matches_success_file():
    username = "sysadmin_prod"
    generated = subprocess.run(
        [KEYGEN_BIN, username], capture_output=True, text=True, timeout=2
    )
    assert generated.returncode == 0, f"keygen failed: {generated.stderr}"
    token = generated.stdout.strip()
    assert token == expected_token(username), "keygen produced an invalid sysadmin_prod token."

    auth = subprocess.run(
        [LEGACY_AUTH, f"{username}:{token}"],
        capture_output=True, text=True, timeout=2
    )
    assert auth.returncode == 0, f"legacy_auth rejected the generated credential: {auth.stdout}{auth.stderr}"
    assert auth.stdout == EXPECTED_SUCCESS, "legacy_auth did not produce the exact successful output."

    with open(SUCCESS_TXT, "r") as f:
        saved = f.read()
    assert saved == auth.stdout, "success.txt is not the exact stdout of the successful authentication run."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
