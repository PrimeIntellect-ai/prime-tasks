#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import hashlib


def test_rotation_report_exists():
    assert os.path.isfile("/home/user/rotation_report.txt"), "The file /home/user/rotation_report.txt was not created."


def test_rotation_report_content():
    expected_key = b"sk_live_9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"
    expected_hash = hashlib.sha256(expected_key).hexdigest()

    with open("/home/user/rotation_report.txt", "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) >= 2, "/home/user/rotation_report.txt must contain at least two lines."
    assert len(content) == 2, "/home/user/rotation_report.txt must contain exactly two lines."

    expected_hash_line = f"OLD_KEY_HASH={expected_hash}"
    assert any(line.strip() == expected_hash_line for line in content), f"Could not find exact line '{expected_hash_line}' in rotation_report.txt."

    expected_cwe_line = "NEW_CODE_CWE=CWE-79"
    assert any(line.strip().upper() == expected_cwe_line for line in content), f"Could not find line '{expected_cwe_line}' (case-insensitive on CWE-79) in rotation_report.txt."

    assert content == [expected_hash_line, expected_cwe_line], "rotation_report.txt must contain exactly the two required lines in the required order."


def test_access_log_redacted():
    assert os.path.isfile("/home/user/logs/access.log"), "/home/user/logs/access.log is missing."

    with open("/home/user/logs/access.log", "r") as f:
        content = f.read()

    old_key = "sk_live_9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"

    assert old_key not in content, "The old API key is still present in /home/user/logs/access.log."
    assert "sk_live_" not in content, "Found remnants of 'sk_live_' keys in /home/user/logs/access.log."
    assert "[REDACTED]" in content, "The literal string '[REDACTED]' was not found in /home/user/logs/access.log."
    assert "GET /api/data?key=[REDACTED] HTTP/1.1" in content, "The log lines were not redacted correctly or the structure was modified."
    assert "GET /health HTTP/1.1" in content, "Unrelated log lines were modified or removed."

    expected_content = (
        "[2023-10-01 10:00:00] GET /api/data?key=[REDACTED] HTTP/1.1\n"
        "[2023-10-01 10:05:00] POST /api/update HTTP/1.1 - Success\n"
        "[2023-10-01 10:10:00] GET /api/data?key=[REDACTED] HTTP/1.1\n"
        "[2023-10-01 10:15:00] GET /health HTTP/1.1\n"
    )
    assert content == expected_content, "access.log was not preserved exactly apart from replacing every old key with [REDACTED]."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
