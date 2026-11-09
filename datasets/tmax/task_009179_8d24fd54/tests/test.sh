#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from datetime import datetime, timedelta, timezone

SCRIPT_PATH = "/home/user/process_metrics.sh"
CLEAN_METRICS_PATH = "/home/user/clean_metrics.csv"
SUMMARY_PATH = "/home/user/summary.txt"
CRON_SCHEDULE_PATH = "/home/user/cron_schedule"
SENSOR_A_PATH = "/home/user/data/sensor_a.csv"
SENSOR_B_PATH = "/home/user/data/sensor_b.csv"

EXPECTED_CLEAN_METRICS = [
    "S08,2023-10-01T11:55:00Z,21.0",
    "S01,2023-10-01T12:00:00Z,23.5",
    "S02,2023-10-01T12:05:00Z,24.1",
    "S03,2023-10-01T12:10:00Z,22.1",
    "S05,2023-10-01T12:15:00Z,19.5°C",
    "S07,2023-10-01T12:20:00Z,20.0"
]

EXPECTED_SUMMARY = "Processing complete. A total of 6 valid, unique time series points were extracted."
VALID_TIMESTAMP = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")


def run_script():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. Stderr: {result.stderr}"


def read_outputs():
    assert os.path.isfile(CLEAN_METRICS_PATH), f"Output file {CLEAN_METRICS_PATH} was not created."
    with open(CLEAN_METRICS_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert os.path.isfile(SUMMARY_PATH), f"Summary file {SUMMARY_PATH} was not created."
    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        summary = f.read().strip()
    return lines, summary


def expected_from_records(records):
    valid = []
    for record in records:
        fields = record.split(",")
        if len(fields) >= 2 and VALID_TIMESTAMP.fullmatch(fields[1]):
            valid.append(record)

    valid.sort(key=lambda record: record.split(",")[1])
    result = []
    seen = set()
    for record in valid:
        timestamp = record.split(",")[1]
        if timestamp not in seen:
            seen.add(timestamp)
            result.append(record)
    return result


def test_script_exists_and_executable():
    """Check if the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_run_script_and_check_outputs():
    """Run the script and verify the generated files against the original fixture."""
    run_script()
    lines, summary_content = read_outputs()
    assert lines == EXPECTED_CLEAN_METRICS, f"Contents of {CLEAN_METRICS_PATH} do not match expected output."
    assert summary_content == EXPECTED_SUMMARY, f"Contents of {SUMMARY_PATH} do not match expected output."


def test_cron_schedule():
    """Check if the cron schedule file exists and contains the correct entry."""
    assert os.path.isfile(CRON_SCHEDULE_PATH), f"Cron schedule file {CRON_SCHEDULE_PATH} does not exist."
    with open(CRON_SCHEDULE_PATH, "r", encoding="utf-8") as f:
        cron_content = f.read().strip()

    parts = cron_content.split()
    assert len(parts) >= 6, f"Cron schedule does not have enough fields: {cron_content}"

    expected_parts = ["15", "4", "*", "*", "2", SCRIPT_PATH]
    assert parts[:6] == expected_parts, f"Cron schedule entry is incorrect. Expected {expected_parts}, got {parts[:6]}"


def test_pipeline_on_runtime_generated_inputs():
    """Exercise decoding, strict filtering, timestamp sorting, and timestamp-only deduplication."""
    token = secrets.token_hex(6)
    value_token = secrets.randbelow(900000) + 100000
    base = datetime(2024, 2, 10, 3, 0, 0, tzinfo=timezone.utc) + timedelta(
        days=secrets.randbelow(10), minutes=secrets.randbelow(30)
    )
    timestamps = [
        (base + timedelta(minutes=offset)).strftime("%Y-%m-%dT%H:%M:%SZ")
        for offset in (0, 7, 13, 21, 34, 55)
    ]

    # The duplicate from sensor A is both first in the combined input and
    # lexically before the sensor B duplicate, avoiding dependence on sort's
    # tie-breaking implementation.
    records_a = [
        f"M{token},{timestamps[4]},{value_token}.4",
        f"A{token},{timestamps[2]},{value_token}.2",
        f"BAD{token},not-a-timestamp,{value_token}.8",
        f"E{token},{timestamps[0]},{value_token}.0",
        f"TAIL{token},{timestamps[3]}extra,{value_token}.9",
    ]
    records_b = [
        f"Y{token},{timestamps[5]},{value_token}.5",
        f"Z{token},{timestamps[2]},{value_token}.7",
        f"B{token},{timestamps[1]},{value_token}.1°C",
        f"NOZ{token},{timestamps[4][:-1]},{value_token}.6",
        f"D{token},{timestamps[3]},{value_token}.3",
    ]

    with open(SENSOR_A_PATH, "wb") as f:
        f.write(("\n".join(records_a) + "\n").encode("utf-16le"))
    with open(SENSOR_B_PATH, "wb") as f:
        f.write(("\n".join(records_b) + "\n").encode("iso-8859-1"))

    for path in (CLEAN_METRICS_PATH, SUMMARY_PATH):
        if os.path.exists(path):
            os.remove(path)

    run_script()
    lines, summary_content = read_outputs()

    expected = expected_from_records(records_a + records_b)
    expected_summary = (
        f"Processing complete. A total of {len(expected)} valid, unique time series points were extracted."
    )
    assert lines == expected, (
        "Pipeline output for generated sensor files does not correctly decode, filter, "
        "sort, and deduplicate the records."
    )
    assert summary_content == expected_summary, "Summary does not reflect the generated cleaned output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
