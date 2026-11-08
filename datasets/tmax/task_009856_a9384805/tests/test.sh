#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

def test_analyze_script_exists_and_executable():
    script_path = "/home/user/analyze.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_report_content_matches_expected():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} was not created."

    log_path = "/home/user/server.log"
    evidence_dir = "/home/user/evidence"

    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    assert os.path.isdir(evidence_dir), f"Evidence directory {evidence_dir} is missing."

    # 1. Compute hashes of all files in evidence directory
    evidence_hashes = {}
    for filename in os.listdir(evidence_dir):
        filepath = os.path.join(evidence_dir, filename)
        if os.path.isfile(filepath):
            with open(filepath, "rb") as f:
                file_hash = hashlib.sha256(f.read()).hexdigest()
            evidence_hashes[file_hash] = filename

    # 2. Parse log file and find matching entries
    expected_findings = []
    traversal_sequences = ["../", "%2E%2E/", "%2e%2e/"]

    with open(log_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            method = entry.get("method", "")
            status = entry.get("status", 0)
            path = entry.get("path", "")
            user_agent = entry.get("user_agent", "")
            headers = entry.get("headers", {})
            ip = entry.get("ip", "")
            payload_hash = headers.get("X-Payload-Hash", "")

            # Check criteria
            if method != "POST":
                continue
            if status != 200:
                continue
            if not any(seq in path for seq in traversal_sequences):
                continue
            if "<script>" not in user_agent.lower():
                continue

            # Check if hash matches any evidence
            if payload_hash in evidence_hashes:
                filename = evidence_hashes[payload_hash]
                expected_findings.append(f"{ip} {filename} {payload_hash}")

    # Sort alphabetically by IP
    expected_findings.sort()
    expected_output = "\n".join(expected_findings) + "\n" if expected_findings else ""

    # 3. Read actual report
    with open(report_path, "r") as f:
        actual_output = f.read()

    # Compare
    assert actual_output.strip() == expected_output.strip(), (
        f"The content of {report_path} does not match the expected output.\n"
        f"Expected:\n{expected_output.strip()}\n\n"
        f"Actual:\n{actual_output.strip()}"
    )

    # Check for proper newline termination
    if expected_output:
        assert actual_output.endswith("\n"), f"The file {report_path} should end with a newline character."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
