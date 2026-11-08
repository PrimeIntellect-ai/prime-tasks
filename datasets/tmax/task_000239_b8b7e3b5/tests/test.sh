#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_extracted_safe_files():
    safe_files = {
        "/home/user/extracted/safe_config.txt": b"port=8080\nmax_connections=100",
        "/home/user/extracted/nested/app.json": b'{"status": "ok"}',
        "/home/user/extracted/safe_scripts/run.sh": b"echo 'running'"
    }

    for path, expected_content in safe_files.items():
        assert os.path.exists(path), f"Safe file {path} was not extracted."
        with open(path, "rb") as f:
            content = f.read()
            assert content == expected_content, f"Content of {path} is incorrect. Expected {expected_content}, got {content}"

def test_malicious_files_not_extracted():
    malicious_paths = [
        "/home/user/extracted/etc/shadow",
        "/home/user/extracted/var/log/system.log",
        "/home/user/extracted//var/log/system.log"
    ]
    for path in malicious_paths:
        assert not os.path.exists(path), f"Malicious file was extracted to {path}"

def test_malicious_log():
    log_path = "/home/user/malicious.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "[THREAT] ../../../etc/shadow : 25",
        "[THREAT] /var/log/system.log : 13"
    ]

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in malicious.log, got {len(lines)}"

    for expected in expected_lines:
        assert expected in lines, f"Expected log entry '{expected}' not found in malicious.log"

def test_threat_report_csv():
    csv_path = "/home/user/threat_report.csv"
    assert os.path.exists(csv_path), f"CSV report {csv_path} does not exist."

    with open(csv_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "../../../etc/shadow,25",
        "/var/log/system.log,13"
    ]

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in threat_report.csv, got {len(lines)}"

    for expected in expected_lines:
        assert expected in lines, f"Expected CSV entry '{expected}' not found in threat_report.csv"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
