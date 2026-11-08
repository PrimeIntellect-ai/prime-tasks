#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import re
import pytest

REPORT_PATH = "/home/user/audit_report.txt"
BASE_DIR = "/home/user/audit"
EXPECTED_REPORT = """[PERMISSIONS]
cache_tmp.txt
config_local.json

[CERTIFICATES]
leaf3.pem

[VULNERABILITIES]
search.php

[FIREWALL]
3306
"""

def get_expected_permissions():
    code_dir = os.path.join(BASE_DIR, "code")
    world_writable = []
    if os.path.isdir(code_dir):
        for f in os.listdir(code_dir):
            path = os.path.join(code_dir, f)
            if os.path.isfile(path):
                st = os.stat(path)
                if bool(st.st_mode & stat.S_IWOTH):
                    world_writable.append(f)
    return sorted(world_writable)

def get_expected_invalid_cert():
    certs_dir = os.path.join(BASE_DIR, "certs")
    ca_file = os.path.join(certs_dir, "ca.pem")
    invalid_certs = []
    if os.path.isdir(certs_dir) and os.path.isfile(ca_file):
        for f in os.listdir(certs_dir):
            if f.startswith("leaf") and f.endswith(".pem"):
                path = os.path.join(certs_dir, f)
                result = subprocess.run(
                    ["openssl", "verify", "-CAfile", ca_file, path],
                    capture_output=True,
                    text=True
                )
                if result.returncode != 0 or "error" in result.stdout.lower() or "error" in result.stderr.lower():
                    invalid_certs.append(f)
    return invalid_certs

def get_expected_vulnerability():
    code_dir = os.path.join(BASE_DIR, "code")
    vuln_files = []
    if os.path.isdir(code_dir):
        for f in os.listdir(code_dir):
            if f.endswith(".php"):
                path = os.path.join(code_dir, f)
                with open(path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                    if "$_GET" in content and "echo" in content and "htmlspecialchars" not in content:
                        vuln_files.append(f)
    return vuln_files

def get_expected_firewall_port():
    rules_file = os.path.join(BASE_DIR, "firewall", "iptables.rules")
    exposed_ports = []
    if os.path.isfile(rules_file):
        with open(rules_file, "r") as f:
            for line in f:
                line = line.strip()
                if "-j ACCEPT" in line and "-p tcp" in line and "--dport" in line:
                    if "-s " not in line:
                        match = re.search(r"--dport\s+(\d+)", line)
                        if match:
                            port = match.group(1)
                            if port not in ["80", "443"]:
                                exposed_ports.append(port)
    return exposed_ports

def parse_report(filepath):
    sections = {
        "PERMISSIONS": [],
        "CERTIFICATES": [],
        "VULNERABILITIES": [],
        "FIREWALL": []
    }
    if not os.path.exists(filepath):
        return sections

    with open(filepath, "r") as f:
        current_section = None
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("[") and line.endswith("]"):
                sec_name = line[1:-1]
                if sec_name in sections:
                    current_section = sec_name
            elif current_section:
                sections[current_section].append(line)
    return sections

@pytest.fixture(scope="module")
def parsed_report():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    return parse_report(REPORT_PATH)

def test_report_exact_content():
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        assert f.read() == EXPECTED_REPORT

def test_permissions_section(parsed_report):
    expected = get_expected_permissions()
    reported = parsed_report.get("PERMISSIONS", [])
    assert reported == expected, f"Expected world-writable files {expected}, but report had {reported}"

def test_certificates_section(parsed_report):
    expected = get_expected_invalid_cert()
    reported = parsed_report.get("CERTIFICATES", [])
    assert reported == expected, f"Expected invalid certificates {expected}, but report had {reported}"

def test_vulnerabilities_section(parsed_report):
    expected = get_expected_vulnerability()
    reported = parsed_report.get("VULNERABILITIES", [])
    assert reported == expected, f"Expected vulnerable files {expected}, but report had {reported}"

def test_firewall_section(parsed_report):
    expected = get_expected_firewall_port()
    reported = parsed_report.get("FIREWALL", [])
    assert reported == expected, f"Expected exposed firewall ports {expected}, but report had {reported}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
