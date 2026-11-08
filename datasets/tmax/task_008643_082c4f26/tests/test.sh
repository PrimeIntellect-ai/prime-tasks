#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import hmac
import pytest

REPORT_PATH = "/home/user/audit_report.json"
LOGS_PATH = "/home/user/audit/logs.json"
SECRET_PATH = "/home/user/audit/secret.key"
IPTABLES_PATH = "/home/user/audit/iptables.dump"
CERT_EXP_PATH = "/tmp/expected_cert_exp.txt"

def get_expected_invalid_logs():
    with open(SECRET_PATH, 'rb') as f:
        secret = f.read().strip()

    with open(LOGS_PATH, 'r') as f:
        logs = json.load(f)

    invalid_ids = []
    for entry in logs:
        id_val = entry['id']
        payload = entry['payload']
        checksum = entry['checksum']
        token = entry['token']

        expected_checksum = hashlib.sha256(payload.encode()).hexdigest()
        msg = f"{id_val}:{payload}".encode()
        expected_token = hmac.new(secret, msg, hashlib.sha256).hexdigest()

        if checksum != expected_checksum or token != expected_token:
            invalid_ids.append(id_val)

    return sorted(invalid_ids)

def check_firewall_rule():
    with open(IPTABLES_PATH, 'r') as f:
        for line in f:
            if "-s 10.0.50.0/24" in line and "--dport 8443" in line and "-j ACCEPT" in line:
                return True
    return False

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The file {REPORT_PATH} does not exist."

def test_report_structure_and_values():
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not a valid JSON file.")

    expected_invalid_logs = get_expected_invalid_logs()

    assert "invalid_log_ids" in report, "Missing 'invalid_log_ids' in report."
    assert isinstance(report["invalid_log_ids"], list), "'invalid_log_ids' must be a list."
    assert sorted(report["invalid_log_ids"]) == expected_invalid_logs, \
        f"Expected invalid_log_ids to be {expected_invalid_logs}, but got {sorted(report['invalid_log_ids'])}."

    assert "certificate_cn" in report, "Missing 'certificate_cn' in report."
    assert report["certificate_cn"] == "data-proxy.internal.corp", \
        f"Expected certificate_cn to be 'data-proxy.internal.corp', got {report['certificate_cn']}."

    with open(CERT_EXP_PATH, 'r') as f:
        expected_cert_exp = f.read().strip()

    assert "certificate_expiration" in report, "Missing 'certificate_expiration' in report."
    assert report["certificate_expiration"] == expected_cert_exp, \
        f"Expected certificate_expiration to be '{expected_cert_exp}', got '{report['certificate_expiration']}'."

    expected_firewall = check_firewall_rule()
    assert "firewall_allows_8443_from_subnet" in report, "Missing 'firewall_allows_8443_from_subnet' in report."
    assert report["firewall_allows_8443_from_subnet"] is expected_firewall, \
        f"Expected firewall_allows_8443_from_subnet to be {expected_firewall}, got {report['firewall_allows_8443_from_subnet']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
