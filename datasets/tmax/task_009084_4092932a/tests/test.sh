#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import re
import pytest

def test_exfil_package_exists_and_valid():
    exfil_path = "/home/user/exfil_package.json"
    assert os.path.exists(exfil_path), f"Expected output file {exfil_path} does not exist."
    assert os.path.isfile(exfil_path), f"Path {exfil_path} is not a file."

    with open(exfil_path, "r", encoding="utf-8") as f:
        try:
            exfil_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"File {exfil_path} is not valid JSON. Error: {e}")

    assert isinstance(exfil_data, dict), f"JSON root in {exfil_path} must be an object/dictionary."

    expected_keys = {"auth_token", "exfil_port", "redacted_data"}
    missing_keys = expected_keys - exfil_data.keys()
    assert not missing_keys, f"Missing expected keys in JSON: {missing_keys}"

def test_auth_token_correct():
    exfil_path = "/home/user/exfil_package.json"
    with open(exfil_path, "r", encoding="utf-8") as f:
        exfil_data = json.load(f)

    # The token is hardcoded in the binary setup
    expected_token = "Ecl1ps3_R3d_99!"
    assert exfil_data["auth_token"] == expected_token, \
        f"Incorrect auth_token. Expected '{expected_token}', got '{exfil_data['auth_token']}'."

def test_exfil_port_correct():
    fw_rules_path = "/home/user/fw_rules.txt"
    exfil_path = "/home/user/exfil_package.json"

    # Derive the expected port from the firewall rules
    expected_port = None
    with open(fw_rules_path, "r", encoding="utf-8") as f:
        for line in f:
            if "-d 203.0.113.10/32" in line and "--dport" in line:
                match = re.search(r"--dport\s+(\d+)", line)
                if match:
                    expected_port = int(match.group(1))
                    break

    assert expected_port is not None, "Could not derive expected port from firewall rules."

    with open(exfil_path, "r", encoding="utf-8") as f:
        exfil_data = json.load(f)

    assert exfil_data["exfil_port"] == expected_port, \
        f"Incorrect exfil_port. Expected {expected_port}, got {exfil_data['exfil_port']}."

def test_redacted_data_correct():
    customer_data_path = "/home/user/customer_data.txt"
    exfil_path = "/home/user/exfil_package.json"

    # Derive the expected redacted data by applying the redaction rules
    with open(customer_data_path, "r", encoding="utf-8") as f:
        original_data = f.read()

    # Regex to match 16 contiguous digits or 4 blocks of 4 digits separated by dashes
    cc_pattern = re.compile(r'\b(?:\d{4}-\d{4}-\d{4}-\d{4}|\d{16})\b')
    expected_redacted_data = cc_pattern.sub("[REDACTED]", original_data)

    with open(exfil_path, "r", encoding="utf-8") as f:
        exfil_data = json.load(f)

    assert exfil_data["redacted_data"] == expected_redacted_data, \
        "The redacted_data does not match the expected redacted content. Ensure only 16-digit credit cards (with or without dashes) are replaced with '[REDACTED]'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
