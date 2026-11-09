#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import secrets
import string
import subprocess
import pytest

def test_redact_logs_script_exists():
    script_path = "/home/user/redact_logs.sh"
    assert os.path.exists(script_path), f"The script {script_path} was not created."

def test_redacted_log_content():
    access_log_path = "/home/user/access.log"
    redacted_log_path = "/home/user/redacted.log"

    assert os.path.exists(redacted_log_path), f"The redacted log {redacted_log_path} is missing."

    with open(access_log_path, "r") as f:
        original_content = f.read()

    # Derive expected content by replacing alphanumeric session IDs
    expected_content = re.sub(r"session_id=[a-zA-Z0-9]+", "session_id=[REDACTED]", original_content)

    with open(redacted_log_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), "The redacted.log content does not match the expected redaction pattern."

def test_redact_logs_script_behavior():
    script_path = "/home/user/redact_logs.sh"
    access_log_path = "/home/user/access.log"
    redacted_log_path = "/home/user/redacted.log"

    assert os.path.isfile(script_path), f"The script {script_path} is not a regular file."

    alphabet = string.ascii_letters + string.digits
    token1 = "".join(secrets.choice(alphabet) for _ in range(29))
    token2 = "".join(secrets.choice(alphabet) for _ in range(41))
    token3 = "".join(secrets.choice(alphabet) for _ in range(17))
    cases = [
        f'203.0.113.8 GET /private session_id={token1} agent\n',
        f'first session_id={token2}\nno sensitive value here\nlast session_id={token3}\n',
        f'session_id={token1} session_id={token2} session_id={token3}\n',
    ]

    with open(access_log_path, "rb") as f:
        original_access = f.read()
    original_redacted = None
    if os.path.exists(redacted_log_path):
        with open(redacted_log_path, "rb") as f:
            original_redacted = f.read()

    try:
        for supplied_content in cases:
            with open(access_log_path, "w") as f:
                f.write(supplied_content)
            if os.path.exists(redacted_log_path):
                os.remove(redacted_log_path)

            result = subprocess.run(
                ["/bin/bash", script_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"The redaction script failed with exit code {result.returncode}: {result.stderr}"
            )
            assert os.path.isfile(redacted_log_path), "The script did not create /home/user/redacted.log."

            with open(redacted_log_path, "r") as f:
                actual_content = f.read()
            expected_content = re.sub(
                r"session_id=[a-zA-Z0-9]+",
                "session_id=[REDACTED]",
                supplied_content,
            )
            assert actual_content == expected_content, (
                "Executing redact_logs.sh did not produce the required redaction."
            )
    finally:
        with open(access_log_path, "wb") as f:
            f.write(original_access)
        if original_redacted is None:
            if os.path.exists(redacted_log_path):
                os.remove(redacted_log_path)
        else:
            with open(redacted_log_path, "wb") as f:
                f.write(original_redacted)

def test_vuln_line():
    vuln_line_path = "/home/user/vuln_line.txt"
    assert os.path.exists(vuln_line_path), f"Missing {vuln_line_path}"

    with open(vuln_line_path, "r") as f:
        content = f.read().strip()

    assert content == "14", f"Expected vulnerable line number to be 14, got '{content}'."

def test_invalid_cert():
    invalid_cert_path = "/home/user/invalid_cert.txt"
    assert os.path.exists(invalid_cert_path), f"Missing {invalid_cert_path}"

    with open(invalid_cert_path, "r") as f:
        content = f.read().strip()

    assert content == "server.crt", f"Expected invalid cert to be 'server.crt', got '{content}'."

def test_payload():
    payload_path = "/home/user/payload.txt"
    assert os.path.exists(payload_path), f"Missing {payload_path}"

    with open(payload_path, "r") as f:
        content = f.read().strip()

    assert content in ["//evil.com", "//evil.com/"], f"Expected payload to be a protocol-relative URL to evil.com, got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
