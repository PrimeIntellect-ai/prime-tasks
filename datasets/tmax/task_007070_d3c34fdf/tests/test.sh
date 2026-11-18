#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import json
import math
import os
import secrets
import shutil
import stat
import subprocess
from pathlib import Path

PROGRAM = Path("/home/user/process.go")
INPUT = Path("/home/user/telemetry.jsonl")
OUTPUT = Path("/home/user/hourly_stats.csv")

ORIGINAL_EXPECTED = [
    ["2023-10-12T14:00:00Z", "2", "5.00"],
    ["2023-10-12T15:00:00Z", "2", "10.00"],
    ["2023-10-13T09:00:00Z", "1", "10.00"],
]


def remove_output():
    if os.path.lexists(OUTPUT):
        if OUTPUT.is_dir() and not OUTPUT.is_symlink():
            shutil.rmtree(OUTPUT)
        else:
            OUTPUT.unlink()


def run_program():
    remove_output()
    result = subprocess.run(
        ["go", "run", str(PROGRAM)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"process.go failed:\n{result.stdout}"


def test_csv_exists():
    file_path = "/home/user/hourly_stats.csv"
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."


def read_rows():
    with open(OUTPUT, "r", newline="") as f:
        return list(csv.reader(f))


def assert_rows(expected_data):
    file_path = "/home/user/hourly_stats.csv"
    rows = read_rows()
    assert len(rows) > 0, f"The file {file_path} is empty."

    expected_header = ["hour", "login_count", "avg_distance"]
    assert rows[0] == expected_header, f"Expected header {expected_header}, but got {rows[0]}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, but got {len(data_rows)}"

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}"


def test_csv_contents():
    assert_rows(ORIGINAL_EXPECTED)


def make_dynamic_case():
    rng = secrets.SystemRandom()
    base = datetime.datetime(
        2024 + secrets.randbelow(2),
        1 + secrets.randbelow(10),
        1 + secrets.randbelow(18),
        secrets.randbelow(12),
        tzinfo=datetime.timezone.utc,
    )
    hours = [base, base + datetime.timedelta(hours=3), base + datetime.timedelta(hours=29)]
    lines = []
    aggregates = {}

    for hour_index, hour in enumerate(hours):
        count = 2 + (hour_index % 2)
        key = hour.strftime("%Y-%m-%dT%H:00:00Z")
        aggregates[key] = []

        for event_index in range(count):
            event_time = hour + datetime.timedelta(
                minutes=3 + event_index * 17,
                seconds=7 + hour_index + event_index,
            )
            timestamp = event_time.strftime("%Y-%m-%dT%H:%M:%SZ")
            x = 50 + secrets.randbelow(35) - 17
            y = 50 + secrets.randbelow(35) - 17
            action = ["login", "LOGIN", "LoGiN"][event_index % 3]
            record = {"timestamp": timestamp, "action": action, "x": x, "y": y}
            line = json.dumps(record)

            if hour_index == 1 and event_index == 0:
                line = json.dumps({"timestamp": timestamp, "action": "__ESC__", "x": x, "y": y})
                line = line.replace('"__ESC__"', r'"log\u0069n"')

            lines.append(line)
            aggregates[key].append(math.hypot(x - 50.0, y - 50.0))

        nonlogin_time = (hour + datetime.timedelta(minutes=58)).strftime("%Y-%m-%dT%H:%M:%SZ")
        lines.append(json.dumps({"timestamp": nonlogin_time, "action": "login-extra", "x": 0, "y": 0}))
        lines.append(json.dumps({"timestamp": nonlogin_time, "action": "logout", "x": 100, "y": 100}))

    bad_time = (hours[0] + datetime.timedelta(minutes=41)).strftime("%Y-%m-%dT%H:%M:%SZ")
    bad_line = json.dumps({"timestamp": bad_time, "action": "__BAD__", "x": 0, "y": 0})
    lines.append(bad_line.replace('"__BAD__"', r'"log\u00XXin"'))
    lines.append('{"timestamp": "broken", this is not json}')
    rng.shuffle(lines)

    expected = []
    for key in sorted(aggregates):
        distances = aggregates[key]
        expected.append([key, str(len(distances)), f"{sum(distances) / len(distances):.2f}"])

    return "\n".join(lines) + "\n", expected


def main():
    assert PROGRAM.exists(), f"The file {PROGRAM} does not exist."
    assert stat.S_ISREG(os.lstat(PROGRAM).st_mode), f"The path {PROGRAM} is not a regular file."
    assert PROGRAM.stat().st_size > 0, f"The file {PROGRAM} is empty."

    original_input = INPUT.read_bytes()
    try:
        run_program()
        test_csv_exists()
        test_csv_contents()

        dynamic_input, dynamic_expected = make_dynamic_case()
        INPUT.write_text(dynamic_input, encoding="utf-8")
        run_program()
        test_csv_exists()
        assert_rows(dynamic_expected)
    finally:
        INPUT.write_bytes(original_input)

    run_program()
    test_csv_exists()
    test_csv_contents()


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
