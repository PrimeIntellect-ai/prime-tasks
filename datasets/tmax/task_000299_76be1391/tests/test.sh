#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import stat
import pytest

REPORT_PATH = "/home/user/forensics/report.json"
BIN_DIR = "/home/user/forensics/bin"

@pytest.fixture(scope="module")
def report_data():
    assert os.path.isfile(REPORT_PATH), f"The forensic report was not found at {REPORT_PATH}."

    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file at {REPORT_PATH} is not valid JSON.")

    return data

def test_report_structure(report_data):
    expected_keys = {"attacker_user", "malicious_csp_domain", "privesc_file_hash"}
    actual_keys = set(report_data.keys())

    missing_keys = expected_keys - actual_keys
    extra_keys = actual_keys - expected_keys

    assert not missing_keys, f"The report is missing required keys: {missing_keys}"
    assert not extra_keys, f"The report contains unauthorized extra keys: {extra_keys}"

def test_attacker_user_value(report_data):
    expected_user = "darkknght"
    actual_user = report_data.get("attacker_user")

    assert actual_user == expected_user, (
        f"Incorrect attacker_user. Expected '{expected_user}', but got '{actual_user}'. "
        "Did you correctly decode the JWT payload with the 'none' algorithm from server.log?"
    )

def test_malicious_csp_domain_value(report_data):
    expected_domain = "http://evil-cdn.net"
    actual_domain = report_data.get("malicious_csp_domain")

    assert actual_domain == expected_domain, (
        f"Incorrect malicious_csp_domain. Expected '{expected_domain}', but got '{actual_domain}'. "
        "Did you verify the file checksums and extract the unauthorized domain from the altered script-src directive?"
    )

def test_privesc_file_hash_value(report_data):
    # Dynamically find the SUID binary in the bin directory to derive the truth
    suid_files = []
    for filename in os.listdir(BIN_DIR):
        filepath = os.path.join(BIN_DIR, filename)
        if os.path.isfile(filepath):
            file_stat = os.stat(filepath)
            if file_stat.st_mode & stat.S_ISUID:
                suid_files.append(filepath)

    assert len(suid_files) == 1, f"Expected exactly one SUID file in {BIN_DIR}, found {len(suid_files)}."

    suid_file_path = suid_files[0]

    # Compute the expected hash dynamically
    sha256_hash = hashlib.sha256()
    with open(suid_file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)

    expected_hash = sha256_hash.hexdigest().lower()
    actual_hash = report_data.get("privesc_file_hash", "").lower()

    assert actual_hash == expected_hash, (
        f"Incorrect privesc_file_hash. Expected '{expected_hash}', but got '{actual_hash}'. "
        f"Did you find the SUID binary ({os.path.basename(suid_file_path)}) and correctly compute its SHA256 hash?"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
