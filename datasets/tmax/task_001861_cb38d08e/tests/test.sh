#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import base64
import secrets
import subprocess
import sys

REPORT_PATH = '/home/user/security_report.json'
ENFORCER_PATH = '/home/user/enforcer.py'
SAMPLE_PATH = '/home/user/app/sample_token.txt'
EXPECTED_SECRET = "S3cr3t_P0licy_K3y_2024!"


def generate_token(user, csp):
    data = EXPECTED_SECRET + user + csp
    sig = hashlib.sha256(data.encode('utf-8')).hexdigest()
    u_b64 = base64.b64encode(user.encode('utf-8')).decode('utf-8')
    c_b64 = base64.b64encode(csp.encode('utf-8')).decode('utf-8')
    return f"{u_b64}.{c_b64}.{sig}"


def run_enforcer(token):
    with open(SAMPLE_PATH, 'w') as f:
        f.write(token)
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        [sys.executable, ENFORCER_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"enforcer.py failed with code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} does not exist."
    with open(REPORT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"{REPORT_PATH} does not contain valid JSON."


def test_security_report_exists_and_valid():
    assert os.path.isfile(ENFORCER_PATH), f"{ENFORCER_PATH} does not exist."

    with open(SAMPLE_PATH, 'r') as f:
        original_token = f.read().strip()

    try:
        # A modified checksum must be detected rather than accepted from a static report.
        parts = original_token.split('.')
        assert len(parts) == 3, "The staged sample token is malformed."
        replacement = '0' if parts[2][-1] != '0' else '1'
        tampered_token = '.'.join((parts[0], parts[1], parts[2][:-1] + replacement))
        tampered_report = run_enforcer(tampered_token)
        assert tampered_report.get("sample_token_valid") is False, (
            "enforcer.py did not reject a token with a bad checksum."
        )
        assert tampered_report.get("sample_token_policy_failed") is True, (
            "enforcer.py did not detect the unsafe script-src directive."
        )

        # Exercise policy parsing with a dynamically generated compliant CSP.
        nonce = secrets.token_hex(8)
        safe_user = f"verification-{nonce}"
        safe_csp = f"default-src 'self'; img-src https://{nonce}.example; script-src 'self';"
        safe_report = run_enforcer(generate_token(safe_user, safe_csp))
        assert safe_report.get("sample_token_valid") is True, (
            "enforcer.py rejected a correctly signed token."
        )
        assert safe_report.get("sample_token_policy_failed") is False, (
            "enforcer.py incorrectly rejected a compliant script-src directive."
        )

        # Run against the original staged sample and retain all original assertions.
        report = run_enforcer(original_token)
        assert report.get("recovered_secret") == EXPECTED_SECRET, (
            "recovered_secret is incorrect."
        )
        assert report.get("sample_token_valid") is True, (
            "sample_token_valid should be true."
        )
        assert report.get("sample_token_policy_failed") is True, (
            "sample_token_policy_failed should be true."
        )

        user = "admin-pipeline"
        csp = "default-src 'self'; script-src 'self';"
        expected_token = generate_token(user, csp)
        assert report.get("forged_admin_token") == expected_token, (
            "forged_admin_token is incorrect."
        )
    finally:
        with open(SAMPLE_PATH, 'w') as f:
            f.write(original_token)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
