#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import hmac
import json
import os
import re
import stat
import subprocess

import pytest

REPORT_PATH = "/home/user/report.json"
ANALYZER_PATH = "/home/user/analyze.go"
TOKEN_PATH = "/home/user/hidden_exfil/token.jwt"
IMPLANT_PATH = "/home/user/hidden_exfil/implant"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def make_token(key, user, signing_key=None):
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"user": user, "role": "root"}, separators=(",", ":")).encode())
    message = header + b"." + payload
    signature = hmac.new(signing_key or key, message, hashlib.sha256).digest()
    return message + b"." + b64url(signature) + b"\n"


def run_analyzer():
    return subprocess.run(
        ["go", "run", ANALYZER_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )


def remove_report():
    try:
        os.remove(REPORT_PATH)
    except FileNotFoundError:
        pass


@pytest.fixture(scope="module", autouse=True)
def exercise_analyzer():
    assert os.path.exists(ANALYZER_PATH), f"Required Go program not found at {ANALYZER_PATH}"
    mode = os.lstat(ANALYZER_PATH).st_mode
    assert stat.S_ISREG(mode), f"{ANALYZER_PATH} must be a regular Go source file"

    with open(IMPLANT_PATH, "rb") as f:
        implant = f.read()
    match = re.search(rb"JWT_SECRET=([A-Za-z0-9_!@#$%^&*+=:.,-]+)\x00", implant)
    assert match, "Could not locate the JWT_SECRET marker in the supplied implant"
    extracted_key = match.group(1)

    with open(TOKEN_PATH, "rb") as f:
        original_token = f.read()

    dynamic_user = "verification_user_" + os.urandom(8).hex()
    valid_dynamic_token = make_token(extracted_key, dynamic_user)
    invalid_dynamic_token = make_token(extracted_key, dynamic_user, signing_key=os.urandom(32))

    try:
        with open(TOKEN_PATH, "wb") as f:
            f.write(valid_dynamic_token)
        remove_report()
        result = run_analyzer()
        assert result.returncode == 0, (
            "analyze.go failed on a valid signed JWT:\n" + result.stdout + result.stderr
        )
        assert os.path.isfile(REPORT_PATH), "analyze.go did not generate report.json"
        with open(REPORT_PATH, "r") as f:
            dynamic_report = json.load(f)
        assert dynamic_report.get("extracted_key") == extracted_key.decode()
        assert dynamic_report.get("decoded_payload_user") == dynamic_user, (
            "analyze.go did not decode the user from the JWT it was given"
        )
        dynamic_cwe = str(dynamic_report.get("vulnerability_cwe", "")).upper()
        assert "CWE-22" in dynamic_cwe or "CWE-022" in dynamic_cwe

        with open(TOKEN_PATH, "wb") as f:
            f.write(invalid_dynamic_token)
        remove_report()
        run_analyzer()
        assert not os.path.exists(REPORT_PATH), (
            "analyze.go generated a report for a JWT with an invalid signature"
        )
    finally:
        with open(TOKEN_PATH, "wb") as f:
            f.write(original_token)

    remove_report()
    result = run_analyzer()
    assert result.returncode == 0, (
        "analyze.go failed on the supplied token:\n" + result.stdout + result.stderr
    )
    yield


def test_report_exists():
    """Verify that the final forensics report exists at the exact required path."""
    assert os.path.isfile(REPORT_PATH), f"Forensics report not found at {REPORT_PATH}. Ensure you saved the file to the correct absolute path."


def test_report_format_and_contents():
    """Verify the JSON schema and the accuracy of the forensics findings."""
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not a valid JSON document.")

    required_keys = ["vulnerability_cwe", "extracted_key", "decoded_payload_user"]
    for key in required_keys:
        assert key in data, f"Missing required key '{key}' in {REPORT_PATH} JSON structure."

    cwe_value = str(data["vulnerability_cwe"]).upper()
    assert "CWE-22" in cwe_value or "CWE-022" in cwe_value, \
        f"Incorrect CWE identifier. Expected a variation of CWE-22 (Path Traversal), but got: '{data['vulnerability_cwe']}'"

    expected_key = "f0r3ns1cs_k3y_9981"
    assert data["extracted_key"] == expected_key, \
        f"Incorrect extracted key. Expected '{expected_key}', but got: '{data['extracted_key']}'"

    expected_user = "sys_attacker"
    assert data["decoded_payload_user"] == expected_user, \
        f"Incorrect decoded payload user. Expected '{expected_user}', but got: '{data['decoded_payload_user']}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
