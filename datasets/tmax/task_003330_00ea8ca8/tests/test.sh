#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import secrets
import subprocess
from collections import defaultdict
from datetime import datetime
from decimal import Decimal

RAW_PATH = "/home/user/raw_sensors.csv"
OUTPUT_PATH = "/home/user/cleaned_sensors.csv"
GO_PATH = "/home/user/clean.go"


def test_cleaned_sensors_csv_content():
    file_path = OUTPUT_PATH

    # Check if file exists
    assert os.path.exists(file_path), f"The output file {file_path} was not created."
    assert os.path.isfile(file_path), f"{file_path} is not a regular file."

    expected_content = """bucket,sensor_id,avg_temp
2023-10-01T10:00:00Z,loc1,23.50
2023-10-01T10:00:00Z,loc2,24.00
2023-10-01T10:00:00Z,loc3,22.00
2023-10-01T11:00:00Z,loc1,20.50
2023-10-01T11:00:00Z,loc2,21.50
2023-10-01T11:00:00Z,loc3,19.50"""

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"The content of {file_path} does not match the expected output. Got:\n{actual_content}"


def test_go_script_exists():
    assert os.path.exists(GO_PATH), f"The Go program {GO_PATH} was not created."
    assert os.path.isfile(GO_PATH), f"{GO_PATH} is not a regular file."


def derive_expected(raw_text):
    lines = raw_text.splitlines()
    seen = set()
    groups = defaultdict(list)

    for raw_row in lines[1:]:
        digest = hashlib.sha256(raw_row.encode("utf-8")).digest()
        if digest in seen:
            continue
        seen.add(digest)

        row = next(csv.reader([raw_row]))
        timestamp = datetime.fromisoformat(row[0].replace("Z", "+00:00"))
        bucket = timestamp.replace(minute=0, second=0, microsecond=0).strftime("%Y-%m-%dT%H:00:00Z")
        for sensor_id, value in zip(("loc1", "loc2", "loc3"), row[2:5]):
            groups[(bucket, sensor_id)].append(Decimal(value))

    output = ["bucket,sensor_id,avg_temp"]
    for (bucket, sensor_id), values in sorted(groups.items()):
        average = sum(values) / Decimal(len(values))
        output.append(f"{bucket},{sensor_id},{average:.2f}")
    return "\n".join(output)


def test_go_program_executes_pipeline_on_fresh_input():
    original_raw = open(RAW_PATH, "rb").read()
    original_output = open(OUTPUT_PATH, "rb").read() if os.path.isfile(OUTPUT_PATH) else None

    day = 10 + secrets.randbelow(10)
    hour = 3 + secrets.randbelow(12)
    base = 10 + secrets.randbelow(20)
    token = secrets.token_hex(8)

    row_a = f"2024-07-{day:02d}T{hour:02d}:47:00Z,{token},{base}.0,{base + 1}.5,{base - 2}.0"
    row_b = f"2024-07-{day:02d}T{hour:02d}:08:00Z,{token},{base + 3}.5,{base - 1}.0,{base + 4}.5"
    row_c = f"2024-07-{day:02d}T{hour + 1:02d}:52:00Z,{token},{base - 4}.0,{base + 6}.5,{base + 1}.0"
    row_d = f"2024-07-{day:02d}T{hour + 1:02d}:03:00Z,{token},{base + 2}.0,{base + 1}.5,{base - 3}.0"

    # Rows are deliberately unsorted, and exact duplicates have values that
    # would alter the averages if they were not removed.
    raw_text = "\n".join([
        "timestamp,metadata,temp_loc1,temp_loc2,temp_loc3",
        row_c,
        row_a,
        row_b,
        row_a,
        row_d,
        row_c,
    ]) + "\n"
    expected = derive_expected(raw_text)

    try:
        with open(RAW_PATH, "w", newline="") as f:
            f.write(raw_text)
        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        result = subprocess.run(
            ["go", "run", GO_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert result.returncode == 0, f"The Go program failed to compile or run:\n{result.stdout}"
        assert os.path.exists(OUTPUT_PATH), f"The Go program did not create {OUTPUT_PATH}."
        assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a regular file."

        with open(OUTPUT_PATH, "r") as f:
            actual = f.read().strip()
        assert actual == expected, f"The Go program produced incorrect output for fresh input.\nExpected:\n{expected}\nGot:\n{actual}"
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        if original_output is None:
            if os.path.lexists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
