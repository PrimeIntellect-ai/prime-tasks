#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

REPORT_PATH = '/home/user/security_report.txt'

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."

def get_report_sections():
    with open(REPORT_PATH, 'r') as f:
        content = f.read()

    sections = {}
    current_section = None
    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith('[') and line.endswith(']'):
            current_section = line
            sections[current_section] = []
        elif current_section:
            sections[current_section].append(line)

    return sections

def test_report_malicious_responses():
    sections = get_report_sections()
    assert '[Malicious Responses]' in sections, "Missing '[Malicious Responses]' section in the report."

    malicious = sections['[Malicious Responses]']
    expected_line = "102:22ea0d2a5cf3ba5bb619ca2ee62df00e5ba6445582c0697d264f331cf1ea80f6"
    assert expected_line in malicious, f"Expected '{expected_line}' in [Malicious Responses], found: {malicious}"
    assert len(malicious) == 1, f"Expected exactly 1 malicious response, found {len(malicious)}."

def test_report_weak_csp_responses():
    sections = get_report_sections()
    assert '[Weak CSP Responses]' in sections, "Missing '[Weak CSP Responses]' section in the report."

    weak_csp = sections['[Weak CSP Responses]']
    expected_lines = ["102", "103"]
    assert weak_csp == expected_lines, f"Expected Weak CSP Responses to be {expected_lines}, but found {weak_csp}. Ensure they are sorted."

def test_report_cgi_vulnerabilities():
    sections = get_report_sections()
    assert '[CGI Vulnerabilities]' in sections, "Missing '[CGI Vulnerabilities]' section in the report."

    cgi_vulns = sections['[CGI Vulnerabilities]']
    expected_lines = [
        "download.cgi:CWE-22",
        "greet.cgi:CWE-79",
        "ping.cgi:CWE-78"
    ]
    assert cgi_vulns == expected_lines, f"Expected CGI Vulnerabilities to be {expected_lines}, but found {cgi_vulns}. Ensure they are sorted alphabetically."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
