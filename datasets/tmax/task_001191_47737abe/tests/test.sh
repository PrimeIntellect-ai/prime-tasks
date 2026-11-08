#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
from collections import defaultdict

def test_audit_report_exists_and_valid_json():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Expected output file missing: {report_path}"

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert isinstance(data, dict), "JSON root must be an object (dictionary)."
    assert "successful_sessions" in data, "Missing 'successful_sessions' key in JSON report."
    assert "suspicious_ips" in data, "Missing 'suspicious_ips' key in JSON report."

def test_audit_report_contents():
    access_log_path = "/home/user/access.log"
    app_log_path = "/home/user/app.log"
    report_path = "/home/user/audit_report.json"

    assert os.path.isfile(access_log_path), f"File missing: {access_log_path}"
    assert os.path.isfile(app_log_path), f"File missing: {app_log_path}"
    assert os.path.isfile(report_path), f"File missing: {report_path}"

    # Parse app.log
    success_corr_ids = set()
    failed_corr_ids = set()

    with open(app_log_path, 'r') as f:
        for line in f:
            match = re.search(r'\[CorrID:\s*(.*?)\]\s*Event:\s*(\S+)', line)
            if match:
                corr_id = match.group(1)
                event = match.group(2)
                if event == "LOGIN_SUCCESS":
                    success_corr_ids.add(corr_id)
                elif event == "LOGIN_FAILED":
                    failed_corr_ids.add(corr_id)

    # Parse access.log
    expected_sessions = []
    failed_ip_counts = defaultdict(int)

    with open(access_log_path, 'r') as f:
        for line in f:
            # Extract IP
            ip_match = re.search(r'\]\s*([0-9\.]+)\s+', line)
            if not ip_match:
                continue
            ip = ip_match.group(1)

            # Extract Headers JSON
            headers_match = re.search(r'Headers:\s*(\{.*\})', line)
            if not headers_match:
                continue

            try:
                headers = json.loads(headers_match.group(1))
            except json.JSONDecodeError:
                continue

            corr_id = headers.get("X-Correlation-ID")
            cookie_str = headers.get("Cookie", "")

            # Extract session_id
            session_id = None
            for part in cookie_str.split(';'):
                part = part.strip()
                if part.startswith("session_id="):
                    val = part.split("=", 1)[1]
                    if val:
                        session_id = val
                    break

            if corr_id in success_corr_ids and session_id:
                expected_sessions.append(session_id)

            if corr_id in failed_corr_ids:
                failed_ip_counts[ip] += 1

    expected_suspicious_ips = [ip for ip, count in failed_ip_counts.items() if count > 2]

    expected_sessions = sorted(expected_sessions)
    expected_suspicious_ips = sorted(expected_suspicious_ips)

    with open(report_path, 'r') as f:
        data = json.load(f)

    actual_sessions = data.get("successful_sessions", [])
    actual_ips = data.get("suspicious_ips", [])

    assert actual_sessions == expected_sessions, (
        f"Expected successful_sessions to be {expected_sessions}, but got {actual_sessions}"
    )

    assert actual_ips == expected_suspicious_ips, (
        f"Expected suspicious_ips to be {expected_suspicious_ips}, but got {actual_ips}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
