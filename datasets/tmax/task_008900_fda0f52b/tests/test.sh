#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import random
import secrets
import subprocess
import sys
import tempfile

import pytest

OUT_FILE = "/home/user/build/merged_timeline.json"
INGEST_FILE = "/home/user/build/ingest.py"


def load_output(path=OUT_FILE):
    assert os.path.isfile(path), f"The output file {path} is missing."
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {path} does not contain valid JSON.")


def test_merged_timeline_exists():
    assert os.path.isfile(OUT_FILE), f"The output file {OUT_FILE} was not created. Did you run the ingest.py script?"


def test_merged_timeline_valid_json():
    data = load_output()
    assert isinstance(data, list), f"The JSON in {OUT_FILE} should be a list of objects."


def test_merged_timeline_sorted_correctly():
    data = load_output()
    expected_messages = [
        "Initializing service C workers",
        "Started processing batch A",
        "Received data from upstream",
        "Completed batch A",
        "Heartbeat ping successful",
        "Sent data downstream",
        "Shutting down workers"
    ]
    actual_messages = [event.get("message") for event in data if isinstance(event, dict)]
    assert actual_messages == expected_messages, (
        "The timeline is not sorted correctly or is missing events. "
        f"Expected messages in order: {expected_messages}, but got: {actual_messages}"
    )


def test_merged_timeline_structure():
    data = load_output()
    for i, event in enumerate(data):
        assert isinstance(event, dict), f"Event at index {i} is not a JSON object."
        assert "service" in event, f"Event at index {i} is missing the 'service' key."
        assert "timestamp" in event, f"Event at index {i} is missing the 'timestamp' key."
        assert "message" in event, f"Event at index {i} is missing the 'message' key."


def test_final_output_matches_all_original_log_fields():
    expected = [
        {"service": "service_c", "timestamp": "2023-10-25T15:29:55.999999Z", "message": "Initializing service C workers"},
        {"service": "service_a", "timestamp": "2023-10-25T15:30:00.123456Z", "message": "Started processing batch A"},
        {"service": "service_b", "timestamp": "2023-10-25T15:30:30.500000Z", "message": "Received data from upstream"},
        {"service": "service_a", "timestamp": "2023-10-25T15:31:00.000000Z", "message": "Completed batch A"},
        {"service": "service_b", "timestamp": "2023-10-25T15:31:05Z", "message": "Heartbeat ping successful"},
        {"service": "service_b", "timestamp": "2023-10-25T15:31:10.100000Z", "message": "Sent data downstream"},
        {"service": "service_c", "timestamp": "2023-10-25T15:32:00.000000Z", "message": "Shutting down workers"}
    ]
    assert load_output() == expected, "The output records must preserve the service, timestamp, and message from every log entry."


def parse_expected_timestamp(ts):
    fmt = "%Y-%m-%dT%H:%M:%S.%fZ" if "." in ts else "%Y-%m-%dT%H:%M:%SZ"
    return datetime.datetime.strptime(ts, fmt)


def test_repaired_ingest_executes_on_fresh_edge_case_logs():
    assert os.path.isfile(INGEST_FILE), f"The required script {INGEST_FILE} is missing."
    nonce = secrets.token_hex(8)
    day = 10 + secrets.randbelow(15)
    prefix = f"2024-06-{day:02d}T12:34:"
    events = [
        {"service": f"svc_before_{nonce}", "timestamp": prefix + "19.999999Z", "message": f"before-{nonce}"},
        {"service": f"svc_missing_{nonce}", "timestamp": prefix + "20Z", "message": f"missing-{nonce}"},
        {"service": f"svc_fraction_{nonce}", "timestamp": prefix + "20.000001Z", "message": f"fraction-{nonce}"},
        {"service": f"svc_after_{nonce}", "timestamp": prefix + "21.100000Z", "message": f"after-{nonce}"},
        {"service": f"svc_later_{nonce}", "timestamp": prefix + "59Z", "message": f"later-{nonce}"}
    ]
    shuffled = list(events)
    random.SystemRandom().shuffle(shuffled)

    with tempfile.TemporaryDirectory() as temp_dir:
        log_dir = os.path.join(temp_dir, "logs")
        os.mkdir(log_dir)
        for index in range(2):
            with open(os.path.join(log_dir, f"input_{index}_{nonce}.log"), "w") as f:
                for event in shuffled[index::2]:
                    f.write(f"{event['service']} | {event['timestamp']} | {event['message']}\n")

        output = os.path.join(temp_dir, "result.json")
        with open(output, "w") as f:
            f.write('{"sentinel": true}')

        result = subprocess.run(
            [sys.executable, INGEST_FILE, log_dir, output],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15
        )
        assert result.returncode == 0, (
            "The repaired ingest.py failed when executed on fresh logs containing "
            f"timestamps without fractional seconds. stderr: {result.stderr}"
        )

        actual = load_output(output)
        expected = sorted(events, key=lambda event: parse_expected_timestamp(event["timestamp"]))
        assert actual == expected, (
            "Executing ingest.py on fresh logs must preserve every field and sort missing "
            "fractional seconds as exactly zero microseconds."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
