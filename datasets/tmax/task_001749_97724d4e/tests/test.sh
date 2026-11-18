#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import stat
import subprocess

import pytest

REPORT_PATH = "/home/user/audit_report.json"
PROJECT_DIR = "/home/user/audit_tool"


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Audit report {REPORT_PATH} was not created."
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")


def assert_exact_entry(actual, expected, index):
    assert isinstance(actual, dict), f"Entry {index} must be a JSON object."
    assert set(actual.keys()) == {"timestamp", "decoded_payload", "vulnerable"}, \
        f"Entry {index} must contain exactly timestamp, decoded_payload, and vulnerable."
    assert actual.get("timestamp") == expected["timestamp"], \
        f"Entry {index} timestamp mismatch. Expected {expected['timestamp']}, got {actual.get('timestamp')}."
    assert actual.get("decoded_payload") == expected["decoded_payload"], \
        f"Entry {index} decoded_payload mismatch. Expected {expected['decoded_payload']}, got {actual.get('decoded_payload')}."
    assert actual.get("vulnerable") is expected["vulnerable"], \
        f"Entry {index} vulnerable mismatch. Expected {expected['vulnerable']}, got {actual.get('vulnerable')}."


def test_audit_report_exists_and_valid():
    data = load_report()
    assert isinstance(data, list), "The audit report must be a JSON array."
    assert len(data) == 3, f"Expected exactly 3 matching entries, found {len(data)}."

    expected_entries = [
        {
            "timestamp": "2023-10-25T08:15:30Z",
            "decoded_payload": "admin' OR 1=1 --",
            "vulnerable": True
        },
        {
            "timestamp": "2023-10-25T08:16:45Z",
            "decoded_payload": "union select 1,username,323",
            "vulnerable": True
        },
        {
            "timestamp": "2023-10-25T08:25:12Z",
            "decoded_payload": "<script>alert(1)</script>",
            "vulnerable": False
        }
    ]

    for i, expected in enumerate(expected_entries):
        assert_exact_entry(data[i], expected, i)


def test_rust_project_created():
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    src_main = os.path.join(PROJECT_DIR, "src", "main.rs")

    assert os.path.isdir(PROJECT_DIR), f"Rust project directory {PROJECT_DIR} was not created."
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {PROJECT_DIR}."
    assert os.path.isfile(src_main), f"src/main.rs not found in {PROJECT_DIR}."


def test_rust_utility_parses_and_executes_service_on_fresh_inputs():
    nonce = secrets.token_hex(12)
    payloads = [
        f"visitor-{nonce}",
        f"admin' oR 1=1 -- {nonce}",
        f"{nonce} UnIoN SeLeCt account,password",
        f"<ScRiPt>alert('{nonce}')</sCrIpT>",
        f"plain-{nonce}-request",
    ]
    timestamps = [
        "2041-06-01T10:00:00Z",
        "2041-06-01T10:01:00Z",
        "2041-06-01T10:02:00Z",
        "2041-06-01T10:03:00Z",
        "2041-06-01T10:04:00Z",
    ]

    with open("/home/user/auth.log", "w", encoding="utf-8") as f:
        for i, (timestamp, payload) in enumerate(zip(timestamps, payloads)):
            encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
            f.write(f"[{timestamp}] | FAILED | user: dynamic{i} | payload: {encoded}\n")

    calls_path = f"/tmp/auth_service_calls_{nonce}.jsonl"
    exit_codes = {
        payloads[1]: 0,
        payloads[2]: 139,
        payloads[3]: 23,
    }
    service_source = f'''#!/usr/bin/env python3
import json
import sys
calls_path = {calls_path!r}
exit_codes = {exit_codes!r}
with open(calls_path, "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
if len(sys.argv) != 2:
    sys.exit(91)
sys.exit(exit_codes.get(sys.argv[1], 92))
'''
    with open("/home/user/auth_service", "w", encoding="utf-8") as f:
        f.write(service_source)
    os.chmod("/home/user/auth_service", stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
             stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT_DIR, "Cargo.toml")],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, \
        f"Rust utility failed on fresh inputs (exit {result.returncode}).\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    data = load_report()
    assert isinstance(data, list), "The audit report must be a JSON array."
    expected_entries = [
        {"timestamp": timestamps[1], "decoded_payload": payloads[1], "vulnerable": True},
        {"timestamp": timestamps[2], "decoded_payload": payloads[2], "vulnerable": True},
        {"timestamp": timestamps[3], "decoded_payload": payloads[3], "vulnerable": False},
    ]
    assert len(data) == len(expected_entries), \
        f"Expected exactly {len(expected_entries)} matching entries, found {len(data)}."
    for i, expected in enumerate(expected_entries):
        assert_exact_entry(data[i], expected, i)

    assert os.path.isfile(calls_path), "The utility did not execute /home/user/auth_service."
    with open(calls_path, "r", encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert calls == [[payloads[1]], [payloads[2]], [payloads[3]]], \
        "auth_service must be invoked once per matching payload, in log order, with the decoded payload as its only argument."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
