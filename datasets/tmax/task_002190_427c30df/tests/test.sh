#!/bin/bash
set -e
mkdir -p /logs/verifier
rm -f /home/user/timeline_TXN-999.json

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import uuid

import pytest

SCRIPT_FILE = "/home/user/log_aggregator.py"
OUTPUT_FILE = "/home/user/timeline_TXN-999.json"
LOG_DIR = "/home/user/logs"

EXPECTED_LOGS = {
    "evt-start.json": {
        "event_id": "evt-start",
        "service": "api-gateway",
        "timestamp": 1700000000,
        "action": "receive_request",
        "next_event": "evt-2",
    },
    "evt-2.json": {
        "event_id": "evt-2",
        "service": "auth-service",
        "timestamp": 1700000005,
        "action": "authenticate",
        "next_event": "evt-3",
    },
    "evt-3.json": {
        "event_id": "evt-3",
        "service": "legacy-payment-service",
        "timestamp": 1700000010000,
        "action": "charge_card",
        "next_event": "evt-4",
    },
    "evt-4.json": {
        "event_id": "evt-4",
        "service": "notification-service",
        "timestamp": 1700000015,
        "action": "send_email",
        "next_event": "evt-2",
    },
}

EXPECTED_TIMELINE = [
    EXPECTED_LOGS["evt-start.json"],
    EXPECTED_LOGS["evt-2.json"],
    {**EXPECTED_LOGS["evt-3.json"], "timestamp": 1700000010},
    EXPECTED_LOGS["evt-4.json"],
]


def read_logs():
    result = {}
    for filename in EXPECTED_LOGS:
        path = os.path.join(LOG_DIR, filename)
        assert os.path.isfile(path), f"Original log file {path} is missing."
        with open(path, "r") as f:
            result[filename] = json.load(f)
    return result


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_FILE), f"{SCRIPT_FILE} is missing."
    assert stat.S_ISREG(os.lstat(SCRIPT_FILE).st_mode), f"{SCRIPT_FILE} must be a regular file."

    before = read_logs()
    assert before == EXPECTED_LOGS, "One or more underlying JSON log files were modified."

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    try:
        completed = subprocess.run(
            [sys.executable, SCRIPT_FILE],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("log_aggregator.py did not terminate; cycle detection is missing or broken.")

    assert completed.returncode == 0, (
        f"log_aggregator.py exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert read_logs() == before == EXPECTED_LOGS, (
        "The underlying JSON log files were modified. You must only modify the Python script."
    )


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} was not created."


def test_output_file_is_valid_json():
    with open(OUTPUT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The output file {OUTPUT_FILE} is not valid JSON.")
    assert isinstance(data, list), "The output JSON must be a list of events."


def test_output_timeline_contents():
    with open(OUTPUT_FILE, "r") as f:
        data = json.load(f)

    assert len(data) == 4, f"Expected exactly 4 events in the timeline, but found {len(data)}."
    expected_event_ids = ["evt-start", "evt-2", "evt-3", "evt-4"]
    actual_event_ids = [event.get("event_id") for event in data]
    assert actual_event_ids == expected_event_ids, (
        f"Expected event order {expected_event_ids}, but got {actual_event_ids}."
    )

    evt_3 = data[2]
    assert evt_3.get("event_id") == "evt-3"
    timestamp = evt_3.get("timestamp")
    assert timestamp in (1700000010, 1700000010.0), (
        f"The timestamp for evt-3 was not normalized correctly. Expected 1700000010, got {timestamp}."
    )

    assert data == EXPECTED_TIMELINE, (
        "The timeline must preserve every field from every processed event, changing only the "
        "millisecond-scale timestamp to seconds."
    )


def test_original_logs_unmodified():
    evt_3_path = os.path.join(LOG_DIR, "evt-3.json")
    assert os.path.isfile(evt_3_path), f"Original log file {evt_3_path} is missing."
    with open(evt_3_path, "r") as f:
        evt_3_data = json.load(f)
    assert evt_3_data.get("timestamp") == 1700000010000, (
        "The original log file evt-3.json was modified. You must only modify the python script."
    )
    assert read_logs() == EXPECTED_LOGS, "One or more original log files were modified."


def test_build_timeline_on_unseen_chain():
    token = uuid.uuid4().hex
    first = f"start-{token}"
    second = f"middle-{token}"
    third = f"end-{token}"
    base = 1800000000 + (int(token[:6], 16) % 1000000)

    events = [
        {
            "event_id": first,
            "service": f"legacy-{token}",
            "timestamp": base * 1000,
            "action": f"first-{token}",
            "next_event": second,
            "metadata": {"token": token, "position": 1},
        },
        {
            "event_id": second,
            "service": f"worker-{token}",
            "timestamp": base + 4,
            "action": f"second-{token}",
            "next_event": third,
            "metadata": {"token": token, "position": 2},
        },
        {
            "event_id": third,
            "service": f"sink-{token}",
            "timestamp": (base + 9) * 1000,
            "action": f"third-{token}",
            "next_event": second,
            "metadata": {"token": token, "position": 3},
        },
    ]

    with tempfile.TemporaryDirectory() as temp_logs:
        for event in events:
            with open(os.path.join(temp_logs, event["event_id"] + ".json"), "w") as f:
                json.dump(event, f)

        spec = importlib.util.spec_from_file_location(f"submission_{token}", SCRIPT_FILE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert callable(getattr(module, "build_timeline", None)), "build_timeline must remain callable."
        module.LOG_DIR = temp_logs
        timeline = module.build_timeline(first)

        expected = [dict(event) for event in events]
        expected[0]["timestamp"] = base
        expected[2]["timestamp"] = base + 9
        assert timeline == expected, (
            "build_timeline failed on an unseen cyclic chain, did not normalize before checking "
            "chronology, or did not preserve event data."
        )

        for original in events:
            with open(os.path.join(temp_logs, original["event_id"] + ".json"), "r") as f:
                assert json.load(f) == original, "build_timeline modified an underlying log file."
TEST_EOF

if timeout 25s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
