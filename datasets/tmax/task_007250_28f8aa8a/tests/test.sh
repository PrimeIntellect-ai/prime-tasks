#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import re
import pytest

BINARY_PATH = "/home/user/suspicious_binary"
CERT_PATH = "/home/user/extracted_cert.pem"
JSON_PATH = "/home/user/cert_info.json"

def extract_cert_from_binary(binary_path):
    with open(binary_path, "rb") as f:
        content = f.read()

    # Find PEM certificate
    match = re.search(b"(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)", content, re.DOTALL)
    if not match:
        return None
    return match.group(1)

def test_files_exist():
    """Test that the required output files exist."""
    assert os.path.exists(CERT_PATH), f"Extracted certificate not found at {CERT_PATH}."
    assert os.path.exists(JSON_PATH), f"JSON report not found at {JSON_PATH}."

def test_extracted_cert_content():
    """Test that the extracted certificate matches the one embedded in the binary."""
    expected_cert = extract_cert_from_binary(BINARY_PATH)
    assert expected_cert is not None, "Could not find certificate in binary to test against."

    with open(CERT_PATH, "rb") as f:
        actual_cert = f.read()

    assert expected_cert.strip() == actual_cert.strip(), "The extracted certificate does not match the embedded certificate."

def test_json_report_content():
    """Test that the JSON report contains the correct analysis results."""
    # Compute expected binary SHA256
    with open(BINARY_PATH, "rb") as f:
        expected_binary_sha256 = hashlib.sha256(f.read()).hexdigest()

    # Compute expected cert fingerprint
    expected_cert_pem = extract_cert_from_binary(BINARY_PATH).decode('ascii')
    # Extract base64 body
    cert_body = "".join([line for line in expected_cert_pem.splitlines() 
                         if not line.startswith("-----")])
    import base64
    der_cert = base64.b64decode(cert_body)
    expected_fingerprint = hashlib.sha256(der_cert).hexdigest()

    expected_cn = "c2.malicious-domain.local"

    # Read actual JSON
    with open(JSON_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} is not valid JSON.")

    assert "binary_sha256" in report, "Missing 'binary_sha256' in JSON report."
    assert report["binary_sha256"].lower() == expected_binary_sha256.lower(), "Incorrect binary SHA256."

    assert "cert_cn" in report, "Missing 'cert_cn' in JSON report."
    assert report["cert_cn"] == expected_cn, "Incorrect certificate Common Name (CN)."

    assert "cert_fingerprint" in report, "Missing 'cert_fingerprint' in JSON report."
    assert report["cert_fingerprint"].lower() == expected_fingerprint.lower(), "Incorrect certificate fingerprint."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
