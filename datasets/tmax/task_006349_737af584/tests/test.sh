#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_attacker_ip_correct():
    ip_file = "/home/user/attacker_ip.txt"
    assert os.path.isfile(ip_file), f"Expected output file {ip_file} does not exist."

    with open(ip_file, "r") as f:
        content = f.read().strip()

    expected_ip = "192.168.100.42"
    assert content == expected_ip, f"Contents of {ip_file} are incorrect. Expected '{expected_ip}', got '{content}'."

def test_decrypted_data_correct():
    data_file = "/home/user/decrypted_data.txt"
    assert os.path.isfile(data_file), f"Expected output file {data_file} does not exist."

    with open(data_file, "r") as f:
        content = f.read().strip()

    expected_data = "CONFIDENTIAL_FINANCIAL_DATA_Q3_2023"
    assert content == expected_data, f"Contents of {data_file} are incorrect. Expected '{expected_data}', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
