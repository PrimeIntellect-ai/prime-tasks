#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import secrets
import subprocess

import pytest


def test_extracted_payload_json():
    payload_path = "/home/user/extracted_payload.json"
    assert os.path.exists(payload_path), f"File {payload_path} does not exist."

    with open(payload_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {payload_path}: {e}")

    expected_data = {
        "service": "payment-api",
        "status": "down",
        "last_ping": 1700000000,
        "error": "OOM"
    }

    assert data == expected_data, f"Extracted payload JSON does not match expected data. Got: {data}"


def test_uptime_pytest_passes():
    test_file = "/home/user/test_uptime.py"
    assert os.path.exists(test_file), f"File {test_file} does not exist."
    assert os.path.isfile(test_file), f"Path {test_file} is not a regular file."

    res = subprocess.run(
        ["pytest", test_file], capture_output=True, text=True, timeout=30
    )
    assert res.returncode == 0, f"pytest on {test_file} failed with output:\n{res.stdout}\n{res.stderr}"


def test_decode_payload_general_behavior():
    test_file = "/home/user/test_uptime.py"
    assert os.path.isfile(test_file), f"File {test_file} does not exist or is not a regular file."

    spec = importlib.util.spec_from_file_location("submitted_uptime", test_file)
    assert spec is not None and spec.loader is not None, "Could not load test_uptime.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    decoder = getattr(module, "decode_payload", None)
    assert callable(decoder), "test_uptime.py must define a callable decode_payload function"

    nonce = secrets.token_hex(12)
    cases = [
        {"service": "cache", "status": "up"},
        {"message": "héllo 世界 🚀", "ok": True, "value": None},
        {"nested": {"items": [1, -7, 3.25, False], "tag": nonce}},
        {"service": f"worker-{nonce}", "last_ping": secrets.randbelow(10**12)},
    ]

    for expected in cases:
        json_text = json.dumps(expected, ensure_ascii=False, separators=(",", ":"))
        encoded = json_text.encode("utf-16le").hex()
        actual = decoder(encoded)
        assert isinstance(actual, dict), f"decode_payload must return a dictionary, got {type(actual)!r}"
        assert actual == expected, f"decode_payload returned {actual!r}; expected {expected!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
