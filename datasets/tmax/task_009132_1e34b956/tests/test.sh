#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import hmac
import hashlib
import secrets
import subprocess
import pytest

REPORT_PATH = "/home/user/audit_report.json"
SCRIPT_PATH = "/home/user/policy_checker.py"
APP_PATH = "/home/user/app_repo/app.py"
CONFIG_PATH = "/home/user/app_repo/config.json"
EXPECTED_SECRET = "Sup3rS3cr3t_DevSecOps_K3y_2024!"

def b64_decode(data: str) -> bytes:
    """Helper to decode base64url without padding."""
    padded = data + '=' * (4 - len(data) % 4)
    return base64.urlsafe_b64decode(padded)

def verify_jwt(token: str, secret: str) -> dict:
    """Verify and decode a JWT using only the standard library."""
    parts = token.split('.')
    if len(parts) != 3:
        raise ValueError("JWT does not have 3 parts separated by dots.")

    header_b64, payload_b64, signature_b64 = parts

    # Verify signature
    msg = f"{header_b64}.{payload_b64}".encode('utf-8')
    expected_sig = base64.urlsafe_b64encode(
        hmac.new(secret.encode('utf-8'), msg, hashlib.sha256).digest()
    ).decode('utf-8').rstrip('=')

    if not hmac.compare_digest(expected_sig, signature_b64):
        raise ValueError("JWT signature verification failed.")

    header = json.loads(b64_decode(header_b64))
    if header.get("alg") != "HS256":
        raise ValueError(f"Expected HS256 algorithm, got {header.get('alg')}")

    payload = json.loads(b64_decode(payload_b64))
    return payload

def test_policy_checker_script_exists():
    """Verify the student created the policy checker script."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} was not found."

def test_audit_report_exists():
    """Verify the audit report JSON file was generated."""
    assert os.path.isfile(REPORT_PATH), f"The report {REPORT_PATH} was not generated."

def test_audit_report_contents():
    """Verify the contents of the audit report."""
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    # Check basic fields
    assert "extracted_secret" in report, "Missing 'extracted_secret' in audit report."
    assert report["extracted_secret"] == EXPECTED_SECRET, "The extracted secret is incorrect."

    assert "cwe_identified" in report, "Missing 'cwe_identified' in audit report."
    assert report["cwe_identified"] == "CWE-798", "The identified CWE is incorrect."

    assert "privilege_escalation_risk_found" in report, "Missing 'privilege_escalation_risk_found' in audit report."
    assert report["privilege_escalation_risk_found"] is True, "The privilege escalation risk should be True based on config.json."

    assert "forged_admin_jwt" in report, "Missing 'forged_admin_jwt' in audit report."

    # Verify the JWT
    token = report["forged_admin_jwt"]
    try:
        payload = verify_jwt(token, EXPECTED_SECRET)
    except Exception as e:
        pytest.fail(f"Failed to verify the forged JWT: {e}")

    assert payload.get("username") == "admin", f"JWT payload username is not 'admin'. Got: {payload.get('username')}"
    assert payload.get("role") == "superuser", f"JWT payload role is not 'superuser'. Got: {payload.get('role')}"

def test_policy_checker_executes_and_audits_current_inputs():
    """Execute the submitted script against fresh inputs and derive expected answers."""
    with open(APP_PATH, "rb") as f:
        original_app = f.read()
    with open(CONFIG_PATH, "rb") as f:
        original_config = f.read()
    original_report = None
    if os.path.isfile(REPORT_PATH):
        with open(REPORT_PATH, "rb") as f:
            original_report = f.read()

    try:
        for run_as, expected_risk in (("appuser", False), ("root", True)):
            expected_secret = "dynamic_" + secrets.token_urlsafe(24)
            app_source = f'''import jwt\n\n# This development secret is intentionally hardcoded for the audit.\nJWT_SECRET_KEY = "{expected_secret}"\n\ndef authenticate_user(token):\n    try:\n        return jwt.decode(token, JWT_SECRET_KEY, algorithms=["HS256"])\n    except Exception:\n        return None\n'''
            with open(APP_PATH, "w") as f:
                f.write(app_source)
            with open(CONFIG_PATH, "w") as f:
                json.dump({
                    "service_name": "dynamic-test-service",
                    "version": "1.0",
                    "run_as": run_as,
                    "bind_port": 8080,
                    "debug_mode": False
                }, f)

            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)

            result = subprocess.run(
                ["python3", SCRIPT_PATH],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, (
                f"policy_checker.py exited with {result.returncode}. "
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
            assert os.path.isfile(REPORT_PATH), "Executing policy_checker.py did not generate the report."

            with open(REPORT_PATH, "r") as f:
                try:
                    report = json.load(f)
                except json.JSONDecodeError as e:
                    pytest.fail(f"Executing policy_checker.py generated invalid JSON: {e}")

            assert report.get("extracted_secret") == expected_secret
            assert report.get("cwe_identified") == "CWE-798"
            assert report.get("privilege_escalation_risk_found") is expected_risk
            assert "forged_admin_jwt" in report

            try:
                payload = verify_jwt(report["forged_admin_jwt"], expected_secret)
            except Exception as e:
                pytest.fail(f"JWT generated for the current app.py is invalid: {e}")
            assert payload.get("username") == "admin"
            assert payload.get("role") == "superuser"
    finally:
        with open(APP_PATH, "wb") as f:
            f.write(original_app)
        with open(CONFIG_PATH, "wb") as f:
            f.write(original_config)
        if original_report is not None:
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)
        elif os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
