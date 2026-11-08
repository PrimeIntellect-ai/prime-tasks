#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import pytest

def get_extracted_token():
    cmdline_path = "/home/user/evidence/proc_cmdline.b64"
    assert os.path.isfile(cmdline_path), f"Missing {cmdline_path}"

    with open(cmdline_path, "r") as f:
        b64_data = f.read().strip()

    raw_cmdline = base64.b64decode(b64_data).decode('utf-8')
    args = raw_cmdline.split('\x00')

    token = None
    for arg in args:
        if arg.startswith("--master-auth-token="):
            token = arg.split("=", 1)[1]
            break

    assert token is not None, "Could not extract token from proc_cmdline.b64"
    return token

def compute_expected_logs(token):
    input_path = "/home/user/evidence/http_logs.jsonl"
    assert os.path.isfile(input_path), f"Missing {input_path}"

    expected_lines = []
    with open(input_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)

            is_malicious = False

            # Check headers
            auth_header = record.get("headers", {}).get("Authorization", "")
            if auth_header == f"Bearer {token}":
                is_malicious = True

            # Check cookies
            cookies = record.get("cookies", "")
            if f"session={token}" in cookies:
                is_malicious = True

            if is_malicious:
                if "Authorization" in record.get("headers", {}):
                    if record["headers"]["Authorization"] == f"Bearer {token}":
                        record["headers"]["Authorization"] = "Bearer [REDACTED]"

                if "cookies" in record and f"session={token}" in record["cookies"]:
                    record["cookies"] = record["cookies"].replace(f"session={token}", "session=[REDACTED]")

                record["body"] = "[REDACTED]"

            expected_lines.append(record)

    return expected_lines

def test_cleaned_logs_exist():
    output_path = "/home/user/evidence/cleaned_logs.jsonl"
    assert os.path.isfile(output_path), f"The output file {output_path} was not created."

def test_cleaned_logs_content():
    output_path = "/home/user/evidence/cleaned_logs.jsonl"
    assert os.path.isfile(output_path), f"The output file {output_path} is missing."

    token = get_extracted_token()
    expected_logs = compute_expected_logs(token)

    actual_logs = []
    with open(output_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                actual_logs.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON found in {output_path}: {line}")

    assert len(actual_logs) == len(expected_logs), f"Expected {len(expected_logs)} log entries, but found {len(actual_logs)}."

    for i, (actual, expected) in enumerate(zip(actual_logs, expected_logs)):
        assert actual == expected, f"Mismatch at log entry {i + 1}.\nExpected: {expected}\nActual: {actual}"

def test_rust_project_exists():
    assert os.path.isdir("/home/user/forensics_cleaner"), "The Rust project directory /home/user/forensics_cleaner does not exist."
    assert os.path.isfile("/home/user/forensics_cleaner/Cargo.toml"), "The Cargo.toml file is missing in the Rust project directory."
    assert os.path.isfile("/home/user/forensics_cleaner/src/main.rs"), "The src/main.rs file is missing in the Rust project directory."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
