#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import json
import os
import re
import subprocess


def test_source_file_exists():
    path = "/home/user/etl.c"
    assert os.path.isfile(path), f"Source file {path} does not exist."


def test_executable_exists():
    path = "/home/user/etl"
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF executable."


def test_output_csv_content():
    path = "/home/user/output.csv"
    assert os.path.isfile(path), f"Output file {path} does not exist."

    expected_content = """timestamp,sensor,value
2023-01-01T12:00:00Z,alpha,10.0
2023-01-01T12:00:00Z,beta,12.0
2023-01-01T12:01:00Z,alpha,10.0
2023-01-01T12:01:00Z,beta,12.0
2023-01-01T12:02:00Z,alpha,10.5
2023-01-01T12:02:00Z,beta,12.5
2023-01-01T12:03:00Z,alpha,10.5
2023-01-01T12:03:00Z,beta,12.5
2023-01-01T12:04:00Z,alpha,10.5
2023-01-01T12:04:00Z,beta,12.5
2023-01-01T12:05:00Z,alpha,11.2
2023-01-01T12:05:00Z,beta,13.0
"""

    with open(path, 'r', encoding='utf-8') as f:
        actual_content = f.read()

    # Normalize line endings and strip trailing whitespace
    actual_lines = [line.strip() for line in actual_content.strip().splitlines()]
    expected_lines = [line.strip() for line in expected_content.strip().splitlines()]

    assert actual_lines == expected_lines, f"Content of {path} does not match the expected output."


def numeric_value(text):
    match = re.match(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", text)
    assert match, f"Test fixture has no numeric prefix: {text!r}"
    return float(match.group(0))


def expected_lines(records):
    first_by_minute = {}
    for record in records:
        timestamp = datetime.datetime.strptime(record["time"], "%Y-%m-%dT%H:%M:%SZ")
        minute = timestamp.replace(second=0)
        if minute not in first_by_minute:
            first_by_minute[minute] = {
                "alpha": numeric_value(record["alpha"]),
                "beta": numeric_value(record["beta"]),
            }

    start = min(first_by_minute)
    end = max(first_by_minute)
    result = ["timestamp,sensor,value"]
    current = start
    carried = None
    while current <= end:
        if current in first_by_minute:
            carried = first_by_minute[current]
        assert carried is not None
        stamp = current.strftime("%Y-%m-%dT%H:%M:00Z")
        for sensor in sorted(carried):
            result.append(f"{stamp},{sensor},{carried[sensor]:.1f}")
        current += datetime.timedelta(minutes=1)
    return result


def write_input(records):
    with open("/home/user/data.jsonl", "w", encoding="utf-8", newline="\n") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=True, separators=(",", ":")) + "\n")


def test_program_executes_etl_logic_on_additional_inputs():
    compiled_from_source = "/tmp/etl_from_submitted_source"
    build = subprocess.run(
        ["gcc", "/home/user/etl.c", "-o", compiled_from_source],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"Submitted C source does not compile:\n{build.stderr}"

    cases = [
        [
            {"time": "2024-07-15T08:57:04Z", "alpha": "-2.5°C", "beta": "100.26°C"},
            {"time": "2024-07-15T08:57:51Z", "alpha": "99.9°C", "beta": "99.9°C"},
            {"time": "2024-07-15T08:59:33Z", "alpha": "-1.1°C", "beta": "101.04°C"},
            {"time": "2024-07-15T09:02:01Z", "alpha": "0.4°C", "beta": "103.87°C"},
        ],
        [
            {"time": "2025-03-09T23:58:59Z", "alpha": "7.25°C", "beta": "8.84°C"},
            {"time": "2025-03-10T00:01:12Z", "alpha": "9.06°C", "beta": "10.14°C"},
            {"time": "2025-03-10T00:01:49Z", "alpha": "55.0°C", "beta": "66.0°C"},
        ],
    ]

    with open("/home/user/data.jsonl", "rb") as f:
        original_input = f.read()
    with open("/home/user/output.csv", "rb") as f:
        original_output = f.read()

    try:
        # Exercise both the submitted executable and a fresh build of the submitted C source.
        for executable in ("/home/user/etl", compiled_from_source):
            for records in cases:
                write_input(records)
                if os.path.exists("/home/user/output.csv"):
                    os.remove("/home/user/output.csv")
                run = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
                assert run.returncode == 0, (
                    f"{executable} failed on an additional input with exit code "
                    f"{run.returncode}:\n{run.stderr}"
                )
                assert os.path.isfile("/home/user/output.csv"), (
                    f"{executable} did not create /home/user/output.csv"
                )
                with open("/home/user/output.csv", "r", encoding="utf-8") as f:
                    actual = [line.strip() for line in f.read().strip().splitlines()]
                expected = expected_lines(records)
                assert actual == expected, (
                    f"{executable} produced incorrect ETL output on an additional input.\n"
                    f"Expected: {expected}\nActual: {actual}"
                )
    finally:
        with open("/home/user/data.jsonl", "wb") as f:
            f.write(original_input)
        with open("/home/user/output.csv", "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
