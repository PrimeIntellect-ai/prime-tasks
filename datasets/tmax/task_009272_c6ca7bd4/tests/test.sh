#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import pytest

SOURCE = "/home/user/forge.c"
BINARY = "/home/user/forge"
TOKEN_CHECK = "/home/user/token_check"
REBUILT = "/tmp/forge_rebuilt_from_source"
SECRET_KEY = "Sup3rS3cr3tM4st3rK3y"


def expected_token(username):
    return str((sum(ord(c) for c in username) + sum(ord(c) for c in SECRET_KEY)) % 256)


def run_program(path, username):
    return subprocess.run(
        [path, username], capture_output=True, text=True, timeout=5
    )


@pytest.fixture(scope="session")
def rebuilt_binary():
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", REBUILT],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"forge.c did not compile:\n{result.stderr}"
    assert os.path.isfile(REBUILT)
    assert os.access(REBUILT, os.X_OK)
    with open(REBUILT, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled forge.c did not produce an ELF executable."
    return REBUILT


def test_admin_token_file():
    token_file = "/home/user/admin_token.txt"
    assert os.path.exists(token_file), f"{token_file} does not exist."
    assert os.path.isfile(token_file), f"{token_file} is not a file."
    with open(token_file, "rb") as f:
        content = f.read()
    expected = expected_token("admin").encode("ascii")
    assert content == expected, (
        f"{token_file} must contain exactly the admin token with no newline; "
        f"expected {expected!r}, got {content!r}."
    )


def test_forge_c_exists():
    assert os.path.exists(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."


def test_forge_executable_exists():
    assert os.path.exists(BINARY), f"{BINARY} does not exist."
    assert os.path.isfile(BINARY), f"{BINARY} is not a file."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."


def test_fixed_and_unpredictable_usernames(rebuilt_binary):
    alphabet = string.ascii_letters + string.digits
    usernames = ["admin", "guest"]
    usernames.extend(
        "audit_" + "".join(secrets.choice(alphabet) for _ in range(20))
        for _ in range(16)
    )

    for username in usernames:
        expected = expected_token(username)

        validator = run_program(TOKEN_CHECK, username)
        # run_program supplies only one argument after the path, so validate separately.
        validator = subprocess.run(
            [TOKEN_CHECK, username, expected],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert validator.returncode == 0, (
            f"The original token_check no longer accepts the expected token for {username!r}."
        )

        submitted = run_program(BINARY, username)
        assert submitted.returncode == 0, f"Running {BINARY} for {username!r} failed."
        assert submitted.stdout.strip() == expected, (
            f"Incorrect token from {BINARY} for {username!r}: "
            f"expected {expected!r}, got {submitted.stdout.strip()!r}."
        )

        rebuilt = run_program(rebuilt_binary, username)
        assert rebuilt.returncode == 0, f"Compiled forge.c failed for {username!r}."
        assert rebuilt.stdout.strip() == expected, (
            f"Compiled forge.c produced an incorrect token for {username!r}: "
            f"expected {expected!r}, got {rebuilt.stdout.strip()!r}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
