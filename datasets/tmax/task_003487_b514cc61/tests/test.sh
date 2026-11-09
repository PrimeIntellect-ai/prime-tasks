#!/bin/bash
set +e
mkdir -p /logs/verifier

TOKENIZER=/app/legacy_tokenizer
ORIGINAL=/app/.legacy_tokenizer.verifier_real
CALL_LOG=/tmp/verifier_tokenizer_calls
MOVED=0

cleanup() {
    if [ "$MOVED" = "1" ]; then
        rm -f "$TOKENIZER"
        mv "$ORIGINAL" "$TOKENIZER" 2>/dev/null || true
        chmod +x "$TOKENIZER" 2>/dev/null || true
    fi
}
trap cleanup EXIT

rm -f "$ORIGINAL" "$CALL_LOG"
if mv "$TOKENIZER" "$ORIGINAL"; then
    MOVED=1
fi
touch "$CALL_LOG"
chmod 666 "$CALL_LOG"

cat << 'WRAPPER_EOF' > "$TOKENIZER"
#!/usr/bin/env python3
import hashlib
import subprocess
import sys

ORIGINAL = "/app/.legacy_tokenizer.verifier_real"
CALL_LOG = "/tmp/verifier_tokenizer_calls"

data = sys.stdin.buffer.read()
with open(CALL_LOG, "a", encoding="ascii") as log:
    log.write(hashlib.sha256(data).hexdigest() + "\n")

result = subprocess.run([ORIGINAL], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
WRAPPER_EOF
chmod 755 "$TOKENIZER"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import secrets
import subprocess
from datetime import datetime, timedelta

import pytest
import requests

URL = "http://127.0.0.1:8000/process"
ORIGINAL_TOKENIZER = "/app/.legacy_tokenizer.verifier_real"
CALL_LOG = "/tmp/verifier_tokenizer_calls"


def assert_response(payload, expected, label):
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to or get response from {URL} for {label}: {exc}")

    assert response.status_code == 200, (
        f"Expected status code 200 for {label}, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response for {label} is not valid JSON. Response text: {response.text}")

    assert "utc_time" in data, f"Missing 'utc_time' in response for {label}"
    assert "normalized_message" in data, f"Missing 'normalized_message' in response for {label}"
    assert "is_valid" in data, f"Missing 'is_valid' in response for {label}"
    assert data["utc_time"] == expected["utc_time"], (
        f"Incorrect 'utc_time' for {label}. Expected {expected['utc_time']}, "
        f"got {data['utc_time']}"
    )
    assert data["normalized_message"] == expected["normalized_message"], (
        f"Incorrect 'normalized_message' for {label}. "
        f"Expected '{expected['normalized_message']}', got '{data['normalized_message']}'"
    )
    assert data["is_valid"] == expected["is_valid"], (
        f"Incorrect 'is_valid' for {label}. Expected {expected['is_valid']}, "
        f"got {data['is_valid']}"
    )


def tokenize(message):
    result = subprocess.run(
        [ORIGINAL_TOKENIZER],
        input=message.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=True,
    )
    return result.stdout.decode().rstrip("\n")


def expected_timestamp(dt, style):
    if style == "EST":
        return dt.strftime("%Y-%m-%d %H:%M:%S EST"), (dt + timedelta(hours=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
    if style == "PST":
        return dt.strftime("%Y-%m-%d %H:%M:%S PST"), (dt + timedelta(hours=8)).strftime("%Y-%m-%dT%H:%M:%SZ")
    if style == "UTC":
        return dt.strftime("%Y-%m-%d %H:%M:%S UTC"), dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ"), dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def test_service_processing():
    test_cases = [
        {
            "payload": {
                "timestamp": "2023-10-25 08:30:00 EST",
                "message": "User admin failed to LOGIN. Code: 401!"
            },
            "expected": {
                "utc_time": "2023-10-25T13:30:00Z",
                "normalized_message": "user admin failed to login code 401",
                "is_valid": False
            }
        },
        {
            "payload": {
                "timestamp": "2024-01-01T12:00:00Z",
                "message": "Disk ERR on volume 3"
            },
            "expected": {
                "utc_time": "2024-01-01T12:00:00Z",
                "normalized_message": "disk err on volume 3",
                "is_valid": True
            }
        },
        {
            "payload": {
                "timestamp": "2023-05-15 14:00:00 PST",
                "message": "err system"
            },
            "expected": {
                "utc_time": "2023-05-15T22:00:00Z",
                "normalized_message": "err system",
                "is_valid": False
            }
        },
        {
            "payload": {
                "timestamp": "2022-12-31 23:59:59 UTC",
                "message": "Critical fail during reboot sequence 99"
            },
            "expected": {
                "utc_time": "2022-12-31T23:59:59Z",
                "normalized_message": "critical fail during reboot sequence 99",
                "is_valid": True
            }
        }
    ]

    for i, tc in enumerate(test_cases):
        assert_response(tc["payload"], tc["expected"], f"fixed test case {i + 1}")


def test_randomized_processing_and_tokenizer_invocation():
    random_messages = []
    start = datetime(2020, 1, 1)
    styles = ["EST", "PST", "UTC", "ISO"]

    for i in range(12):
        nonce = secrets.token_hex(8)
        variants = [
            f"Node::{nonce}, ERR! disk=7",
            f"FAIL/{nonce}; job (42)",
            f"err--{nonce}",
            f"Alpha_{nonce}: warning code 9",
            f"FAILED {nonce}, during task 5",
        ]
        message = variants[i % len(variants)]
        dt = start + timedelta(seconds=secrets.randbelow(8 * 365 * 24 * 60 * 60))
        timestamp, utc_time = expected_timestamp(dt, styles[i % len(styles)])

        normalized = tokenize(message)
        tokens = normalized.split()
        expected = {
            "utc_time": utc_time,
            "normalized_message": normalized,
            "is_valid": ("err" in tokens or "fail" in tokens) and len(tokens) > 3,
        }
        assert_response(
            {"timestamp": timestamp, "message": message},
            expected,
            f"randomized test case {i + 1}",
        )
        random_messages.append(message)

    with open(CALL_LOG, encoding="ascii") as log:
        observed = {line.strip() for line in log if line.strip()}

    for i, message in enumerate(random_messages):
        encodings = [
            message.encode(),
            (message + "\n").encode(),
            (message + "\r\n").encode(),
        ]
        acceptable = {hashlib.sha256(value).hexdigest() for value in encodings}
        assert observed.intersection(acceptable), (
            f"Randomized message {i + 1} was not passed through /app/legacy_tokenizer"
        )
TEST_EOF

if [ "$MOVED" = "1" ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
