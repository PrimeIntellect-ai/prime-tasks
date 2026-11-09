#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import string
import pytest

REPORT_PATH = "/home/user/audit_report.json"
CERT_PATH = "/home/user/server.crt"

def weak_hash(input_str: str) -> int:
    """Python implementation of the weak_hash function."""
    hash_val = 0x5555
    for char in input_str:
        hash_val = ((hash_val << 5) + hash_val + ord(char)) & 0xFFFF
    return hash_val

def test_audit_report_exists_and_valid_json():
    """Verify that the audit report exists and is valid JSON."""
    assert os.path.exists(REPORT_PATH), f"Audit report not found at {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {REPORT_PATH} is not valid JSON.")

    assert "cert_fingerprint_sha256" in data, "Missing 'cert_fingerprint_sha256' in audit report"
    assert "csp_contains_unsafe_eval" in data, "Missing 'csp_contains_unsafe_eval' in audit report"
    assert "legacy_hash_collision" in data, "Missing 'legacy_hash_collision' in audit report"

def test_cert_fingerprint():
    """Verify that the certificate fingerprint matches the actual cert."""
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    reported_fingerprint = data.get("cert_fingerprint_sha256")

    # Compute actual fingerprint using OpenSSL
    result = subprocess.run(
        ["openssl", "x509", "-noout", "-fingerprint", "-sha256", "-in", CERT_PATH],
        capture_output=True, text=True, check=True
    )
    # Output format: SHA256 Fingerprint=AB:CD:...
    actual_fingerprint = result.stdout.strip().split("=")[-1]

    assert reported_fingerprint == actual_fingerprint, (
        f"Reported fingerprint '{reported_fingerprint}' does not match actual fingerprint '{actual_fingerprint}'"
    )

def test_csp_contains_unsafe_eval():
    """Verify that csp_contains_unsafe_eval is true."""
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    csp_val = data.get("csp_contains_unsafe_eval")
    assert csp_val is True, "csp_contains_unsafe_eval should be True"

def test_legacy_hash_collision():
    """Verify the properties of the legacy hash collision strings."""
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    collisions = data.get("legacy_hash_collision")
    assert isinstance(collisions, list), "legacy_hash_collision must be a list"
    assert len(collisions) == 2, "legacy_hash_collision must contain exactly two strings"

    str1, str2 = collisions
    assert isinstance(str1, str) and isinstance(str2, str), "Collision items must be strings"

    assert str1 != str2, "The two collision strings must be strictly different"

    for idx, s in enumerate([str1, str2]):
        assert 3 <= len(s) <= 15, f"String {idx+1} length must be between 3 and 15 characters"
        assert all(c in string.printable for c in s), f"String {idx+1} must contain only printable ASCII characters"

    hash1 = weak_hash(str1)
    hash2 = weak_hash(str2)

    assert hash1 == hash2, f"Hash values do not match: weak_hash('{str1}')={hash1} != weak_hash('{str2}')={hash2}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
