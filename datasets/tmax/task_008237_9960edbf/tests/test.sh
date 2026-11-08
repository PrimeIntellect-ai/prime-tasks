#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import stat
import subprocess
import sys


def expected_token(user_id):
    key = 42
    encrypted = bytearray()
    for char in user_id:
        encrypted.append(ord(char) ^ key)
    return base64.b64encode(encrypted).decode('utf-8')


def test_admin_token_correct():
    token_path = "/home/user/admin_token.txt"
    assert os.path.isfile(token_path), f"File {token_path} is missing."

    with open(token_path, 'r') as f:
        token = f.read().strip()

    # Compute the expected token dynamically
    user_id = "admin_root"
    expected = expected_token(user_id)

    assert token == expected, f"The token in {token_path} is incorrect. Expected {expected}, got {token}."


def test_forge_script_replicates_algorithm():
    script_path = "/home/user/forge_token.py"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    mode = os.lstat(script_path).st_mode
    assert stat.S_ISREG(mode), f"File {script_path} must be a regular Python script."

    user_ids = [
        "admin_root",
        "service_user",
        "audit-" + secrets.token_hex(12),
        "test_" + secrets.token_hex(17),
    ]

    # Prefer the natural API matching the legacy function. The helper executes the
    # submitted script in a separate interpreter and calls its generate_token.
    helper = r'''
import json
import runpy
import sys

script_path = sys.argv[1]
user_ids = json.loads(sys.stdin.read())
sys.argv = [script_path]
namespace = runpy.run_path(script_path)
func = namespace.get("generate_token")
if not callable(func):
    raise RuntimeError("forge_token.py does not define generate_token(user_id)")
print("__RESULT__" + json.dumps([func(user_id) for user_id in user_ids]))
'''
    proc = subprocess.run(
        [sys.executable, "-I", "-c", helper, script_path],
        input=json.dumps(user_ids),
        text=True,
        capture_output=True,
        timeout=10,
    )

    outputs = None
    if proc.returncode == 0:
        for line in reversed(proc.stdout.splitlines()):
            if line.startswith("__RESULT__"):
                outputs = json.loads(line[len("__RESULT__"):])
                break

    # Also accept a script implemented as a command-line tool taking the user ID
    # as its sole argument and printing the generated token.
    if outputs is None:
        outputs = []
        for user_id in user_ids:
            cli = subprocess.run(
                [sys.executable, "-I", script_path, user_id],
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert cli.returncode == 0, (
                f"Could not execute {script_path} via generate_token(user_id) or as a CLI. "
                f"stderr: {cli.stderr}"
            )
            lines = [line.strip() for line in cli.stdout.splitlines() if line.strip()]
            assert lines, f"CLI script {script_path} did not print a token for {user_id}."
            outputs.append(lines[-1])

    expected_outputs = [expected_token(user_id) for user_id in user_ids]
    assert outputs == expected_outputs, (
        "forge_token.py does not replicate the legacy token algorithm for arbitrary user IDs."
    )


def test_safe_csp_correct():
    csp_path = "/home/user/safe_csp.json"
    assert os.path.isfile(csp_path), f"File {csp_path} is missing."

    try:
        with open(csp_path, 'r') as f:
            safe_csp = json.load(f)
    except json.JSONDecodeError:
        assert False, f"File {csp_path} does not contain valid JSON."

    assert isinstance(safe_csp, list), f"The JSON in {csp_path} should be a list of objects."

    # Verify the contents
    ids = sorted([item.get('id') for item in safe_csp if 'id' in item])
    expected_ids = ['app2', 'app4']

    assert ids == expected_ids, f"The filtered CSP rules are incorrect. Expected IDs {expected_ids}, got {ids}."

    # Verify that none of the policies contain 'unsafe-inline' or 'unsafe-eval'
    for item in safe_csp:
        policy = item.get('policy', '')
        assert 'unsafe-inline' not in policy, f"Found 'unsafe-inline' in policy for id {item.get('id')}"
        assert 'unsafe-eval' not in policy, f"Found 'unsafe-eval' in policy for id {item.get('id')}"

    expected_csp = [
        {"id": "app2", "policy": "default-src 'self'; img-src https://*"},
        {"id": "app4", "policy": "default-src 'self'; font-src 'self'"},
    ]
    for item in safe_csp:
        assert isinstance(item, dict), "Each CSP configuration must be an object."
        assert set(item.keys()) == {"id", "policy"}, (
            "Each CSP configuration must contain exactly the id and policy keys."
        )
        assert isinstance(item['id'], str) and isinstance(item['policy'], str), (
            "CSP id and policy values must be strings."
        )
    assert safe_csp == expected_csp, (
        "safe_csp.json must preserve the complete compliant configurations and their original policies."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
