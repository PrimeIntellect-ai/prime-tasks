#!/bin/bash
set -e
mkdir -p /logs/verifier

# Require the repaired artifact to exist and regenerate the requested output.
if [ ! -f /home/user/legacy/aggregator.py ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
rm -f /home/user/timeline.json
if ! (cd /home/user/legacy && timeout 10s python3 aggregator.py); then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import tempfile
import pytest

LEGACY = '/home/user/legacy'
TIMELINE = '/home/user/timeline.json'


def test_timeline_json_exists():
    assert os.path.isfile('/home/user/timeline.json'), "The /home/user/timeline.json file is missing. Did you run the fixed aggregator script?"


def test_timeline_json_format_and_content():
    with open('/home/user/timeline.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/timeline.json does not contain valid JSON.")

    assert isinstance(data, list), "The JSON root must be an array (list)."

    expected_data = [
        {
            "timestamp": 1690000000,
            "service": "service_a",
            "message": "System started"
        },
        {
            "timestamp": 1690000010,
            "service": "service_b",
            "message": "Database connected"
        },
        {
            "timestamp": 1690000025,
            "service": "service_a",
            "message": "User logged in"
        },
        {
            "timestamp": 1690000030,
            "service": "service_b",
            "message": "Query executed"
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} events, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Event at index {i} is not a JSON object."

        actual_keys = set(actual.keys())
        expected_keys = {"timestamp", "service", "message"}
        assert actual_keys == expected_keys, f"Event at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        assert actual["timestamp"] == expected["timestamp"], f"Event at index {i} has incorrect timestamp. Expected {expected['timestamp']}, got {actual['timestamp']}."
        assert actual["service"] == expected["service"], f"Event at index {i} has incorrect service. Expected '{expected['service']}', got '{actual['service']}'."
        assert actual["message"] == expected["message"], f"Event at index {i} has incorrect message. Expected '{expected['message']}', got '{actual['message']}'."


def test_timeline_is_sorted():
    with open('/home/user/timeline.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/timeline.json does not contain valid JSON.")

    if not isinstance(data, list):
        pytest.fail("The JSON root must be an array (list).")

    timestamps = [event.get("timestamp", 0) for event in data if isinstance(event, dict)]
    assert timestamps == sorted(timestamps), "The events in timeline.json are not sorted strictly by timestamp in ascending order."


def test_aggregator_handles_derived_inputs_and_uses_decoder_key():
    service_a = os.path.join(LEGACY, 'service_a.log')
    service_b = os.path.join(LEGACY, 'service_b.log')
    decoder = os.path.join(LEGACY, 'legacy_decoder')
    aggregator = os.path.join(LEGACY, 'aggregator.py')

    assert os.path.isfile(aggregator), 'aggregator.py is missing.'
    assert os.path.isfile(decoder), 'legacy_decoder is missing.'

    tmpdir = tempfile.mkdtemp(prefix='aggregator_verifier_')
    a_backup = os.path.join(tmpdir, 'service_a.log')
    b_backup = os.path.join(tmpdir, 'service_b.log')
    decoder_backup = os.path.join(tmpdir, 'legacy_decoder')
    timeline_backup = os.path.join(tmpdir, 'timeline.json')
    call_log = os.path.join(tmpdir, 'decoder_calls.jsonl')

    shutil.copy2(service_a, a_backup)
    shutil.copy2(service_b, b_backup)
    shutil.copy2(decoder, decoder_backup)
    had_timeline = os.path.isfile(TIMELINE)
    if had_timeline:
        shutil.copy2(TIMELINE, timeline_backup)

    message_a = 'DynamicAlpha'
    message_b = 'DynamicBeta'
    payload_a = ''.join(chr(ord(ch) ^ 0x2A) for ch in message_a)
    payload_b = message_b.encode('utf-8').hex()
    dynamic_data = None
    decoder_calls = []

    try:
        with open(service_a, 'w') as f:
            f.write(f'1700000037,{payload_a}\n')
        with open(service_b, 'w') as f:
            f.write(f'1700000011:{payload_b}\n')

        os.unlink(decoder)
        wrapper = f'''#!/usr/bin/env python3
import json
import sys
with open({call_log!r}, "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
if len(sys.argv) != 4 or sys.argv[1] != "--key" or sys.argv[2] != "SuperSecretLegacyKey99":
    sys.exit(1)
payload = sys.argv[3].encode("latin1")
sys.stdout.buffer.write(bytes(value ^ 0x2A for value in payload))
'''
        with open(decoder, 'w') as f:
            f.write(wrapper)
        os.chmod(decoder, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                          stat.S_IRGRP | stat.S_IXGRP |
                          stat.S_IROTH | stat.S_IXOTH)

        if os.path.exists(TIMELINE):
            os.unlink(TIMELINE)
        subprocess.run(
            ['python3', aggregator],
            cwd=LEGACY,
            check=True,
            timeout=10,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        assert os.path.isfile(TIMELINE), 'The aggregator did not create timeline.json for new inputs.'
        with open(TIMELINE, 'r') as f:
            dynamic_data = json.load(f)
        if os.path.exists(call_log):
            with open(call_log, 'r') as f:
                decoder_calls = [json.loads(line) for line in f if line.strip()]
    finally:
        shutil.copy2(a_backup, service_a)
        shutil.copy2(b_backup, service_b)
        if os.path.exists(decoder):
            os.unlink(decoder)
        shutil.copy2(decoder_backup, decoder)
        if had_timeline:
            shutil.copy2(timeline_backup, TIMELINE)
        elif os.path.exists(TIMELINE):
            os.unlink(TIMELINE)
        shutil.rmtree(tmpdir, ignore_errors=True)

    expected = [
        {"timestamp": 1700000011, "service": "service_b", "message": message_b},
        {"timestamp": 1700000037, "service": "service_a", "message": message_a},
    ]
    assert dynamic_data == expected, 'aggregator.py did not decode and chronologically merge newly supplied log records.'
    assert ["--key", "SuperSecretLegacyKey99", payload_a] in decoder_calls, \
        'aggregator.py did not invoke legacy_decoder with the required secret key and payload.'
    timestamps = [event['timestamp'] for event in dynamic_data]
    assert all(left < right for left, right in zip(timestamps, timestamps[1:])), \
        'Dynamically generated events are not strictly sorted by timestamp.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
