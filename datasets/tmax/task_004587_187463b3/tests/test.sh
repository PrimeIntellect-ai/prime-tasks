#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

def test_phase1_c2_ip():
    c2_ip_path = "/home/user/c2_ip.txt"
    assert os.path.isfile(c2_ip_path), f"File {c2_ip_path} does not exist."
    with open(c2_ip_path, "r") as f:
        content = f.read().strip()
    assert content == "123.192.34.56", f"Expected IP '123.192.34.56', but got '{content}' in {c2_ip_path}."

def test_phase2_vulnerability():
    vuln_path = "/home/user/vulnerability.txt"
    assert os.path.isfile(vuln_path), f"File {vuln_path} does not exist."
    with open(vuln_path, "r") as f:
        content = f.read().strip()
    assert content.upper() == "CWE-78", f"Expected 'CWE-78', but got '{content}' in {vuln_path}."

def test_phase3_ssh_hardening():
    hardened_path = "/home/user/hardened_sshd_config"
    assert os.path.isfile(hardened_path), f"File {hardened_path} does not exist."

    expected_content = """# Standard SSH config
Port 22
Protocol 2

# Authentication:
LoginGraceTime 2m
PermitRootLogin no
StrictModes yes
MaxAuthTries 6
MaxSessions 10

# To disable tunneled clear text passwords, change to no here!
PasswordAuthentication no
PermitEmptyPasswords no

# Forwarding
X11Forwarding no"""

    with open(hardened_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"The contents of {hardened_path} do not exactly match the expected hardened configuration."

def test_phase4_csp():
    csp_path = "/home/user/csp_meta.txt"
    assert os.path.isfile(csp_path), f"File {csp_path} does not exist."
    with open(csp_path, "r") as f:
        content = f.read().strip()

    # Check for presence of key components, allowing for single/double quote variations
    assert content.startswith("<meta") and content.endswith(">"), f"{csp_path} does not contain a valid <meta> tag."

    # Normalize quotes to simplify checking
    normalized_content = content.replace("'", '"')

    assert 'http-equiv="Content-Security-Policy"' in normalized_content or "http-equiv=Content-Security-Policy" in normalized_content, \
        f"{csp_path} is missing the correct http-equiv attribute."

    assert 'content="default-src "self""' in normalized_content or 'content="default-src \'self\'"' in content, \
        f"{csp_path} does not contain the correct content attribute for default-src 'self'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
