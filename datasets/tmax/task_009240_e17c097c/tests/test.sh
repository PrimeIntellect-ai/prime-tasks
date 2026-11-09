#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

REPORT_PATH = "/home/user/audit_report.txt"

def parse_report(filepath):
    sections = {}
    current_section = None
    with open(filepath, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("[") and line.endswith("]"):
                current_section = line
                sections[current_section] = ""
            elif current_section:
                sections[current_section] = line
    return sections

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The final report file {REPORT_PATH} is missing."

def test_report_vulnerable_endpoints():
    sections = parse_report(REPORT_PATH)
    assert "[VULNERABLE_ENDPOINTS]" in sections, "Missing [VULNERABLE_ENDPOINTS] section in the report."

    expected = "/api/v1/legacy_login,/api/v1/profile"
    actual = sections["[VULNERABLE_ENDPOINTS]"]

    assert actual == expected, f"Expected [VULNERABLE_ENDPOINTS] to be '{expected}', but got '{actual}'."

def test_report_tampered_files():
    sections = parse_report(REPORT_PATH)
    assert "[TAMPERED_FILES]" in sections, "Missing [TAMPERED_FILES] section in the report."

    expected = "/home/user/audit/www/index.html,/home/user/audit/www/js/app.js"
    actual = sections["[TAMPERED_FILES]"]

    assert actual == expected, f"Expected [TAMPERED_FILES] to be '{expected}', but got '{actual}'."

def test_report_world_writable_tampered():
    sections = parse_report(REPORT_PATH)
    assert "[WORLD_WRITABLE_TAMPERED]" in sections, "Missing [WORLD_WRITABLE_TAMPERED] section in the report."

    expected = "/home/user/audit/www/index.html"
    actual = sections["[WORLD_WRITABLE_TAMPERED]"]

    assert actual == expected, f"Expected [WORLD_WRITABLE_TAMPERED] to be '{expected}', but got '{actual}'."

def test_report_malicious_domains():
    sections = parse_report(REPORT_PATH)
    assert "[MALICIOUS_DOMAINS]" in sections, "Missing [MALICIOUS_DOMAINS] section in the report."

    expected = "bad-actor.io"
    actual = sections["[MALICIOUS_DOMAINS]"]

    assert actual == expected, f"Expected [MALICIOUS_DOMAINS] to be '{expected}', but got '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
