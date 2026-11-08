#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from collections import Counter

import pytest


def test_cleaner_c_and_executable_exist():
    c_file = "/home/user/cleaner.c"
    exe_file = "/home/user/cleaner"
    assert os.path.isfile(c_file), f"Source file not found: {c_file}"
    assert os.path.isfile(exe_file), f"Executable not found: {exe_file}"
    assert os.access(exe_file, os.X_OK), f"File is not executable: {exe_file}"
    with open(exe_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled ELF executable required: {exe_file}"


def test_error_log_content():
    log_file = "/home/user/error.log"
    assert os.path.isfile(log_file), f"Error log not found: {log_file}"

    with open(log_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["2", "4", "6"]
    assert lines == expected_lines, f"Expected {expected_lines} in error.log, got {lines}"


def test_clean_data_csv_content():
    csv_file = "/home/user/clean_data.csv"
    assert os.path.isfile(csv_file), f"Output CSV not found: {csv_file}"

    with open(csv_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in {csv_file}, got {len(lines)}"

    expected_data = {
        "1": 45.2,
        "3": 48.9,
        "5": 12.1,
    }
    seen_ids = []

    for line in lines:
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid CSV format in line: '{line}'"
        event_id, sensor_val = parts

        assert event_id in expected_data, f"Unexpected event_id {event_id} in output"
        seen_ids.append(event_id)
        expected_val = expected_data[event_id]

        try:
            val_float = float(sensor_val)
        except ValueError:
            pytest.fail(f"Could not parse float from sensor_val: {sensor_val}")

        assert abs(val_float - expected_val) < 0.001, \
            f"Expected sensor_val {expected_val} for event_id {event_id}, got {val_float}"

    assert Counter(seen_ids) == Counter(expected_data), \
        f"Each expected event_id must occur exactly once, got {seen_ids}"


def make_stream():
    rng = random.Random(secrets.randbits(128))
    base = rng.randint(10000, 900000)
    lines = []
    expected_rows = []
    expected_bad = []

    for i in range(1, 358):
        event_id = base + i * rng.randint(2, 9)
        value_tenths = rng.randint(-5000, 5000)
        value_text = f"{value_tenths / 10:.1f}"
        kind = i % 9

        if kind == 0:
            note = "bad \\u12G4 sequence"
            bad = True
        elif kind == 1:
            note = "short \\u1"
            bad = True
        elif kind == 2:
            note = "bad \\u-234 sequence"
            bad = True
        elif kind == 3:
            # Deliberately truncated after the escape introducer.
            line = f'{{"event_id": {event_id}, "sensor_val": {value_text}, "note": "truncated \\u'
            bad = True
        elif kind == 4:
            note = "valid uppercase \\uABCD"
            bad = False
        elif kind == 5:
            note = "two valid escapes \\u0041 and \\ua9F0"
            bad = False
        elif kind == 6:
            note = "plain text with no escape"
            bad = False
        elif kind == 7:
            note = "valid zero \\u0000 followed by text"
            bad = False
        else:
            note = "later malformed after valid \\u1234 then \\uZZZZ"
            bad = True

        if kind != 3:
            # Vary field order while retaining the promised exact field syntax.
            if i % 2:
                line = f'{{"event_id": {event_id}, "note": "{note}", "sensor_val": {value_text}}}'
            else:
                line = f'{{"sensor_val": {value_text}, "event_id": {event_id}, "note": "{note}"}}'

        assert len(line.encode()) < 1024
        lines.append(line)
        if bad:
            expected_bad.append(str(i))
        else:
            expected_rows.append((str(event_id), value_tenths / 10.0))

    return "\n".join(lines) + "\n", expected_rows, expected_bad


def run_and_check(executable, stream, expected_rows, expected_bad):
    log_file = "/home/user/error.log"
    try:
        os.remove(log_file)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        [executable],
        input=stream,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, \
        f"{executable} exited with {result.returncode}; stderr: {result.stderr}"

    output_lines = result.stdout.splitlines()
    assert len(output_lines) == len(expected_rows), \
        f"Expected {len(expected_rows)} output rows, got {len(output_lines)}"

    observed_ids = []
    for output, (expected_id, expected_value) in zip(output_lines, expected_rows):
        parts = output.split(",")
        assert len(parts) == 2, f"Invalid CSV output line: {output!r}"
        event_id, value_text = parts
        assert event_id == expected_id, \
            f"Expected event_id {expected_id}, got {event_id}"
        observed_ids.append(event_id)
        try:
            value = float(value_text)
        except ValueError:
            pytest.fail(f"Invalid sensor value in CSV output: {value_text!r}")
        assert abs(value - expected_value) < 0.001, \
            f"Expected sensor value {expected_value}, got {value}"

    assert Counter(observed_ids) == Counter(row[0] for row in expected_rows), \
        "Every valid input record must appear exactly once"
    assert os.path.isfile(log_file), "Cleaner did not create /home/user/error.log"
    with open(log_file, "r") as f:
        logged = [line.strip() for line in f if line.strip()]
    assert logged == expected_bad, \
        f"Expected corrupted line numbers {expected_bad}, got {logged}"


def test_executable_and_source_on_generated_stream():
    compiled = "/tmp/cleaner_from_source"
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/cleaner.c", "-o", compiled],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert build.returncode == 0, f"cleaner.c does not compile: {build.stderr}"

    stream, expected_rows, expected_bad = make_stream()
    run_and_check("/home/user/cleaner", stream, expected_rows, expected_bad)
    run_and_check(compiled, stream, expected_rows, expected_bad)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
