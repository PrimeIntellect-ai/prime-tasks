#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import struct
import subprocess

HOME = "/home/user"
BIN_PATH = f"{HOME}/events.bin"
JSON_PATH = f"{HOME}/events.json"
PARSER_PATH = f"{HOME}/parse_events.py"
PROFILER_PATH = f"{HOME}/profiler_dump"
DIFF_PATH = f"{HOME}/diff_analysis.txt"
RECORD = struct.Struct("<IH26s")


def run(command):
    return subprocess.run(
        command,
        cwd=HOME,
        check=True,
        timeout=10,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def independently_decode(blob):
    assert len(blob) % RECORD.size == 0, "Binary log contains a partial record."
    events = []
    for offset in range(0, len(blob), RECORD.size):
        timestamp, event_type, raw_name = RECORD.unpack_from(blob, offset)
        events.append({
            "timestamp": timestamp,
            "event_type": event_type,
            "function_name": raw_name.decode("ascii").strip("\x00"),
        })
    return events


def load_json():
    assert os.path.isfile(JSON_PATH), f"Missing file: {JSON_PATH}. Did you run the fixed parse_events.py?"
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {JSON_PATH} is not valid JSON."


def execute_parser_fresh():
    if os.path.lexists(JSON_PATH):
        os.remove(JSON_PATH)
    run(["python3", PARSER_PATH])
    return load_json()


def assert_event_shape_and_values(actual, expected):
    assert isinstance(actual, list), f"JSON root should be a list, found {type(actual)}."
    assert len(actual) == len(expected), f"Expected {len(expected)} events in JSON, found {len(actual)}."
    for i, (got, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(got, dict), f"Event {i} should be a dictionary."
        assert set(got) == {"timestamp", "event_type", "function_name"}, f"Event {i} has incorrect keys."
        assert got.get("timestamp") == wanted["timestamp"], f"Event {i} has incorrect timestamp."
        assert got.get("event_type") == wanted["event_type"], f"Event {i} has incorrect event_type."
        assert got.get("function_name") == wanted["function_name"], f"Event {i} has incorrect function_name."


def test_complete_solution():
    assert os.path.isfile(PROFILER_PATH), f"Missing profiler binary: {PROFILER_PATH}."
    assert os.access(PROFILER_PATH, os.X_OK), f"Profiler is not executable: {PROFILER_PATH}."
    assert os.path.isfile(PARSER_PATH), f"Missing repaired parser: {PARSER_PATH}."

    # Generate the real artifact, then require the submitted parser to recreate JSON.
    if os.path.lexists(BIN_PATH):
        os.remove(BIN_PATH)
    run([PROFILER_PATH])
    assert os.path.isfile(BIN_PATH), f"Missing generated file: {BIN_PATH}. Did you run profiler_dump?"
    assert os.path.getsize(BIN_PATH) == 96, f"File {BIN_PATH} has incorrect size. Expected 96 bytes."

    with open(BIN_PATH, "rb") as f:
        original_blob = f.read()
    derived_original = independently_decode(original_blob)
    data = execute_parser_fresh()
    with open(BIN_PATH, "rb") as f:
        assert f.read() == original_blob, "The parser must read, not replace, events.bin."

    expected_events = [
        {"timestamp": 1625091234, "event_type": 1, "function_name": "main"},
        {"timestamp": 1625091240, "event_type": 2, "function_name": "compute_hash"},
        {"timestamp": 1625091245, "event_type": 2, "function_name": "validate_data"},
    ]
    assert derived_original == expected_events, "profiler_dump generated unexpected event data."
    assert_event_shape_and_values(data, expected_events)

    # Exercise the repaired parser on unpredictable records so fixed JSON cannot pass.
    synthetic_records = [
        (secrets.randbits(32), secrets.randbelow(65536), "probe_" + secrets.token_hex(6)),
        (secrets.randbits(32), secrets.randbelow(65536), "x" + secrets.token_hex(10)),
        (secrets.randbits(32), secrets.randbelow(65536), "third_" + secrets.token_hex(5)),
    ]
    synthetic_blob = b"".join(
        RECORD.pack(ts, event_type, name.encode("ascii").ljust(26, b"\x00"))
        for ts, event_type, name in synthetic_records
    )
    with open(BIN_PATH, "wb") as f:
        f.write(synthetic_blob)
    synthetic_expected = independently_decode(synthetic_blob)
    synthetic_actual = execute_parser_fresh()
    with open(BIN_PATH, "rb") as f:
        assert f.read() == synthetic_blob, "The parser modified the input binary log."
    assert_event_shape_and_values(synthetic_actual, synthetic_expected)

    # Restore and verify the requested final artifacts.
    run([PROFILER_PATH])
    final_data = execute_parser_fresh()
    assert_event_shape_and_values(final_data, expected_events)

    assert os.path.isfile(DIFF_PATH), f"Missing file: {DIFF_PATH}."
    with open(DIFF_PATH, "r") as f:
        content = f.read().strip()
    assert content == "validate_data", f"Incorrect content in {DIFF_PATH}. Expected 'validate_data', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
