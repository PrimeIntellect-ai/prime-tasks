#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def test_firewall_block_script():
    script_path = "/home/user/firewall_block.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    # Look for a line that looks like the required iptables command
    lines = content.strip().split("\n")
    found_valid_rule = False

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        # Check components of the iptables command
        has_iptables = line.startswith("iptables ")
        has_append = "-A OUTPUT" in line or "--append OUTPUT" in line
        has_dest = "-d 203.0.113.85" in line or "--destination 203.0.113.85" in line
        has_proto = "-p tcp" in line or "--protocol tcp" in line
        has_dport = "--dport 4444" in line or "--destination-port 4444" in line
        has_drop = "-j DROP" in line or "--jump DROP" in line

        if has_iptables and has_append and has_dest and has_proto and has_dport and has_drop:
            found_valid_rule = True
            break

    assert found_valid_rule, f"Script {script_path} does not contain the correct iptables command."

def test_recovered_data():
    data_path = "/home/user/recovered_data.txt"
    assert os.path.isfile(data_path), f"Recovered data file {data_path} does not exist."

    with open(data_path, "r") as f:
        content = f.read()

    expected_content = "MISSION_ACCOMPLISHED_EVIDENCE_SECURED"
    assert content.strip() == expected_content, f"Content of {data_path} does not match the expected decrypted text."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
