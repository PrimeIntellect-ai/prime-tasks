#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import pytest

ORIGINAL_LOG = """[INFO] Application started
[DEBUG] User login attempt: admin
[WARN] Failed transaction for card 1234-5678-9012-3456 due to insufficient funds
[INFO] Cache cleared
[WARN] Failed transaction for card 9876-5432-1098-7654 due to invalid CVV
[INFO] User logout
[DEBUG] Processing batch for cards 1111-2222-3333-4444 and 5555-6666-7777-8888
[INFO] System shutting down
"""

CC_PATTERN = re.compile(r'\b\d{4}-\d{4}-\d{4}-\d{4}\b')
EXPECTED_REDACTED_LOG = CC_PATTERN.sub("[REDACTED]", ORIGINAL_LOG)
EXPECTED_MODIFIED_LINES = sum(
    1
    for original, redacted in zip(
        ORIGINAL_LOG.splitlines(keepends=True),
        EXPECTED_REDACTED_LOG.splitlines(keepends=True),
    )
    if original != redacted
)


def load_report():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The final report file {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The report file is not valid JSON.")


def test_report_exists_and_valid():
    report_data = load_report()

    assert "admin_password" in report_data, "Missing 'admin_password' in report."
    assert report_data["admin_password"] == "purplemonkey", "Incorrect admin_password. Did you crack the hash correctly?"

    assert "cert_valid" in report_data, "Missing 'cert_valid' in report."
    assert report_data["cert_valid"] is False, "Incorrect cert_valid value. The certificate chain should be invalid."

    assert "cwe_vulnerability" in report_data, "Missing 'cwe_vulnerability' in report."
    assert report_data["cwe_vulnerability"].upper() == "CWE-78", "Incorrect cwe_vulnerability. Look closely at the OS command execution."

    assert "redacted_log_lines_count" in report_data, "Missing 'redacted_log_lines_count' in report."
    assert report_data["redacted_log_lines_count"] == 3, "Incorrect redacted_log_lines_count. Check how many lines contained credit card numbers."
    assert report_data["redacted_log_lines_count"] == EXPECTED_MODIFIED_LINES


def test_redacted_log_file():
    source_log_path = "/home/user/app_backup/app.log"
    redacted_log_path = "/home/user/app_backup/app_redacted.log"
    assert os.path.isfile(source_log_path), f"The original log file {source_log_path} does not exist."
    assert os.path.isfile(redacted_log_path), f"The redacted log file {redacted_log_path} does not exist."

    with open(source_log_path, "r") as f:
        source_content = f.read()
    with open(redacted_log_path, "r") as f:
        content = f.read()

    assert source_content == ORIGINAL_LOG, "The original application log was modified."

    # Preserve the original checks.
    assert not CC_PATTERN.search(content), "Found unredacted credit card numbers in the redacted log file."
    assert "[REDACTED]" in content, "The exact string '[REDACTED]' was not found in the redacted log file."
    redaction_count = content.count("[REDACTED]")
    assert redaction_count == 4, f"Expected 4 replacements of '[REDACTED]', but found {redaction_count}."

    # Verify the artifact is exactly the original log with only card numbers replaced.
    assert content == EXPECTED_REDACTED_LOG, (
        "The redacted log must preserve the complete original log and replace only "
        "credit card numbers with '[REDACTED]'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
