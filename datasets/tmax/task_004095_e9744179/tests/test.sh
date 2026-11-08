#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import urllib.parse
import pytest

def test_audit_report_exists():
    assert os.path.isfile("/home/user/audit_report.json"), "The audit report file /home/user/audit_report.json was not created."

def test_audit_report_content():
    log_file_path = "/home/user/logs/upload.log"
    base_upload_dir = "/home/user/server_root/uploads/"

    assert os.path.isfile(log_file_path), "Log file is missing."

    expected_findings = []

    with open(log_file_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split(" ")
            if len(parts) != 4:
                continue

            timestamp, method, url, status = parts

            if method != "POST":
                continue
            if status != "200":
                continue

            url_parts = urllib.parse.urlparse(url)
            if url_parts.path != "/api/upload":
                continue

            query = urllib.parse.parse_qs(url_parts.query)
            if "filename" not in query:
                continue

            filename = query["filename"][0]

            # Resolve path
            resolved_path = os.path.abspath(os.path.join(base_upload_dir, filename))

            # Check if strictly outside
            if not resolved_path.startswith(os.path.abspath(base_upload_dir) + os.sep):
                if os.path.isfile(resolved_path):
                    # Compute hash
                    sha256_hash = hashlib.sha256()
                    with open(resolved_path, "rb") as f_target:
                        for byte_block in iter(lambda: f_target.read(4096), b""):
                            sha256_hash.update(byte_block)

                    expected_findings.append({
                        "timestamp": timestamp,
                        "provided_filename": filename,
                        "resolved_path": resolved_path,
                        "sha256": sha256_hash.hexdigest(),
                        "cwe": "CWE-22"
                    })

    # Read the generated report
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} not found"

    with open(report_path, "r") as f:
        try:
            actual_findings = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The audit report is not valid JSON.")

    assert isinstance(actual_findings, list), "The audit report must be a JSON array."

    assert len(actual_findings) == len(expected_findings), f"Expected {len(expected_findings)} findings, but found {len(actual_findings)}."

    for expected, actual in zip(expected_findings, actual_findings):
        assert actual.get("timestamp") == expected["timestamp"], f"Timestamp mismatch: expected {expected['timestamp']}, got {actual.get('timestamp')}"
        assert actual.get("provided_filename") == expected["provided_filename"], f"Filename mismatch: expected {expected['provided_filename']}, got {actual.get('provided_filename')}"
        assert actual.get("resolved_path") == expected["resolved_path"], f"Resolved path mismatch: expected {expected['resolved_path']}, got {actual.get('resolved_path')}"
        assert actual.get("sha256") == expected["sha256"], f"SHA256 mismatch for {expected['resolved_path']}"
        assert actual.get("cwe") == "CWE-22", f"CWE mismatch: expected CWE-22, got {actual.get('cwe')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
