#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

BINARY = "/home/user/auth_service_fixed"
SOURCE = "/home/user/auth_service.c"
EXPECTED = "Cookie: session=x9f8c7b6a5d4e3f2g1h0"


def run_auth(cookie_marker, args=()):
    env = os.environ.copy()
    if cookie_marker is None:
        env.pop("AUTH_COOKIE", None)
    else:
        env["AUTH_COOKIE"] = cookie_marker
    return subprocess.run(
        [BINARY, *args], env=env, capture_output=True, text=True, timeout=5
    )


def test_leaked_token():
    token_file = "/home/user/leaked_token.txt"
    assert os.path.exists(token_file), f"File {token_file} does not exist."
    with open(token_file, "r") as f:
        content = f.read().strip()
    assert content == "x9f8c7b6a5d4e3f2g1h0", f"Leaked token is incorrect. Expected 'x9f8c7b6a5d4e3f2g1h0', got '{content}'."


def test_binary_exists():
    assert os.path.isfile(BINARY), f"Binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "auth_service_fixed must be a compiled ELF executable."


def test_source_exists_and_binary_was_compiled_from_it():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    # Ignore comments and literals when checking that the original argv parameter
    # is not referenced outside its declaration.
    cleaned = re.sub(
        r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        " ",
        source,
        flags=re.S,
    )
    assert len(re.findall(r"\bargv\b", cleaned)) <= 1, "auth_service.c still reads or uses argv."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "auth_service_fixed")
        result = subprocess.run(
            ["/usr/bin/gcc", SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"auth_service.c does not compile with gcc: {result.stderr}"
        with open(rebuilt, "rb") as f:
            rebuilt_bytes = f.read()
        with open(BINARY, "rb") as f:
            submitted_bytes = f.read()
        assert submitted_bytes == rebuilt_bytes, "auth_service_fixed was not compiled from the submitted auth_service.c using the required gcc command."


def test_binary_no_cookie():
    result = run_auth(None)
    assert result.returncode == 1, f"Expected exit code 1 when no cookie is provided, got {result.returncode}."
    assert "Error: No cookie" in result.stdout, f"Expected 'Error: No cookie' in stdout, got '{result.stdout}'."


def test_binary_correct_cookie():
    result = run_auth(EXPECTED)
    assert result.returncode == 0, f"Expected exit code 0 with correct cookie, got {result.returncode}."
    assert "Authentication successful." in result.stdout, f"Expected 'Authentication successful.' in stdout, got '{result.stdout}'."


def test_binary_incorrect_cookie():
    result = run_auth("Cookie: session=wrong_token_here")
    assert result.returncode == 1, f"Expected exit code 1 with incorrect cookie, got {result.returncode}."
    assert "Authentication failed." in result.stdout, f"Expected 'Authentication failed.' in stdout, got '{result.stdout}'."


def test_authentication_depends_only_on_environment():
    random_args = [secrets.token_urlsafe(17), EXPECTED, secrets.token_hex(19)]

    # argv must not authenticate when AUTH_COOKIE is absent.
    result = run_auth(None, random_args)
    assert result.returncode == 1
    assert result.stdout == "Error: No cookie\n"

    # A valid environment cookie must succeed regardless of conflicting argv.
    for _ in range(6):
        args = ["Cookie: session=" + secrets.token_urlsafe(24), secrets.token_hex(13)]
        result = run_auth(EXPECTED, args)
        assert result.returncode == 0
        assert result.stdout == "Authentication successful.\n"

    # Random invalid environment cookies must fail even when argv contains the
    # valid cookie. Values are generated at verification time, not fixed cases.
    invalid = ["", EXPECTED + "x", "x" + EXPECTED]
    invalid.extend("Cookie: session=" + secrets.token_urlsafe(24) for _ in range(12))
    for cookie in invalid:
        assert cookie != EXPECTED
        result = run_auth(cookie, [EXPECTED, secrets.token_hex(11)])
        assert result.returncode == 1
        assert result.stdout == "Authentication failed.\n"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
