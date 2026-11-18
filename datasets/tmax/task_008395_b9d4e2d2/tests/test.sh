#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_PATH = "/home/user/audit_report.json"

def test_audit_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The expected report file {REPORT_PATH} does not exist."

def test_audit_report_structure_and_content():
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    # Check CWE
    assert "vulnerability_cwe" in report, "Missing 'vulnerability_cwe' key in the JSON report."
    assert report["vulnerability_cwe"] == "CWE-22", f"Expected CWE-22, got {report['vulnerability_cwe']}."

    # Check attackers array
    assert "attackers" in report, "Missing 'attackers' key in the JSON report."
    attackers = report["attackers"]
    assert isinstance(attackers, list), "'attackers' should be a list."
    assert len(attackers) == 2, f"Expected exactly 2 attackers, found {len(attackers)}."

    # The instructions specify sorting alphabetically by username
    # charlie comes before malicious_dave
    attacker1 = attackers[0]
    assert attacker1.get("username") == "charlie", f"Expected first attacker username 'charlie', got {attacker1.get('username')}."
    assert attacker1.get("ip_address") == "172.16.0.4", f"Expected IP '172.16.0.4' for charlie, got {attacker1.get('ip_address')}."
    assert attacker1.get("payload") == "../../../etc/passwd", f"Expected payload '../../../etc/passwd' for charlie, got {attacker1.get('payload')}."

    attacker2 = attackers[1]
    assert attacker2.get("username") == "malicious_dave", f"Expected second attacker username 'malicious_dave', got {attacker2.get('username')}."
    assert attacker2.get("ip_address") == "203.0.113.88", f"Expected IP '203.0.113.88' for malicious_dave, got {attacker2.get('ip_address')}."
    assert attacker2.get("payload") == "..%2F..%2F..%2Fetc%2Fshadow", f"Expected payload '..%2F..%2F..%2Fetc%2Fshadow' for malicious_dave, got {attacker2.get('payload')}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
