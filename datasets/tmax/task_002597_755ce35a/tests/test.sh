#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import re
import pytest

REPORT_PATH = "/home/user/report.json"
MANIFEST_PATH = "/home/user/app_manifest.sha256"
LOG_PATH = "/home/user/logs/access.log"

EXPECTED_REPORT = {
    "compromised_files": [
        "/home/user/app/index.html",
        "/home/user/app/main.js",
    ],
    "attacker_ip": "198.51.100.77",
    "extracted_malicious_domains": [
        "crypto-miner.badactor.net",
        "exfil.stealdata.org",
    ],
    "recommended_csp": "script-src 'self';",
}

def get_expected_compromised_files():
    if not os.path.exists(MANIFEST_PATH):
        return []

    compromised = []
    with open(MANIFEST_PATH, 'r') as f:
        for line in f:
            parts = line.strip().split('  ')
            if len(parts) == 2:
                expected_hash, filepath = parts
                if os.path.exists(filepath):
                    with open(filepath, 'rb') as target_file:
                        actual_hash = hashlib.sha256(target_file.read()).hexdigest()
                    if actual_hash != expected_hash:
                        compromised.append(filepath)
                else:
                    compromised.append(filepath)
    return sorted(compromised)

def get_expected_attacker_ip(compromised_files):
    if not os.path.exists(LOG_PATH):
        return None

    attacker_ip = None
    with open(LOG_PATH, 'r') as f:
        for line in f:
            if '../' in line:
                for comp_file in compromised_files:
                    if comp_file in line:
                        attacker_ip = line.split(' ')[0]
                        break
    return attacker_ip

def get_expected_malicious_domains(compromised_files):
    domains = set()
    url_pattern = re.compile(r'https?://([a-zA-Z0-9.-]+)')
    for filepath in compromised_files:
        if os.path.exists(filepath):
            with open(filepath, 'r') as f:
                content = f.read()
                matches = url_pattern.findall(content)
                for match in matches:
                    domains.add(match)
    return sorted(list(domains))

@pytest.fixture
def report_data():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    try:
        with open(REPORT_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT_PATH} is not valid JSON")
    return data

def test_compromised_files(report_data):
    assert "compromised_files" in report_data, "Key 'compromised_files' missing in report"
    expected = get_expected_compromised_files()
    actual = sorted(report_data["compromised_files"])
    assert actual == expected, f"Expected compromised_files to be {expected}, but got {actual}"

def test_attacker_ip(report_data):
    assert "attacker_ip" in report_data, "Key 'attacker_ip' missing in report"
    expected_files = get_expected_compromised_files()
    expected_ip = get_expected_attacker_ip(expected_files)
    assert report_data["attacker_ip"] == expected_ip, f"Expected attacker_ip to be {expected_ip}, but got {report_data['attacker_ip']}"

def test_malicious_domains(report_data):
    assert "extracted_malicious_domains" in report_data, "Key 'extracted_malicious_domains' missing in report"
    expected_files = get_expected_compromised_files()
    expected_domains = get_expected_malicious_domains(expected_files)
    actual_domains = sorted(report_data["extracted_malicious_domains"])
    assert actual_domains == expected_domains, f"Expected extracted_malicious_domains to be {expected_domains}, but got {actual_domains}"

def test_recommended_csp(report_data):
    assert "recommended_csp" in report_data, "Key 'recommended_csp' missing in report"
    expected_csp = "script-src 'self';"
    assert report_data["recommended_csp"] == expected_csp, f"Expected recommended_csp to be {expected_csp}, but got {report_data['recommended_csp']}"

def test_report_matches_ground_truth(report_data):
    assert report_data == EXPECTED_REPORT, f"Report does not match the fixed forensic ground truth: {report_data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
