#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_decrypted_audit_log():
    """Verify that the decrypted audit log exists and contains the correct plaintext."""
    decrypted_path = '/home/user/decrypted_audit.txt'
    assert os.path.exists(decrypted_path), f"Decrypted file not found at {decrypted_path}"

    with open(decrypted_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_content = "[AUDIT_START] Server compliance check passed. Token: COMPLIANCE-8821-XRT."
    assert content == expected_content, f"Decrypted content is incorrect. Expected '{expected_content}', but got '{content}'."

def test_remediation_script():
    """Verify that the remediation script exists and contains the exact iptables command."""
    script_path = '/home/user/remediation.sh'
    assert os.path.exists(script_path), f"Remediation script not found at {script_path}"

    with open(script_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected_command = "iptables -A OUTPUT -d 203.0.113.85 -p tcp --dport 443 -j DROP"
    assert content == expected_command, f"Remediation script content is incorrect. Expected '{expected_command}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
