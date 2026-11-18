#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from datetime import datetime, timedelta

import pytest

SOURCE_FILE = "/home/user/etl_processor.c"
EXECUTABLE_FILE = "/home/user/etl_processor"
COMPILED_FROM_SOURCE = "/tmp/etl_processor_from_source"
INPUT_FILE = "/home/user/raw_data.log"
OUTPUT_FILE = "/home/user/summary.csv"

ORIGINAL_INPUT = """LOG_TIME:2023-10-15T10:01:23Z | SID:S01 | VAL:20.0
LOG_TIME:2023-10-15T10:14:59Z | SID:S01 | VAL:22.0
LOG_TIME:2023-10-15T10:14:59Z | SID:S02 | VAL:15.0
LOG_TIME:2023-10-15T10:16:00Z | SID:S01 | VAL:25.0
LOG_TIME:2023-10-15T10:20:00Z | SID:S01 | VAL:150.0
LOG_TIME:2023-10-15T10:29:59Z | SID:S01 | VAL:27.0
LOG_TIME:2023-10-15T10:30:00Z | SID:S03 | VAL:99.9
LOG_TIME:2023-10-15T10:44:59Z | SID:S03 | VAL:100.1
LOG_TIME:2023-10-15T11:00:00Z | SID:S01 | VAL:50.0
"""

EXPECTED_ORIGINAL = [
    "2023-10-15T10:00:00Z,S01,21.00",
    "2023-10-15T10:00:00Z,S02,15.00",
    "2023-10-15T10:15:00Z,S01,26.00",
    "2023-10-15T10:30:00Z,S03,99.90",
    "2023-10-15T11:00:00Z,S01,50.00",
]


def compile_source():
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE_FILE, "-o", COMPILED_FROM_SOURCE],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"Failed to compile {SOURCE_FILE} with gcc:\n{result.stdout}\n{result.stderr}"
    )
    assert os.path.isfile(COMPILED_FROM_SOURCE)
    assert os.access(COMPILED_FROM_SOURCE, os.X_OK)


def run_with_input(executable, input_text):
    with open(INPUT_FILE, "w") as f:
        f.write(input_text)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run([executable], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        f"Execution of {executable} failed with status {result.returncode}: {result.stderr}"
    )
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."

    with open(OUTPUT_FILE, "r") as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()]


def test_c_program_exists_and_executable():
    assert os.path.exists(SOURCE_FILE), f"Source file {SOURCE_FILE} does not exist."
    assert os.path.isfile(SOURCE_FILE), f"Source path {SOURCE_FILE} is not a regular file."
    assert os.path.exists(EXECUTABLE_FILE), f"Executable file {EXECUTABLE_FILE} does not exist."
    assert os.path.isfile(EXECUTABLE_FILE), f"Executable path {EXECUTABLE_FILE} is not a regular file."
    assert os.access(EXECUTABLE_FILE, os.X_OK), f"File {EXECUTABLE_FILE} is not executable."
    compile_source()


def test_etl_processor_output():
    actual_lines = run_with_input(EXECUTABLE_FILE, ORIGINAL_INPUT)

    assert len(actual_lines) == len(EXPECTED_ORIGINAL), (
        f"Expected {len(EXPECTED_ORIGINAL)} lines in {OUTPUT_FILE}, "
        f"but found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, EXPECTED_ORIGINAL)):
        assert actual == expected, (
            f"Line {i + 1} mismatch: expected '{expected}', got '{actual}'."
        )


def test_source_and_executable_process_generated_data():
    compile_source()
    rng = random.SystemRandom()

    year = rng.randint(2024, 2032)
    month = rng.randint(1, 12)
    day = rng.randint(1, 25)
    base = datetime(year, month, day, rng.randint(0, 8), 0, 0)
    sensors = rng.sample([f"S{i:02d}" for i in range(10, 90)], 5)
    bucket_offsets = [0, 15, 30, 60, 135, 225, 24 * 60 + 15]

    records = []
    aggregates = {}

    def add_valid(when, sensor, value):
        records.append(
            f"LOG_TIME:{when.strftime('%Y-%m-%dT%H:%M:%SZ')} | SID:{sensor} | VAL:{value:.1f}"
        )
        bucket = when.replace(minute=(when.minute // 15) * 15, second=0)
        aggregates.setdefault((bucket, sensor), []).append(value)

    for index, minute_offset in enumerate(bucket_offsets):
        bucket = base + timedelta(minutes=minute_offset)
        first_sensor = sensors[index % len(sensors)]
        second_sensor = sensors[(index + 2) % len(sensors)]

        a = rng.randint(0, 80)
        b = rng.randint(0, 80)
        add_valid(bucket + timedelta(seconds=rng.randint(0, 40)), first_sensor, float(a))
        add_valid(bucket + timedelta(minutes=14, seconds=rng.randint(41, 59)), first_sensor, float(b))
        add_valid(bucket + timedelta(minutes=rng.randint(1, 13), seconds=rng.randint(0, 59)), second_sensor, float(rng.randint(0, 100)))

    # Exercise both inclusive validation boundaries.
    add_valid(base + timedelta(minutes=45), sensors[0], 0.0)
    add_valid(base + timedelta(minutes=59, seconds=59), sensors[0], 100.0)

    invalid_time = base + timedelta(minutes=75)
    records.extend([
        f"LOG_TIME:{invalid_time.strftime('%Y-%m-%dT%H:%M:%SZ')} | SID:{sensors[1]} | VAL:-{rng.randint(1, 50)}.0",
        f"LOG_TIME:{invalid_time.strftime('%Y-%m-%dT%H:%M:%SZ')} | SID:{sensors[2]} | VAL:{rng.randint(101, 250)}.0",
        "this is not a telemetry record",
        "LOG_TIME:broken | SID:BAD | VAL:not-a-number",
    ])
    rng.shuffle(records)
    generated_input = "\n".join(records) + "\n"

    expected = []
    for (bucket, sensor), values in sorted(aggregates.items(), key=lambda item: (item[0][0], item[0][1])):
        expected.append(
            f"{bucket.strftime('%Y-%m-%dT%H:%M:00Z')},{sensor},{sum(values) / len(values):.2f}"
        )

    try:
        submitted_output = run_with_input(EXECUTABLE_FILE, generated_input)
        source_output = run_with_input(COMPILED_FROM_SOURCE, generated_input)
        assert submitted_output == expected, (
            "The submitted executable did not correctly parse, validate, bucket, aggregate, "
            f"and sort generated telemetry.\nExpected: {expected}\nActual: {submitted_output}"
        )
        assert source_output == expected, (
            f"The program compiled from {SOURCE_FILE} did not produce the required result.\n"
            f"Expected: {expected}\nActual: {source_output}"
        )
        assert submitted_output == source_output, (
            "The installed executable does not behave like the executable compiled from the submitted C source."
        )
    finally:
        with open(INPUT_FILE, "w") as f:
            f.write(ORIGINAL_INPUT)


def test_cron_job_configured():
    try:
        result = subprocess.run(
            ["crontab", "-u", "user", "-l"], check=True, capture_output=True, text=True
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve crontab for user 'user'. Is it configured for that user?")

    pattern = re.compile(
        r'^((0,15,30,45|\*/15)\s+\*\s+\*\s+\*\s+\*)\s+(.*?)?/home/user/etl_processor',
        re.MULTILINE,
    )
    match = pattern.search(crontab_content)
    assert match is not None, (
        "Cron job for /home/user/etl_processor running every 15 minutes is not correctly configured for user 'user'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
