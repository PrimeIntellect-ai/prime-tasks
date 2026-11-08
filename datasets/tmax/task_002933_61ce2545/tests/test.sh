#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import subprocess
import pytest

EXPECTED_MD5 = "9a0364b9e99bb480dd25e1f0284c8555"

def test_verify_script_exists_and_executable():
    path = "/home/user/verify.sh"
    assert os.path.isfile(path), f"Missing required file: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"

def test_dropper_script_exists_and_executable():
    path = "/home/user/dropper.sh"
    assert os.path.isfile(path), f"Missing required file: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"

def test_verify_script_execution():
    path = "/home/user/verify.sh"
    try:
        result = subprocess.run([path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"verify.sh failed with exit code {result.returncode}. STDOUT: {result.stdout} STDERR: {result.stderr}"
    except subprocess.TimeoutExpired:
        pytest.fail("verify.sh execution timed out.")
    except Exception as e:
        pytest.fail(f"Failed to execute verify.sh: {e}")

def test_payload_bin_exists():
    path = "/home/user/payload.bin"
    assert os.path.isfile(path), f"Missing required file: {path}. The dropper.sh script should have created it."

def test_dropper_independently_produces_expected_payload():
    dropper = "/home/user/dropper.sh"
    payload = "/home/user/payload.bin"

    if os.path.lexists(payload):
        os.unlink(payload)

    try:
        result = subprocess.run([dropper], capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        pytest.fail("dropper.sh execution timed out.")

    assert result.returncode == 0, (
        f"dropper.sh failed with exit code {result.returncode}. "
        f"STDOUT: {result.stdout} STDERR: {result.stderr}"
    )
    assert os.path.isfile(payload), "dropper.sh did not create /home/user/payload.bin"

    with open(payload, "rb") as f:
        actual_md5 = hashlib.md5(f.read()).hexdigest()
    assert actual_md5 == EXPECTED_MD5, (
        f"Incorrect payload checksum: expected {EXPECTED_MD5}, got {actual_md5}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
