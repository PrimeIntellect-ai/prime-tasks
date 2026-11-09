#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import math
import os
import secrets
import subprocess

import pytest

PROGRAM = "/home/user/pipeline.go"
OUTPUT_FILE = "/home/user/output.jsonl"
STATS_FILE = "/home/user/stats.json"


def test_stats_file_exists_and_correct():
    """Retain the original assertion for the required fixture execution."""
    assert os.path.exists(STATS_FILE), f"Stats file {STATS_FILE} is missing."
    assert os.path.isfile(STATS_FILE), f"{STATS_FILE} is not a file."

    with open(STATS_FILE, "r") as f:
        try:
            stats = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{STATS_FILE} does not contain valid JSON.")

    expected_stats = {
        "total_read": 5,
        "dropped_invalid": 1,
        "dropped_duplicates": 1,
        "total_output": 3,
    }

    for key, expected_value in expected_stats.items():
        assert key in stats, f"Key '{key}' missing in {STATS_FILE}."
        assert stats[key] == expected_value, (
            f"Expected {key} to be {expected_value}, got {stats[key]}."
        )


def test_output_file_exists_and_correct():
    """Retain the original assertions for the required fixture output."""
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

    with open(OUTPUT_FILE, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == 3, (
        f"Expected exactly 3 lines in {OUTPUT_FILE}, but got {len(lines)}."
    )

    expected_data = [
        {"event_id": "e1", "device_model": "ModelA", "temperature_c": 0},
        {"event_id": "e3", "device_model": "ModelC-Pro", "temperature_c": 37},
        {"event_id": "e4", "device_model": "Legacy", "temperature_c": -40},
    ]

    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i + 1} in {OUTPUT_FILE} is not valid JSON.")

        expected = expected_data[i]
        assert record.get("event_id") == expected["event_id"]
        assert record.get("device_model") == expected["device_model"]
        assert "user_agent" not in record
        assert "sensor_data" in record

        sensor_data = record["sensor_data"]
        assert "temperature_f" not in sensor_data
        assert "temperature_c" in sensor_data
        assert sensor_data["temperature_c"] == expected["temperature_c"]
        assert "timestamp" in record
        assert record["timestamp"] != ""


def round_like_go(value):
    rounded = math.copysign(math.floor(abs(value) * 100 + 0.5), value) / 100
    return 0.0 if rounded == 0 else rounded


def derive_expected(records):
    seen = set()
    output = []
    invalid = 0
    duplicates = 0

    for source in records:
        if "timestamp" not in source or source["timestamp"] == "":
            invalid += 1
            continue

        event_id = source["event_id"]
        if event_id in seen:
            duplicates += 1
            continue
        seen.add(event_id)

        record = copy.deepcopy(source)
        fahrenheit = record["sensor_data"].pop("temperature_f")
        record["sensor_data"]["temperature_c"] = round_like_go(
            (fahrenheit - 32) * 5 / 9
        )
        record["device_model"] = record["user_agent"].split("/", 1)[0]
        del record["user_agent"]
        output.append(record)

    stats = {
        "total_read": len(records),
        "dropped_invalid": invalid,
        "dropped_duplicates": duplicates,
        "total_output": len(output),
    }
    return output, stats


def make_records():
    token = secrets.token_hex(12)
    invalid_then_valid = "iv-" + token
    duplicate = "dup-" + token
    temperatures = [
        secrets.randbelow(351) - 100,
        secrets.randbelow(351) - 100,
        secrets.randbelow(351) - 100,
        secrets.randbelow(351) - 100,
        secrets.randbelow(351) - 100,
    ]
    return [
        {
            "event_id": invalid_then_valid,
            "sensor_data": {"temperature_f": temperatures[0], "battery": 91},
            "user_agent": "Discarded/0.1",
            "tag": token,
        },
        {
            "event_id": invalid_then_valid,
            "timestamp": "2026-01-02T03:04:05Z",
            "sensor_data": {"temperature_f": temperatures[0], "battery": 90},
            "user_agent": "Edge-" + token + "/7.2/beta",
            "tag": token,
        },
        {
            "event_id": duplicate,
            "timestamp": "2026-01-02T03:04:06Z",
            "sensor_data": {"temperature_f": temperatures[1], "humidity": 44.5},
            "user_agent": "First-" + token + "/1.0",
            "active": True,
        },
        {
            "event_id": duplicate,
            "timestamp": "2026-01-02T03:04:07Z",
            "sensor_data": {"temperature_f": temperatures[2]},
            "user_agent": "DuplicateMustDisappear/9.9",
        },
        {
            "event_id": "empty-" + token,
            "timestamp": "",
            "sensor_data": {"temperature_f": temperatures[2]},
            "user_agent": "Empty/1",
        },
        {
            "event_id": "plain-" + token,
            "timestamp": "2026-01-02T03:04:08Z",
            "sensor_data": {"temperature_f": temperatures[2]},
            "user_agent": "NoSlashModel",
            "sequence": 17,
        },
        {
            "event_id": "cold-" + token,
            "timestamp": "2026-01-02T03:04:09Z",
            "sensor_data": {"temperature_f": temperatures[3], "meta": {"site": token}},
            "user_agent": "Multi-Part/3.4/release",
        },
        {
            "event_id": "hot-" + token,
            "timestamp": "2026-01-02T03:04:10Z",
            "sensor_data": {"temperature_f": temperatures[4]},
            "user_agent": "Final-" + token + "/2",
            "nullable": None,
        },
    ]


def run_pipeline(records):
    payload = "".join(json.dumps(record) + "\n" for record in records)
    return subprocess.run(
        ["go", "run", PROGRAM],
        input=payload,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd="/home/user",
        timeout=60,
        check=False,
    )


def test_pipeline_program_executes_and_processes_unseen_inputs():
    assert os.path.exists(PROGRAM), f"Required Go program {PROGRAM} is missing."
    assert os.path.isfile(PROGRAM), f"{PROGRAM} is not a regular file."
    assert os.path.getsize(PROGRAM) > 0, f"{PROGRAM} is empty."

    # Separate executions verify that state is stream-local. Values and IDs are
    # generated only at verification time, so fixed fixture output cannot pass.
    for _ in range(2):
        records = make_records()
        expected_output, expected_stats = derive_expected(records)
        result = run_pipeline(records)

        assert result.returncode == 0, (
            f"go run failed with exit code {result.returncode}: {result.stderr}"
        )

        stdout_lines = result.stdout.splitlines()
        assert len(stdout_lines) == len(expected_output), (
            f"Expected {len(expected_output)} stdout JSON lines, got "
            f"{len(stdout_lines)}: {result.stdout!r}"
        )
        actual_output = []
        for index, line in enumerate(stdout_lines, 1):
            try:
                actual_output.append(json.loads(line))
            except json.JSONDecodeError as exc:
                pytest.fail(f"stdout line {index} is not valid JSON: {exc}")
        assert actual_output == expected_output

        stderr_lines = result.stderr.splitlines()
        assert len(stderr_lines) == 1, (
            f"Expected exactly one statistics line on stderr, got: {result.stderr!r}"
        )
        try:
            actual_stats = json.loads(stderr_lines[0])
        except json.JSONDecodeError as exc:
            pytest.fail(f"stderr statistics line is not valid JSON: {exc}")
        assert actual_stats == expected_stats
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
