#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import configparser
from pathlib import Path

def test_findings_file_exists():
    """Test that the findings.ini file has been created in the correct location."""
    findings_file = Path("/home/user/findings.ini")
    assert findings_file.is_file(), "The file /home/user/findings.ini does not exist."

def test_findings_format_and_content():
    """Test that findings.ini has the correct section and keys with expected values."""
    findings_file = Path("/home/user/findings.ini")
    assert findings_file.is_file(), "Cannot check content because /home/user/findings.ini is missing."

    config = configparser.ConfigParser()
    try:
        config.read(findings_file)
    except Exception as e:
        assert False, f"Failed to parse /home/user/findings.ini as a valid INI file: {e}"

    assert "Forensics" in config.sections(), "The [Forensics] section is missing from findings.ini."

    forensics = config["Forensics"]

    # 1. Malicious IP
    assert "Malicious_IP" in forensics, "Key 'Malicious_IP' is missing."
    assert forensics["Malicious_IP"] == "10.0.0.88", f"Incorrect Malicious_IP. Found: {forensics['Malicious_IP']}"

    # 2. Vulnerable Line Number
    assert "Vulnerable_Line_Number" in forensics, "Key 'Vulnerable_Line_Number' is missing."
    assert forensics["Vulnerable_Line_Number"] == "9", f"Incorrect Vulnerable_Line_Number. Found: {forensics['Vulnerable_Line_Number']}"

    # 3. Insecure SSH Config
    assert "Insecure_SSH_Config" in forensics, "Key 'Insecure_SSH_Config' is missing."
    assert forensics["Insecure_SSH_Config"] == "PermitRootLogin yes", f"Incorrect Insecure_SSH_Config. Found: {forensics['Insecure_SSH_Config']}"

    # 4. Compromised Binary
    assert "Compromised_Binary" in forensics, "Key 'Compromised_Binary' is missing."
    assert forensics["Compromised_Binary"] == "systemd-resolve", f"Incorrect Compromised_Binary. Found: {forensics['Compromised_Binary']}"

    # 5. C2 Domain
    assert "C2_Domain" in forensics, "Key 'C2_Domain' is missing."
    assert forensics["C2_Domain"] == "c2.evil-hacker-empire.xyz", f"Incorrect C2_Domain. Found: {forensics['C2_Domain']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
