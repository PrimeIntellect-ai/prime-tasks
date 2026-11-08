#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

ACCESS_LOG = "/home/user/access.log"
DUMP_CSV = "/home/user/compromised_db_dump.csv"
REDACTED_CSV = "/home/user/redacted_evidence.csv"
REPORT_TXT = "/home/user/forensics_report.txt"

def get_expected_attack_details():
    assert os.path.isfile(ACCESS_LOG), f"Missing original access log: {ACCESS_LOG}"
    attacker_ip = None
    attack_time = None

    with open(ACCESS_LOG, "r") as f:
        for line in f:
            # Look for HTTP status 200 and SQLi keywords
            if " 200 " in line and ("UNION" in line or "SELECT" in line):
                # Example line:
                # 192.168.1.42 - - [14/Nov/2023:09:42:01 +0000] "GET /products?id=1'%20UNION%20SELECT... HTTP/1.1" 200 8943
                match = re.match(r'^(\S+)\s+\S+\s+\S+\s+\[(.*?)\]', line)
                if match:
                    attacker_ip = match.group(1)
                    attack_time = match.group(2)
                    break

    return attacker_ip, attack_time

def get_expected_redacted_content_and_count():
    assert os.path.isfile(DUMP_CSV), f"Missing original DB dump: {DUMP_CSV}"

    with open(DUMP_CSV, "r") as f:
        lines = f.read().strip().split('\n')

    if not lines:
        return "", 0

    header = lines[0]
    records = lines[1:]

    redacted_lines = [header]
    for record in records:
        # Redact SSN
        record = re.sub(r'\b\d{3}-\d{2}-\d{4}\b', 'XXX-XX-XXXX', record)
        # Redact CC
        record = re.sub(r'\b\d{4}-\d{4}-\d{4}-\d{4}\b', 'XXXX-XXXX-XXXX-XXXX', record)
        redacted_lines.append(record)

    return "\n".join(redacted_lines), len(records)

def test_redacted_evidence_csv():
    assert os.path.isfile(REDACTED_CSV), f"Redacted evidence file not found at {REDACTED_CSV}"

    expected_content, _ = get_expected_redacted_content_and_count()

    with open(REDACTED_CSV, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, "The redacted evidence CSV does not match the expected redacted output."

def test_forensics_report():
    assert os.path.isfile(REPORT_TXT), f"Forensics report not found at {REPORT_TXT}"

    expected_ip, expected_time = get_expected_attack_details()
    assert expected_ip is not None and expected_time is not None, "Could not determine expected attack details from access log."

    _, expected_count = get_expected_redacted_content_and_count()

    with open(REPORT_TXT, "r") as f:
        report_content = f.read().strip()

    expected_report = (
        f"Attacker IP: {expected_ip}\n"
        f"Attack Timestamp: {expected_time}\n"
        f"Redacted Records: {expected_count}"
    )

    assert report_content == expected_report, (
        f"Forensics report content is incorrect.\n"
        f"Expected:\n{expected_report}\n\n"
        f"Actual:\n{report_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
