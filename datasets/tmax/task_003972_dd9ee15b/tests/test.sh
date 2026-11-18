#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import difflib
import os
import random
import re
import secrets
import subprocess
from collections import Counter
from datetime import datetime, timedelta

SCRIPT_PATH = "/home/user/process_logs.py"
INPUT_PATH = "/home/user/system_logs.csv"
OUTPUT_PATH = "/home/user/critical_hourly_summary.csv"
REFERENCE = "CRITICAL: Disk failure detected in /dev/sda1"


def run_script():
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"process_logs.py failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def read_output():
    assert os.path.exists(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} is missing. Did you run your script?"
    )
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."
    with open(OUTPUT_PATH, "r", newline="") as f:
        return list(csv.reader(f))


def expected_for(records):
    counts = Counter()
    for _, timestamp, raw_message in records:
        message = raw_message.strip()
        if not re.match(r"^CRITICAL: .*", message):
            continue
        ratio = difflib.SequenceMatcher(None, message, REFERENCE).ratio()
        if ratio < 0.60:
            continue
        parsed = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ")
        aligned = parsed.replace(minute=0, second=0, microsecond=0)
        counts[aligned.strftime("%Y-%m-%dT%H:00:00Z")] += 1
    return [[hour, str(counts[hour])] for hour in sorted(counts)]


def write_fixture(records):
    with open(INPUT_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["event_id", "timestamp", "message"])
        writer.writerows(records)


def test_process_logs_end_to_end():
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    try:
        # Preserve the original verifier's exact assertions, but first require the
        # submitted artifact itself to generate the file.
        run_script()
        reader = read_output()
        assert len(reader) > 0, "The output CSV is empty."
        header = reader[0]
        assert header == ["hour_timestamp", "event_count"], \
            f"Incorrect header. Expected ['hour_timestamp', 'event_count'], got {header}."
        rows = reader[1:]
        assert len(rows) == 2, f"Expected exactly 2 data rows, got {len(rows)}."
        expected_data = [
            ["2023-10-15T14:00:00Z", "2"],
            ["2023-10-16T02:00:00Z", "2"],
        ]
        assert rows == expected_data, \
            f"Output data does not match expected results or is not sorted chronologically. Got {rows}."

        # Replace the input with an unpredictable fixture containing quoted
        # commas, embedded newlines, whitespace, near matches, and unsorted hours.
        base = datetime(
            2020 + secrets.randbelow(6),
            1 + secrets.randbelow(11),
            2 + secrets.randbelow(20),
            secrets.randbelow(18),
        )
        hours = [base + timedelta(hours=9), base, base + timedelta(days=1, hours=2)]
        records = []
        event_id = 1000 + secrets.randbelow(8000)
        qualifying_messages = [
            REFERENCE,
            REFERENCE.replace("sda1", "sdb2") + "\nVolume, degraded.",
            "  " + REFERENCE + "\nCheck rack, bay 7.\n  ",
        ]
        for group_index, hour in enumerate(hours):
            count = 1 + secrets.randbelow(3)
            for item_index in range(count):
                timestamp = (hour + timedelta(minutes=3 + item_index * 11, seconds=17)).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                )
                message = qualifying_messages[(group_index + item_index) % len(qualifying_messages)]
                records.append((str(event_id), timestamp, message))
                event_id += 1

        noise_hour = base + timedelta(hours=4)
        noise = [
            "INFO: CRITICAL: Disk failure detected in /dev/sda1\nIgnored, informational.",
            "CRITICAL: " + ("unrelated " * 18),
            "CRITICAL:Disk failure detected in /dev/sda1",
            "critical: Disk failure detected in /dev/sda1",
            "WARNING: CPU usage, 99%\nNo disk issue.",
        ]
        for index, message in enumerate(noise):
            timestamp = (noise_hour + timedelta(minutes=index + 1)).strftime("%Y-%m-%dT%H:%M:%SZ")
            records.append((str(event_id), timestamp, message))
            event_id += 1

        random.SystemRandom().shuffle(records)
        expected_rows = expected_for(records)
        write_fixture(records)
        run_script()

        dynamic_reader = read_output()
        assert dynamic_reader, "The dynamically generated output CSV is empty."
        assert dynamic_reader[0] == ["hour_timestamp", "event_count"], (
            f"Incorrect dynamic-output header: {dynamic_reader[0]}."
        )
        assert dynamic_reader[1:] == expected_rows, (
            "The script did not correctly parse, filter, score, aggregate, and sort "
            f"the dynamic CSV. Expected {expected_rows}, got {dynamic_reader[1:]}."
        )
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.lexists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            if os.path.lexists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
