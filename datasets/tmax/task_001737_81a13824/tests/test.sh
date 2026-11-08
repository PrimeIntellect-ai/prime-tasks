#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import sys
import uuid
from datetime import datetime

import pytest
import pytz

SCRIPT = "/home/user/process_telemetry.py"
INPUT = "/home/user/data/telemetry.txt"
OUTPUT = "/home/user/output.json"


def expected_records(path):
    records = []
    with open(path, "r") as f:
        for line in f:
            parts = line.strip().split("|")
            if len(parts) != 4:
                continue
            dt_str, tz_str, device_id, value = parts
            dt = datetime.strptime(dt_str, "%Y-%m-%d %H:%M:%S")
            localized = pytz.timezone(tz_str).localize(dt, is_dst=False)
            records.append({
                "timestamp": localized.isoformat(),
                "device_id": device_id,
                "value": float(value),
            })
    return records


def test_culprit_device_extracted():
    path = "/home/user/culprit_device.txt"
    assert os.path.isfile(path), f"File {path} is missing. Did you extract the device ID?"

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "DEV-8932", f"Expected culprit device ID 'DEV-8932', but found '{content}'"


def test_output_json_exists_and_valid():
    path = OUTPUT
    assert os.path.isfile(path), f"File {path} is missing. Did you run the fixed script to generate the output?"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert isinstance(data, list), "Output JSON should be a list of records."
    assert len(data) == 3, f"Expected 3 records in output.json, but found {len(data)}."


def test_output_json_contains_correct_standard_time():
    path = OUTPUT
    if not os.path.isfile(path):
        pytest.fail(f"File {path} is missing.")

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    dev_8932_record = next((r for r in data if r.get("device_id") == "DEV-8932"), None)
    assert dev_8932_record is not None, "Record for DEV-8932 is missing from output.json"

    expected_timestamp = "2023-11-05T01:30:00-05:00"
    actual_timestamp = dev_8932_record.get("timestamp")

    assert actual_timestamp == expected_timestamp, (
        f"Timestamp for DEV-8932 is incorrect. Expected {expected_timestamp} "
        f"(Standard Time), but got {actual_timestamp}. "
        "Make sure ambiguous times default to Standard Time (is_dst=False)."
    )


def test_output_json_contains_other_records():
    path = OUTPUT
    if not os.path.isfile(path):
        pytest.fail(f"File {path} is missing.")

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    dev_1111_record = next((r for r in data if r.get("device_id") == "DEV-1111"), None)
    assert dev_1111_record is not None, "Record for DEV-1111 is missing from output.json"
    assert dev_1111_record.get("timestamp") == "2023-11-04T14:00:00-04:00", "Timestamp for DEV-1111 is incorrect."

    dev_2222_record = next((r for r in data if r.get("device_id") == "DEV-2222"), None)
    assert dev_2222_record is not None, "Record for DEV-2222 is missing from output.json"
    assert dev_2222_record.get("timestamp") == "2023-11-06T09:15:00-05:00", "Timestamp for DEV-2222 is incorrect."


def test_output_json_contains_all_correct_records_and_values():
    with open(OUTPUT, "r") as f:
        actual = json.load(f)
    assert actual == expected_records(INPUT), "output.json does not exactly match all input records."


def test_fixed_script_executes_on_fresh_data(tmp_path):
    assert os.path.isfile(SCRIPT), f"Required Python script {SCRIPT} is missing."

    ids = [f"CHECK-{uuid.uuid4().hex}" for _ in range(3)]
    test_input = tmp_path / "telemetry.txt"
    test_output = tmp_path / "output.json"
    test_input.write_text(
        f"2024-11-03 01:37:19|America/New_York|{ids[0]}|17.625\n"
        f"2024-10-27 01:42:11|Europe/London|{ids[1]}|-3.75\n"
        f"2024-06-12 08:09:10|Asia/Tokyo|{ids[2]}|101.125\n"
    )

    # Make pytz.localize use strict ambiguity detection when is_dst is omitted.
    # This reproduces the specified failure mode while allowing explicit
    # is_dst=False, exception-and-retry fixes, and non-pytz implementations.
    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    (hook_dir / "sitecustomize.py").write_text(
        "import pytz\n"
        "_real_timezone = pytz.timezone\n"
        "_missing = object()\n"
        "class _TimezoneProxy:\n"
        "    def __init__(self, zone): self._zone = zone\n"
        "    def __getattr__(self, name): return getattr(self._zone, name)\n"
        "    def localize(self, dt, is_dst=_missing):\n"
        "        if is_dst is _missing:\n"
        "            return self._zone.localize(dt, is_dst=None)\n"
        "        return self._zone.localize(dt, is_dst=is_dst)\n"
        "def _strict_timezone(name): return _TimezoneProxy(_real_timezone(name))\n"
        "pytz.timezone = _strict_timezone\n"
    )

    env = os.environ.copy()
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = str(hook_dir) + (os.pathsep + old_pythonpath if old_pythonpath else "")
    result = subprocess.run(
        [sys.executable, SCRIPT, str(test_input), str(test_output)],
        text=True,
        capture_output=True,
        timeout=15,
        env=env,
    )
    assert result.returncode == 0, (
        "The fixed processing script failed on fresh telemetry containing "
        f"ambiguous DST times:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert test_output.is_file(), "The processing script did not create its requested output file."

    try:
        actual = json.loads(test_output.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f"The processing script produced invalid JSON: {exc}")

    assert actual == expected_records(test_input), (
        "The processing script did not preserve every record and value or did not "
        "choose Standard Time for an ambiguous timestamp."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
