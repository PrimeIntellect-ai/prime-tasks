#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

CLEAN_LOG_PATH = "/home/user/compliance_clean.log"
FIREWALL_SCRIPT_PATH = "/home/user/firewall_block.sh"

EXPECTED_CLEAN_LOG = """192.168.1.50 - [12/Oct/2023:10:00:01 +0000] "GET /login?user=alice&password=[REDACTED]&redirect_url=/dashboard HTTP/1.1" 200
203.0.113.42 - [12/Oct/2023:10:05:12 +0000] "GET /login?user=bob&password=[REDACTED]&redirect_url=https://evil-phishing.com/login HTTP/1.1" 302
192.168.1.51 - [12/Oct/2023:10:10:00 +0000] "GET /login?user=charlie&password=[REDACTED]&redirect_url=https://internal.company.local/settings HTTP/1.1" 200
198.51.100.7 - [12/Oct/2023:10:15:33 +0000] "GET /login?user=admin&password=[REDACTED]&redirect_url=http://malicious.site.net/payload HTTP/1.1" 302
203.0.113.42 - [12/Oct/2023:10:20:00 +0000] "GET /login?user=dave&password=[REDACTED]&redirect_url=https://attacker.com/drop HTTP/1.1" 302"""

EXPECTED_FIREWALL_SCRIPT = """#!/bin/bash
iptables -A INPUT -s 198.51.100.7 -j DROP
iptables -A INPUT -s 203.0.113.42 -j DROP"""

def test_compliance_clean_log_exists():
    assert os.path.exists(CLEAN_LOG_PATH), f"The file {CLEAN_LOG_PATH} was not created."
    assert os.path.isfile(CLEAN_LOG_PATH), f"The path {CLEAN_LOG_PATH} exists but is not a regular file."

def test_compliance_clean_log_content():
    with open(CLEAN_LOG_PATH, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == EXPECTED_CLEAN_LOG, (
        f"The content of {CLEAN_LOG_PATH} does not match the expected redacted output. "
        "Ensure passwords are replaced with '[REDACTED]' and no other parts of the log are modified."
    )

def test_firewall_script_exists_and_executable():
    assert os.path.exists(FIREWALL_SCRIPT_PATH), f"The script {FIREWALL_SCRIPT_PATH} was not created."
    assert os.path.isfile(FIREWALL_SCRIPT_PATH), f"The path {FIREWALL_SCRIPT_PATH} is not a file."
    assert os.access(FIREWALL_SCRIPT_PATH, os.X_OK), f"The script {FIREWALL_SCRIPT_PATH} does not have executable permissions."

def test_firewall_script_content():
    with open(FIREWALL_SCRIPT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    actual_content = "\n".join(lines)
    assert actual_content == EXPECTED_FIREWALL_SCRIPT, (
        f"The content of {FIREWALL_SCRIPT_PATH} is incorrect. "
        "It must start with '#!/bin/bash', contain exactly the iptables drop rules for the malicious IPs, "
        "and be sorted alphabetically by IP address."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
