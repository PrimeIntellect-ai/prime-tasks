#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import string
import subprocess

import pytest

SOURCE = "/home/user/rotate.c"
OUTPUT = "/home/user/new_creds.json"
BINARY = "/tmp/rotate_verifier_bin"
RECOVERED_KEY = "SecureKey2023!"


def expected_json(key):
    digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
    return '{"status": "rotated", "new_key": "' + digest + '"}'


def assert_strict_output(key):
    assert os.path.exists(OUTPUT), f"The output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"The path {OUTPUT} exists but is not a file."
    with open(OUTPUT, "rb") as f:
        actual = f.read()
    expected = expected_json(key).encode("ascii")
    assert actual == expected, f"Expected strict JSON bytes {expected!r}, got {actual!r}."


def run_rotate(key):
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    return subprocess.run(
        [BINARY, key],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def test_rotate_c_exists():
    path = SOURCE
    assert os.path.exists(path), f"The C program {path} is missing."
    assert os.path.isfile(path), f"The path {path} exists but is not a file."

    with open(path, "r") as f:
        content = f.read()
    assert "main" in content, f"The file {path} does not appear to be a valid C program."


def test_new_creds_json_correct():
    path = OUTPUT
    assert os.path.exists(path), f"The output file {path} is missing."
    assert os.path.isfile(path), f"The path {path} exists but is not a file."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {path} does not contain valid JSON.")

    assert "status" in data, f"The JSON in {path} is missing the 'status' key."
    assert data["status"] == "rotated", f"Expected 'status' to be 'rotated', got '{data['status']}'."

    assert "new_key" in data, f"The JSON in {path} is missing the 'new_key' key."

    expected_hash = hashlib.sha256(RECOVERED_KEY.encode("utf-8")).hexdigest()
    actual_hash = data["new_key"]
    assert actual_hash == expected_hash, f"Expected 'new_key' to be '{expected_hash}', but got '{actual_hash}'."

    assert_strict_output(RECOVERED_KEY)


def test_compile_and_execute_recovered_key():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", BINARY, "-lcrypto"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, compile_result.stderr.decode("utf-8", "replace")
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compilation did not produce an executable."

    result = run_rotate(RECOVERED_KEY)
    assert result.returncode == 0, f"rotate exited with {result.returncode}: {result.stderr.decode('utf-8', 'replace')}"
    assert_strict_output(RECOVERED_KEY)


def test_sha256_for_unpredictable_valid_inputs():
    allowed = string.ascii_letters + string.digits + "!@#$"
    for _ in range(4):
        key = "T" + "".join(secrets.choice(allowed) for _ in range(31))
        result = run_rotate(key)
        assert result.returncode == 0, f"Valid input was rejected with exit code {result.returncode}."
        assert_strict_output(key)


def test_illegal_characters_exit_with_code_one():
    allowed = string.ascii_letters + string.digits + "!@#$"
    for illegal in ["%", "_", "'", " ", "/", ";"]:
        prefix = "".join(secrets.choice(allowed) for _ in range(12))
        suffix = "".join(secrets.choice(allowed) for _ in range(12))
        result = run_rotate(prefix + illegal + suffix)
        assert result.returncode == 1, (
            f"Input containing illegal character {illegal!r} must exit with code 1, "
            f"but exited with {result.returncode}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
