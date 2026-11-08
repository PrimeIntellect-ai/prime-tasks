#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import hashlib
import secrets
import subprocess
import pytest

def get_expected_token():
    log_path = "/home/user/access.log"
    assert os.path.isfile(log_path), f"File {log_path} is missing."

    target_cookie = None
    with open(log_path, 'r') as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        if "X-Action: Rotate-Target" in line:
            # Find the cookie line in this block
            for j in range(i, len(lines)):
                if lines[j].startswith("Cookie: auth_session="):
                    target_cookie = lines[j].strip().split("Cookie: auth_session=")[1]
                    break
            break

    assert target_cookie is not None, "Could not find target cookie in access.log"

    decoded_json = base64.b64decode(target_cookie).decode('utf-8')
    data = json.loads(decoded_json)

    old_secret = data['secret']
    user = data['user']

    new_secret_raw = old_secret + "ROTATED"
    new_secret_hash = hashlib.sha256(new_secret_raw.encode('utf-8')).hexdigest()

    new_data = {"user": user, "secret": new_secret_hash}
    new_json_str = json.dumps(new_data, separators=(',', ':'))

    expected_token = base64.b64encode(new_json_str.encode('utf-8')).decode('utf-8')
    return expected_token

def test_rotate_script_exists():
    script_path = "/home/user/rotate.py"
    assert os.path.isfile(script_path), f"The script {script_path} was not created."

def test_new_token_correct():
    token_path = "/home/user/new_token.txt"
    assert os.path.isfile(token_path), f"The token file {token_path} was not created."

    with open(token_path, 'r') as f:
        actual_token = f.read().strip()

    expected_token = get_expected_token()

    assert actual_token == expected_token, (
        f"The token in {token_path} is incorrect. "
        f"Expected '{expected_token}', but got '{actual_token}'."
    )

def test_rotate_script_executes_on_fresh_input():
    script_path = "/home/user/rotate.py"
    log_path = "/home/user/access.log"
    token_path = "/home/user/new_token.txt"

    assert os.path.isfile(script_path), f"The script {script_path} was not created."

    with open(log_path, 'rb') as f:
        original_log = f.read()
    token_existed = os.path.isfile(token_path)
    original_token = None
    if token_existed:
        with open(token_path, 'rb') as f:
            original_token = f.read()

    user = "user_" + secrets.token_hex(8)
    old_secret = "secret_" + secrets.token_hex(24)
    distractor_payload = base64.b64encode(json.dumps({
        "user": "distractor",
        "secret": secrets.token_hex(16),
    }).encode('utf-8')).decode('ascii')
    target_payload = base64.b64encode(json.dumps({
        "user": user,
        "secret": old_secret,
    }).encode('utf-8')).decode('ascii')

    fresh_log = (
        "GET /ignore HTTP/1.1\n"
        "Host: internal.corp\n"
        "X-Action: Ignore\n"
        f"Cookie: auth_session={distractor_payload}\n\n"
        "GET /rotate HTTP/1.1\n"
        "Host: internal.corp\n"
        "X-Action: Rotate-Target\n"
        f"Cookie: auth_session={target_payload}\n"
    )

    expected_secret = hashlib.sha256((old_secret + "ROTATED").encode('utf-8')).hexdigest()
    expected_json = json.dumps(
        {"user": user, "secret": expected_secret}, separators=(',', ':')
    )
    expected_token = base64.b64encode(expected_json.encode('utf-8')).decode('ascii')

    try:
        with open(log_path, 'w') as f:
            f.write(fresh_log)
        if os.path.exists(token_path):
            os.remove(token_path)

        result = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Running {script_path} failed with exit code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(token_path), (
            f"Running {script_path} did not create {token_path}."
        )
        with open(token_path, 'r') as f:
            actual_token = f.read().strip()
        assert actual_token == expected_token, (
            "The script did not generate the correct token for a fresh access log. "
            f"Expected '{expected_token}', but got '{actual_token}'."
        )
    finally:
        with open(log_path, 'wb') as f:
            f.write(original_log)
        if token_existed:
            with open(token_path, 'wb') as f:
                f.write(original_token)
        elif os.path.exists(token_path):
            os.remove(token_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
