#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def compute_expected_results():
    # Derive the XOR key from the known 'guest' token
    # The first character of 'guest' is 'g' (0x67)
    # The first byte of the token '2537273136' is '25' (0x25)
    known_char = 'g'
    known_hex_byte = '25'
    xor_key = ord(known_char) ^ int(known_hex_byte, 16)

    # Compute the token for 'admin'
    admin_token = "".join(f"{ord(c) ^ xor_key:02x}" for c in "admin")

    # Parse the log file to find matching IPs
    log_file_path = "/home/user/auth_logs.txt"
    matching_ips = set()

    if os.path.exists(log_file_path):
        with open(log_file_path, "r") as f:
            for line in f:
                # Match line format: [TIMESTAMP] IP=<ip_address> USER=<username> TOKEN=<hex_token> STATUS=<SUCCESS|FAILED>
                ip_match = re.search(r"IP=([^\s]+)", line)
                user_match = re.search(r"USER=([^\s]+)", line)
                token_match = re.search(r"TOKEN=([^\s]+)", line)
                status_match = re.search(r"STATUS=([^\s]+)", line)

                if ip_match and user_match and token_match and status_match:
                    ip = ip_match.group(1)
                    user = user_match.group(1)
                    token = token_match.group(1)
                    status = status_match.group(1)

                    if user == "admin" and token == admin_token and status == "SUCCESS":
                        matching_ips.add(ip)

    sorted_ips = sorted(list(matching_ips))
    return admin_token, sorted_ips

def test_compromise_report_exists_and_correct():
    report_file_path = "/home/user/compromise_report.txt"

    assert os.path.isfile(report_file_path), f"The report file {report_file_path} was not created."

    expected_token, expected_ips = compute_expected_results()

    with open(report_file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"The report file {report_file_path} is empty."

    actual_token = lines[0]
    assert actual_token == expected_token, (
        f"The computed token for 'admin' is incorrect. "
        f"Expected '{expected_token}', but found '{actual_token}'."
    )

    actual_ips = lines[1:]
    assert actual_ips == expected_ips, (
        f"The list of IP addresses is incorrect or not properly sorted. "
        f"Expected {expected_ips}, but found {actual_ips}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
