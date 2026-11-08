#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/etl.sh"
RAW_PATH = "/home/user/raw_sensors.txt"
CSV_PATH = "/home/user/clean_temperature.csv"

EXPECTED_ORIGINAL = [
    "2023-10-01 10:00,22.5",
    "2023-10-01 10:01,22.8",
    "2023-10-01 10:02,23.0",
    "2023-10-01 10:03,23.0",
    "2023-10-01 10:04,23.0",
    "2023-10-01 10:05,23.5",
    "2023-10-01 10:06,23.6",
    "2023-10-01 10:07,23.6",
    "2023-10-01 10:08,23.6",
    "2023-10-01 10:09,24.0",
    "2023-10-01 10:10,24.1"
]

def read_output():
    assert os.path.isfile(CSV_PATH), f"The output CSV file is missing: {CSV_PATH}"
    with open(CSV_PATH, "r") as f:
        return f.read().strip().splitlines()

def assert_output(expected_lines):
    actual_content = read_output()
    assert len(actual_content) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines, but got {len(actual_content)} in {CSV_PATH}"
    for i, (actual, expected) in enumerate(zip(actual_content, expected_lines)):
        assert actual == expected, \
            f"Line {i+1} mismatch: expected '{expected}', got '{actual}'"

def run_etl():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, \
        f"ETL script failed with exit code {result.returncode}: {result.stderr}"
    assert os.path.isfile(CSV_PATH), "Running etl.sh did not create clean_temperature.csv"

def make_random_case():
    active = {0, 10}
    while len(active) < 6:
        active.add(secrets.randbelow(9) + 1)
    duplicate_minutes = set(sorted(active)[:2])
    lines = [f"[2023-10-01 09:59:59] DEVICE_A TEMP={(secrets.randbelow(8000)+1000)/10:.1f}"]
    last_by_minute = {}

    for minute in range(11):
        if minute in active:
            first = f"{(secrets.randbelow(8000)+1000)/10:.1f}"
            lines.append(f"[2023-10-01 10:{minute:02d}:07] DEVICE_A TEMP={first}")
            last_by_minute[minute] = first
            if minute in duplicate_minutes:
                second = f"{(secrets.randbelow(8000)+1000)/10:.1f}"
                lines.append(f"[2023-10-01 10:{minute:02d}:43] DEVICE_A TEMP={second}")
                last_by_minute[minute] = second
        other = f"{(secrets.randbelow(8000)+1000)/10:.1f}"
        lines.append(f"[2023-10-01 10:{minute:02d}:55] DEVICE_B TEMP={other}")

    lines.append(f"[2023-10-01 10:11:01] DEVICE_A TEMP={(secrets.randbelow(8000)+1000)/10:.1f}")

    expected = []
    current = None
    for minute in range(11):
        if minute in last_by_minute:
            current = last_by_minute[minute]
        expected.append(f"2023-10-01 10:{minute:02d},{current}")
    return "\n".join(lines) + "\n", expected

def test_etl_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The ETL script is missing: {SCRIPT_PATH}"

def test_clean_temperature_csv_content():
    assert os.path.isfile(CSV_PATH), f"The output CSV file is missing: {CSV_PATH}"
    assert_output(EXPECTED_ORIGINAL)

def test_etl_executes_and_transforms_current_raw_file():
    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()
    original_csv = None
    if os.path.exists(CSV_PATH):
        with open(CSV_PATH, "rb") as f:
            original_csv = f.read()

    try:
        run_etl()
        assert_output(EXPECTED_ORIGINAL)

        for _ in range(2):
            raw_data, expected = make_random_case()
            with open(RAW_PATH, "w") as f:
                f.write(raw_data)
            run_etl()
            assert_output(expected)
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        if original_csv is None:
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)
        else:
            with open(CSV_PATH, "wb") as f:
                f.write(original_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
