#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import configparser
import subprocess
import pytest

EXPLOIT_GENERATOR_PATH = "/home/user/exploit_generator.py"
EXPLOIT_JSON_PATH = "/home/user/exploit.json"
TARGET_WAF_PATH = "/home/user/target/waf_eval.py"
CONFIG_PATH = "/home/user/target/config.ini"
PWNED_FILE_PATH = "/home/user/pwned.txt"

EXPECTED_TARGET = b'''import json
import sys
import hashlib
import configparser

def load_config():
    config = configparser.ConfigParser()
    config.read('/home/user/target/config.ini')
    return config['security']['secret_salt']

def process_request(filepath):
    salt = load_config()
    try:
        with open(filepath, 'r') as f:
            req = json.load(f)
    except Exception as e:
        print(f"Failed to load request: {e}")
        return

    headers = req.get('headers', {})
    cookie = headers.get('Cookie', '')
    token = headers.get('X-Bypass-Token', '')

    expected_token = hashlib.md5((cookie + salt).encode()).hexdigest()

    if token != expected_token:
        print("WAF Block: Invalid token.")
        return

    body = req.get('body', {})
    payload = body.get('payload', '')

    if not payload:
        print("No payload provided.")
        return

    print("Token valid. Executing payload in sandbox...")
    # Restricted execution environment
    safe_globals = {
        '__builtins__': None
    }

    try:
        exec(payload, safe_globals)
    except Exception as e:
        print(f"Sandbox execution error: {e}")

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 waf_eval.py <request.json>")
        sys.exit(1)
    process_request(sys.argv[1])
'''

def assert_target_unchanged():
    assert os.path.isfile(TARGET_WAF_PATH), f"Target missing: {TARGET_WAF_PATH}"
    assert not os.path.islink(TARGET_WAF_PATH), f"Target must be a regular file, not a symlink: {TARGET_WAF_PATH}"
    with open(TARGET_WAF_PATH, "rb") as f:
        actual = f.read()
    assert actual == EXPECTED_TARGET, f"Target WAF was modified: {TARGET_WAF_PATH}"

def test_target_waf_unchanged():
    """Ensure the supplied WAF implementation was not replaced or modified."""
    assert_target_unchanged()

def test_exploit_generator_exists():
    """Verify the student created the exploit generator script."""
    assert os.path.isfile(EXPLOIT_GENERATOR_PATH), f"File missing: {EXPLOIT_GENERATOR_PATH}"

def test_exploit_generation():
    """Run the generator script and verify it creates the exploit.json file."""
    assert_target_unchanged()

    if os.path.exists(EXPLOIT_JSON_PATH):
        os.remove(EXPLOIT_JSON_PATH)

    result = subprocess.run(
        ["python3", EXPLOIT_GENERATOR_PATH],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Generator script failed with error:\n{result.stderr}"
    assert os.path.isfile(EXPLOIT_JSON_PATH), f"Generator script did not create {EXPLOIT_JSON_PATH}"
    assert_target_unchanged()

def test_exploit_json_structure_and_token():
    """Verify the structure of exploit.json and the correctness of the forged token."""
    assert os.path.isfile(EXPLOIT_JSON_PATH), f"Cannot test structure, {EXPLOIT_JSON_PATH} is missing."

    with open(EXPLOIT_JSON_PATH, 'r') as f:
        try:
            req = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"exploit.json is not valid JSON: {e}")

    assert "headers" in req, "exploit.json missing 'headers' key."
    assert "body" in req, "exploit.json missing 'body' key."

    headers = req["headers"]
    body = req["body"]

    assert "Cookie" in headers, "Missing 'Cookie' in headers."
    assert "X-Bypass-Token" in headers, "Missing 'X-Bypass-Token' in headers."
    assert "payload" in body, "Missing 'payload' in body."
    assert isinstance(body["payload"], str) and body["payload"], "Payload must be a non-empty string."
    assert headers["Cookie"] == "session=admin", "Cookie must be exactly 'session=admin'."

    assert os.path.isfile(CONFIG_PATH), f"Missing config file {CONFIG_PATH} to check token."
    config = configparser.ConfigParser()
    config.read(CONFIG_PATH)
    salt = config['security']['secret_salt']

    cookie = headers["Cookie"]
    expected_token = hashlib.md5((cookie + salt).encode()).hexdigest()
    actual_token = headers["X-Bypass-Token"]

    assert actual_token == expected_token, f"Forged token '{actual_token}' does not match expected token '{expected_token}'."

def test_sandbox_escape_execution():
    """Run the original WAF target with the generated exploit and verify the sandbox escape succeeds."""
    assert os.path.isfile(EXPLOIT_JSON_PATH), f"Cannot run exploit, {EXPLOIT_JSON_PATH} is missing."
    assert_target_unchanged()

    if os.path.exists(PWNED_FILE_PATH):
        os.remove(PWNED_FILE_PATH)

    result = subprocess.run(
        ["python3", TARGET_WAF_PATH, EXPLOIT_JSON_PATH],
        capture_output=True,
        text=True
    )

    assert_target_unchanged()
    assert os.path.isfile(PWNED_FILE_PATH), (
        f"Sandbox escape failed. {PWNED_FILE_PATH} was not created.\n"
        f"WAF stdout: {result.stdout}\n"
        f"WAF stderr: {result.stderr}"
    )

    with open(PWNED_FILE_PATH, 'r') as f:
        content = f.read()

    assert content == "Pwned!", f"Incorrect content in {PWNED_FILE_PATH}. Expected exactly 'Pwned!', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
