#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import secrets
import subprocess
import sys
from datetime import datetime, timezone


def test_unified_timeouts_json_exists():
    """Test that the unified_timeouts.json file exists."""
    assert os.path.isfile("/home/user/unified_timeouts.json"), "/home/user/unified_timeouts.json is missing"


def test_unified_timeouts_json_content():
    """Test that the unified_timeouts.json file contains the correct sorted list of timeouts."""
    try:
        with open("/home/user/unified_timeouts.json", "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("/home/user/unified_timeouts.json is not valid JSON")

    expected_data = [
        {
            "timestamp": "2023-10-25T14:30:17.000Z",
            "service": "payment",
            "message": "データベース タイムアウト"
        },
        {
            "timestamp": "2023-10-25T14:30:18.000Z",
            "service": "auth",
            "message": "Connection timeout"
        },
        {
            "timestamp": "2023-10-25T14:30:20.000Z",
            "service": "auth",
            "message": "Request Timeout on API"
        },
        {
            "timestamp": "2023-10-25T14:30:22.000Z",
            "service": "payment",
            "message": "ネットワーク タイムアウト"
        }
    ]

    assert isinstance(data, list), "The JSON output should be a list"
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(data)}"

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, f"Mismatch at index {i}. Expected: {expected}, Got: {actual}"


def test_pipeline_log_exists_and_content():
    """Test that pipeline.log exists and contains the correct success message."""
    pipeline_log_path = "/home/user/pipeline.log"
    assert os.path.isfile(pipeline_log_path), f"{pipeline_log_path} is missing"

    with open(pipeline_log_path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_message = "[SUCCESS] Processed logs: auth timeouts: 2, payment timeouts: 2"
    assert expected_message in content, f"pipeline.log does not contain the expected success message. Found: {content}"


def test_analyze_logs_script_executes_on_fresh_inputs():
    """Run the submitted script against unpredictable inputs and verify its behavior."""
    script_path = "/home/user/analyze_logs.py"
    auth_path = "/home/user/logs/auth.log"
    payment_path = "/home/user/logs/payment.log"
    output_path = "/home/user/unified_timeouts.json"
    pipeline_path = "/home/user/pipeline.log"

    assert os.path.isfile(script_path), f"{script_path} is missing or is not a file"

    paths = [auth_path, payment_path, output_path, pipeline_path]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()
        else:
            backups[path] = None

    token = secrets.token_hex(8)
    base_seconds = 1700000000 + secrets.randbelow(10_000_000)
    auth_count = 1 + secrets.randbelow(3)
    payment_count = 1 + secrets.randbelow(3)
    expected = []
    auth_lines = []
    payment_lines = []

    for i in range(auth_count):
        seconds = base_seconds + 2 + i * 4
        stamp = datetime.fromtimestamp(seconds, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        message = f"auth-{token}-{i} TiMeOuT while connecting"
        auth_lines.append(f"[{stamp}] ERROR {message}")
        expected.append({
            "timestamp": datetime.fromtimestamp(seconds, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
            "service": "auth",
            "message": message,
        })

    for i in range(payment_count):
        millis = (base_seconds + i * 4) * 1000 + 375 + i
        message = f"支払い-{token}-{i} タイムアウト"
        payment_lines.append(f"{millis} [エラー] {message}")
        whole_seconds, milliseconds = divmod(millis, 1000)
        normalized = datetime.fromtimestamp(whole_seconds, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
        expected.append({
            "timestamp": f"{normalized}.{milliseconds:03d}Z",
            "service": "payment",
            "message": message,
        })

    auth_ok_stamp = datetime.fromtimestamp(base_seconds + 1, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    auth_lines.append(f"[{auth_ok_stamp}] INFO ordinary-auth-{token}")
    payment_lines.append(f"{(base_seconds + 1) * 1000 + 111} [情報] 通常処理-{token}")

    # Reverse each source so successful output requires a chronological sort.
    auth_lines.reverse()
    payment_lines.reverse()
    expected.sort(key=lambda item: item["timestamp"])

    sentinel = f"preexisting-pipeline-entry-{token}\n"

    try:
        with open(auth_path, "w", encoding="utf-8") as f:
            f.write("\n".join(auth_lines) + "\n")
        with open(payment_path, "w", encoding="utf-8") as f:
            f.write("\n".join(payment_lines) + "\n")
        with open(pipeline_path, "w", encoding="utf-8") as f:
            f.write(sentinel)
        if os.path.exists(output_path):
            os.remove(output_path)

        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"analyze_logs.py exited with {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(output_path), "Script did not create unified_timeouts.json"

        try:
            with open(output_path, "r", encoding="utf-8") as f:
                actual = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Script produced invalid JSON: {exc}")

        assert actual == expected, f"Fresh-input output mismatch. Expected: {expected}, Got: {actual}"
        assert all(set(item.keys()) == {"timestamp", "service", "message"} for item in actual), \
            "Every output object must have exactly timestamp, service, and message keys"

        with open(pipeline_path, "r", encoding="utf-8") as f:
            pipeline_content = f.read()
        expected_log = (
            f"[SUCCESS] Processed logs: auth timeouts: {auth_count}, "
            f"payment timeouts: {payment_count}"
        )
        assert pipeline_content.startswith(sentinel), "Script overwrote pipeline.log instead of appending"
        assert expected_log in pipeline_content[len(sentinel):], \
            f"Appended pipeline entry is missing or incorrect. Found: {pipeline_content!r}"
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
