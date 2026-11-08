#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_decrypted_audit_log():
    """
    Validates that the decrypted audit log exists and matches the expected plaintext.
    """
    expected_log = (
        "[2023-10-15 08:12:00] SUCCESS User admin logged in.\n"
        "[2023-10-15 08:45:12] FAILED Login from 192.168.45.10\n"
        "[2023-10-15 09:02:33] FAILED Login from 10.100.2.55\n"
        "[2023-10-15 09:15:00] SUCCESS User system_service logged in."
    )

    log_path = "/home/user/decrypted_audit.log"
    assert os.path.isfile(log_path), f"Decrypted log file not found at {log_path}"

    with open(log_path, "r") as f:
        actual_log = f.read().strip()

    assert actual_log == expected_log, "The decrypted audit log contents do not match the expected plaintext."

def test_cwe_report():
    """
    Validates that the CWE report exists and contains the correct CWE ID.
    """
    report_path = "/home/user/cwe_report.txt"
    assert os.path.isfile(report_path), f"CWE report file not found at {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert content == "CWE-321", f"Expected CWE-321 in {report_path}, but found: '{content}'"

def test_firewall_block_script():
    """
    Validates that the firewall block script exists and contains the correct iptables commands.
    """
    script_path = "/home/user/firewall_block.sh"
    assert os.path.isfile(script_path), f"Firewall block script not found at {script_path}"

    expected_commands = [
        "iptables -A INPUT -s 192.168.45.10 -j DROP",
        "iptables -A INPUT -s 10.100.2.55 -j DROP"
    ]

    with open(script_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_commands), f"Expected {len(expected_commands)} commands, but found {len(lines)}."

    for expected in expected_commands:
        assert expected in lines, f"Missing expected iptables command: '{expected}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
