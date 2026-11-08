#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import hashlib
import pytest

REPORT_PATH = "/home/user/report.json"
REDACTED_PATH = "/home/user/audit/messages_redacted.txt"

def test_report_json_exists():
    """Test that the deliverable report.json exists."""
    assert os.path.exists(REPORT_PATH), f"File {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."

def test_report_json_structure_and_content():
    """Test that report.json contains the correct findings."""
    assert os.path.exists(REPORT_PATH), "report.json is missing."
    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} does not contain valid JSON.")

    # 1. Tampered File
    assert "tampered_file" in report, "Key 'tampered_file' missing from report."
    assert report["tampered_file"] == "messages.txt", "Incorrect tampered file identified."

    # 2. Cracked Passwords
    assert "cracked_passwords" in report, "Key 'cracked_passwords' missing from report."
    expected_passwords = {
        "admin": "admin2023",
        "alice": "hunter2",
        "bob": "qwerty"
    }
    assert report["cracked_passwords"] == expected_passwords, "Cracked passwords do not match the expected values."

    # 3. Vulnerabilities
    assert "vulnerabilities" in report, "Key 'vulnerabilities' missing from report."
    vulns = report["vulnerabilities"]
    assert vulns.get("sqli_line") == 13, "Incorrect line number for SQLi vulnerability."
    assert vulns.get("xss_line") == 21, "Incorrect line number for XSS vulnerability."

def test_messages_redacted_exists():
    """Test that the redacted messages file was created."""
    assert os.path.exists(REDACTED_PATH), f"File {REDACTED_PATH} does not exist."
    assert os.path.isfile(REDACTED_PATH), f"{REDACTED_PATH} is not a file."

def test_messages_redacted_content():
    """Test that the credit card numbers were properly redacted."""
    assert os.path.exists(REDACTED_PATH), f"File {REDACTED_PATH} does not exist."
    with open(REDACTED_PATH, "r") as f:
        content = f.read()

    # Check that the specific credit cards are redacted
    assert "XXXX-XXXX-XXXX-4444" in content, "First credit card was not correctly redacted."
    assert "XXXX-XXXX-XXXX-8888" in content, "Second credit card was not correctly redacted."

    # Check that the original unredacted numbers are gone
    assert "4111-2222-3333-4444" not in content, "Original first credit card number is still present."
    assert "5555-6666-7777-8888" not in content, "Original second credit card number is still present."

    # Check that the tampered appended line is still there
    assert "P.S. Call me back." in content, "The appended tampered text was removed or altered."

def test_redacted_hash_matches_report():
    """Test that the redacted_hash in the report matches the actual sha256 of the redacted file."""
    assert os.path.exists(REPORT_PATH), "report.json is missing."
    assert os.path.exists(REDACTED_PATH), "messages_redacted.txt is missing."

    with open(REPORT_PATH, "r") as f:
        report = json.load(f)

    assert "redacted_hash" in report, "Key 'redacted_hash' missing from report."

    with open(REDACTED_PATH, "rb") as f:
        file_bytes = f.read()

    actual_hash = hashlib.sha256(file_bytes).hexdigest()
    assert report["redacted_hash"] == actual_hash, f"Report hash {report['redacted_hash']} does not match actual file hash {actual_hash}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
