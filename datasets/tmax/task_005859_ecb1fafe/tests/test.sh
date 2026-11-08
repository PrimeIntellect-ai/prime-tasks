#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import stat
import subprocess
import hashlib
import base64
import secrets
import pytest

CREDS_FILE = "/home/user/app_config/creds.json"
SCRIPT_FILE = "/home/user/verify_auth.py"

# Compute the expected values dynamically
OLD_TOKEN = "old_secret_token_123"
SALT = "ROTATION_SALT_2024"
HASH_INPUT = OLD_TOKEN + SALT
EXPECTED_HEX_DIGEST = hashlib.sha256(HASH_INPUT.encode('utf-8')).hexdigest()
EXPECTED_B64_TOKEN = base64.b64encode(EXPECTED_HEX_DIGEST.encode('utf-8')).decode('utf-8')

def test_creds_json_permissions():
    assert os.path.isfile(CREDS_FILE), f"File {CREDS_FILE} does not exist."
    st = os.stat(CREDS_FILE)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"File {CREDS_FILE} has permissions {oct(perms)}, expected 0o600."

def test_creds_json_contents():
    assert os.path.isfile(CREDS_FILE), f"File {CREDS_FILE} does not exist."
    with open(CREDS_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {CREDS_FILE} is not valid JSON.")

    assert "api_key_b64" in data, f"'api_key_b64' key missing in {CREDS_FILE}."
    assert data["api_key_b64"] == EXPECTED_B64_TOKEN, f"Incorrect rotated token in {CREDS_FILE}."

def run_verify_script():
    try:
        return subprocess.run(
            ["python3", SCRIPT_FILE],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script {SCRIPT_FILE} failed to execute. Error: {e.stderr}")

def test_verify_auth_script():
    assert os.path.isfile(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."

    original_contents = open(CREDS_FILE, "rb").read()
    original_mode = stat.S_IMODE(os.stat(CREDS_FILE).st_mode)

    try:
        result = run_verify_script()
        expected_output = f"Active Token: {EXPECTED_HEX_DIGEST}"
        actual_output = result.stdout.strip()
        assert actual_output == expected_output, f"Output from {SCRIPT_FILE} was '{actual_output}', expected '{expected_output}'."

        # Exercise the script with a verifier-generated token so a script that
        # merely prints the known final digest cannot pass.
        alternate_hex_digest = secrets.token_hex(32)
        alternate_b64 = base64.b64encode(alternate_hex_digest.encode("utf-8")).decode("utf-8")
        with open(CREDS_FILE, "w") as f:
            json.dump({"api_key_b64": alternate_b64}, f)
        os.chmod(CREDS_FILE, 0o600)

        result = run_verify_script()
        expected_output = f"Active Token: {alternate_hex_digest}"
        actual_output = result.stdout.strip()
        assert actual_output == expected_output, f"Output from {SCRIPT_FILE} was '{actual_output}', expected '{expected_output}' after changing the credential file."
    finally:
        with open(CREDS_FILE, "wb") as f:
            f.write(original_contents)
        os.chmod(CREDS_FILE, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
