#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

FINDINGS_FILE = "/home/user/findings.json"
HELPER_SOURCE = "/home/user/incident/auth_helper.c"
HELPER_BINARY = "/tmp/auth_helper_verifier"

def test_findings_file_exists():
    assert os.path.isfile(FINDINGS_FILE), f"The file {FINDINGS_FILE} does not exist."

def test_findings_json_format():
    with open(FINDINGS_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{FINDINGS_FILE} is not a valid JSON file.")

    assert isinstance(data, dict), "The JSON root must be a dictionary."

    expected_keys = {"attacker_ip", "attacker_user", "valid_token"}
    actual_keys = set(data.keys())
    assert expected_keys == actual_keys, f"JSON keys do not match. Expected {expected_keys}, found {actual_keys}."

def test_attacker_details():
    with open(FINDINGS_FILE, 'r') as f:
        data = json.load(f)

    assert data["attacker_ip"] == "10.0.5.55", "Incorrect attacker_ip."
    assert data["attacker_user"] == "www-data", "Incorrect attacker_user."

def test_valid_token():
    with open(FINDINGS_FILE, 'r') as f:
        data = json.load(f)

    token = data["valid_token"]
    assert isinstance(token, str), "valid_token must be a string."
    assert token.startswith("ADM-"), "valid_token must start with 'ADM-'."

    # Calculate checksum of the rest of the string
    rest_of_token = token[4:]
    checksum = sum(ord(c) for c in rest_of_token)

    expected_checksum = 0x15e  # 350
    assert checksum == expected_checksum, f"Token checksum is {checksum}, but expected {expected_checksum}."

    # Compile and execute the actual helper so validation follows the C program's
    # byte-level char arithmetic rather than Python Unicode code points alone.
    assert os.path.isfile(HELPER_SOURCE), f"The helper source {HELPER_SOURCE} does not exist."
    compile_result = subprocess.run(
        ["gcc", HELPER_SOURCE, "-o", HELPER_BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Failed to compile auth_helper.c: {compile_result.stderr}"

    try:
        helper_result = subprocess.run(
            [HELPER_BINARY, token],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except (ValueError, OSError) as exc:
        pytest.fail(f"Token could not be passed to the authentication helper: {exc}")

    assert helper_result.returncode == 0, "The token was rejected by the actual authentication helper."
    assert helper_result.stdout.strip() == "AUTH_SUCCESS", "The helper did not report AUTH_SUCCESS."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
