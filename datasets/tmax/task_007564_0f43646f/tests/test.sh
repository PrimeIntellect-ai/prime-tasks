#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.util
import json
import os
import secrets
import subprocess
import sys
from decimal import Decimal

import pytest

SCRIPT = "/home/user/log_processor.py"
OUTPUT = "/home/user/processed_logs.jsonl"


@pytest.fixture(scope="session", autouse=True)
def run_submitted_script():
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist."
    assert os.path.isfile("/home/user/app_logs.jsonl")
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        check=True,
        timeout=20,
    )


def test_processed_logs_exists():
    path = "/home/user/processed_logs.jsonl"
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the script?"


def test_processed_logs_content():
    path = "/home/user/processed_logs.jsonl"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 3, f"Expected exactly 3 lines in {path}, found {len(lines)}"

    # We use Decimal to check exact values without float precision loss
    parsed_lines = [json.loads(line, parse_float=Decimal) for line in lines]

    # Line 1
    assert parsed_lines[0]['timestamp'] == Decimal("1700000000.1234567890123456789"), "Precision loss in timestamp on line 1."
    assert parsed_lines[0]['payload'] == {"data": "critical_event_1"}, "Payload not correctly unwrapped on line 1."
    assert parsed_lines[0].get('decoded_msg') == "Hello World", "Base64 decoding failed or incorrect on line 1."

    # Line 2
    assert parsed_lines[1]['timestamp'] == Decimal("1700000005.9876543210987654321"), "Precision loss in timestamp on line 2."
    assert parsed_lines[1]['payload'] == {"data": "critical_event_2"}, "Payload not correctly unwrapped on line 2."
    assert parsed_lines[1].get('decoded_msg') == "agent activated", "Base64 decoding failed or incorrect on line 2."

    # Line 3
    assert parsed_lines[2]['timestamp'] == Decimal("1700000010.5555555555555555555"), "Precision loss in timestamp on line 3."
    assert parsed_lines[2]['payload'] == {"data": "critical_event_3"}, "Payload not correctly unwrapped on line 3."
    assert parsed_lines[2].get('decoded_msg') == "padding issue", "Base64 decoding failed or incorrect on line 3."


def test_processed_logs_raw_strings():
    # Double check that the raw strings contain the exact float representation
    path = "/home/user/processed_logs.jsonl"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 3
    assert "1700000000.1234567890123456789" in lines[0], "Exact timestamp string missing in line 1 output."
    assert "1700000005.9876543210987654321" in lines[1], "Exact timestamp string missing in line 2 output."
    assert "1700000010.5555555555555555555" in lines[2], "Exact timestamp string missing in line 3 output."


def test_processor_handles_fresh_inputs(tmp_path):
    token = secrets.token_hex(12)
    timestamps = [
        "1800000001." + secrets.token_hex(16)[:25].replace("a", "1").replace("b", "2").replace("c", "3").replace("d", "4").replace("e", "5").replace("f", "6"),
        "1800000002." + secrets.token_hex(16)[:25].replace("a", "7").replace("b", "8").replace("c", "9").replace("d", "4").replace("e", "5").replace("f", "6"),
        "1800000003." + secrets.token_hex(16)[:25].replace("a", "1").replace("b", "2").replace("c", "3").replace("d", "4").replace("e", "5").replace("f", "6"),
    ]
    messages = ["fresh-" + token, "nested-" + token, "utf8-π-" + token]
    payloads = [
        {"inner": {"inner": {"inner": {"data": "fresh-" + token}}}},
        {"inner": {"data": "second-" + token}},
        {"data": "plain-" + token},
    ]
    expected_payloads = [
        {"data": "fresh-" + token},
        {"data": "second-" + token},
        {"data": "plain-" + token},
    ]

    input_path = tmp_path / "fresh.jsonl"
    output_path = tmp_path / "fresh-output.jsonl"
    input_lines = []
    for timestamp, payload, message in zip(timestamps, payloads, messages):
        encoded = base64.b64encode(message.encode("utf-8")).decode("ascii").rstrip("=")
        input_lines.append(
            '{"timestamp": ' + timestamp
            + ', "payload": ' + json.dumps(payload)
            + ', "encoded_msg": ' + json.dumps(encoded) + '}'
        )
    input_path.write_text("\n".join(input_lines) + "\n", encoding="utf-8")

    runner = r'''
import importlib.util
import sys
spec = importlib.util.spec_from_file_location("submitted_log_processor", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert callable(getattr(module, "process_logs", None)), "process_logs is missing"
module.process_logs(sys.argv[2], sys.argv[3])
'''
    subprocess.run(
        [sys.executable, "-c", runner, SCRIPT, str(input_path), str(output_path)],
        check=True,
        timeout=20,
    )

    assert output_path.is_file(), "process_logs did not create the requested output file"
    raw_lines = output_path.read_text(encoding="utf-8").strip().split("\n")
    assert len(raw_lines) == len(timestamps)
    parsed = [json.loads(line, parse_float=Decimal) for line in raw_lines]

    for i, (item, timestamp, payload, message, raw) in enumerate(
        zip(parsed, timestamps, expected_payloads, messages, raw_lines)
    ):
        assert item["timestamp"] == Decimal(timestamp), f"Precision loss on fresh input line {i + 1}"
        assert timestamp in raw, f"Exact timestamp text missing on fresh input line {i + 1}"
        assert item["payload"] == payload, f"Payload not unwrapped on fresh input line {i + 1}"
        assert item.get("decoded_msg") == message, f"Base64 decoding failed on fresh input line {i + 1}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
