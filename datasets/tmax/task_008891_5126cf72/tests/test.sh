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

REPORT_PATH = "/home/user/forensic_report.json"
WEBAPP_DIR = "/home/user/webapp"
BACKUP_HASHES_PATH = "/home/user/backup_hashes.txt"
LOG_PATH = "/home/user/logs/access.log"
CONFIG_PATH = "/home/user/webapp/config.json"

@pytest.fixture
def report_data():
    assert os.path.isfile(REPORT_PATH), f"Forensic report not found at {REPORT_PATH}"
    try:
        with open(REPORT_PATH, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} is not valid JSON.")

def test_report_structure(report_data):
    expected_keys = {"integrity_violations", "attacker_ips", "fixed_csp"}
    actual_keys = set(report_data.keys())
    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f"Report is missing required keys: {missing_keys}"

def test_integrity_violations(report_data):
    # Derive the truth dynamically
    assert os.path.isfile(BACKUP_HASHES_PATH), f"Missing {BACKUP_HASHES_PATH}"

    backup_hashes = {}
    with open(BACKUP_HASHES_PATH, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                backup_hashes[parts[1]] = parts[0]

    actual_files = [f for f in os.listdir(WEBAPP_DIR) if os.path.isfile(os.path.join(WEBAPP_DIR, f))]

    expected_violations = []
    for filename in actual_files:
        filepath = os.path.join(WEBAPP_DIR, filename)
        with open(filepath, "rb") as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()

        if filename not in backup_hashes or backup_hashes[filename] != file_hash:
            expected_violations.append(filename)

    expected_violations.sort()

    reported_violations = report_data.get("integrity_violations", [])
    assert isinstance(reported_violations, list), "'integrity_violations' must be a list"
    assert reported_violations == expected_violations, \
        f"Expected integrity violations {expected_violations}, but got {reported_violations}"

def test_attacker_ips(report_data):
    # Derive the truth dynamically
    assert os.path.isfile(LOG_PATH), f"Missing {LOG_PATH}"

    expected_ips = set()
    traversal_pattern = re.compile(r'\.\./|%2e%2e%2f', re.IGNORECASE)

    with open(LOG_PATH, "r") as f:
        for line in f:
            if traversal_pattern.search(line):
                # Extract IP (first space-separated token in standard combined/common log format)
                ip = line.split(" ", 1)[0]
                expected_ips.add(ip)

    expected_ips_sorted = sorted(list(expected_ips))

    reported_ips = report_data.get("attacker_ips", [])
    assert isinstance(reported_ips, list), "'attacker_ips' must be a list"
    assert reported_ips == expected_ips_sorted, \
        f"Expected attacker IPs {expected_ips_sorted}, but got {reported_ips}"

def test_fixed_csp(report_data):
    # Derive the truth dynamically
    assert os.path.isfile(CONFIG_PATH), f"Missing {CONFIG_PATH}"

    with open(CONFIG_PATH, "r") as f:
        config_data = json.load(f)

    original_csp = config_data.get("headers", {}).get("Content-Security-Policy", "")

    # Remove bad elements and normalize both token and semicolon spacing.
    cleaned_csp = original_csp.replace("'unsafe-inline'", "").replace("http://evil.com", "")
    directives = [" ".join(directive.split()) for directive in cleaned_csp.split(";") if directive.split()]
    fixed_csp = "; ".join(directives)
    if original_csp.rstrip().endswith(";"):
        fixed_csp += ";"

    reported_csp = report_data.get("fixed_csp", "")
    assert reported_csp == fixed_csp, \
        f"Expected fixed CSP to be '{fixed_csp}', but got '{reported_csp}'"

def test_config_unmodified():
    assert os.path.isfile(CONFIG_PATH), f"Missing {CONFIG_PATH}"
    with open(CONFIG_PATH, "r") as f:
        config_data = json.load(f)

    csp = config_data.get("headers", {}).get("Content-Security-Policy", "")
    assert "'unsafe-inline'" in csp and "http://evil.com" in csp, \
        "The original config.json file was modified. The instructions stated not to modify the original file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
