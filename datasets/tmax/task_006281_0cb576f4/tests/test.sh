#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import xml.etree.ElementTree as ET
import pytest

def test_audit_report():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/suspicious/normal_file.txt",
        "/home/user/suspicious/subdir/world_write.conf",
        "/home/user/suspicious/suid_bin"
    ]

    assert lines == expected_lines, f"Audit report contents are incorrect. Expected {expected_lines}, got {lines}"

def test_audit_script_exists():
    script_path = "/home/user/audit_privesc.sh"
    assert os.path.isfile(script_path), f"Audit script not found at {script_path}"

def test_vuln_report_xml():
    report_path = "/home/user/vuln_report.xml"
    assert os.path.isfile(report_path), f"Vulnerability report not found at {report_path}"

    try:
        tree = ET.parse(report_path)
        root = tree.getroot()
    except ET.ParseError as e:
        pytest.fail(f"Vulnerability report is not a valid XML file: {e}")

def test_compiled_binary_exists():
    binary_path = "/home/user/log_analyzer/bin/analyzer"
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Compiled binary at {binary_path} is not executable"

def test_clean_output_log():
    output_path = "/home/user/data/clean_output.log"
    assert os.path.isfile(output_path), f"Clean output log not found at {output_path}"

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "[INFO] CHAIN: Client1|IntCA1, IntCA1|RootCA MESSAGE: User ************1234 logged in.",
        "[INFO] CHAIN: Client3|RootCA MESSAGE: Payment ************6666 done.",
        "[INFO] CHAIN: Client4|IntCA4, IntCA4|IntCA5, IntCA5|RootCA MESSAGE: Card ************4444 approved."
    ]

    assert lines == expected_lines, "Clean output log contents do not match expected output. Check your certificate validation and redaction logic."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
