#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from datetime import datetime, timedelta


def test_script_exists_and_executable():
    script_path = "/home/user/clean_data.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_cleaned_data():
    cleaned_data_path = "/home/user/cleaned_data.csv"
    assert os.path.exists(cleaned_data_path), f"Cleaned data file {cleaned_data_path} does not exist."

    expected_content = """id,age,income,score
1,25,50000,0.8
4,30,75000,0.7
6,50,120000,0.85
8,35,80000,0.95
9,28,90000,0.88"""

    with open(cleaned_data_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {cleaned_data_path} does not match the expected cleaned dataset."


def test_experiment_log():
    log_path = "/home/user/experiment_log.txt"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = f.readlines()

    pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Initial: 10 rows, Cleaned: 5 rows$")

    match_found = any(pattern.match(line.strip()) for line in lines)
    assert match_found, f"No line in {log_path} matches the expected log format and counts."


def test_script_executes_pipeline_on_runtime_data():
    script_path = "/home/user/clean_data.sh"
    raw_path = "/home/user/raw_data.csv"
    cleaned_path = "/home/user/cleaned_data.csv"
    log_path = "/home/user/experiment_log.txt"

    base_id = 100000 + secrets.randbelow(800000)
    rows = [
        [str(base_id + 1), "31", "0", "0.11"],
        [str(base_id + 2), "42", "1000000", "0.22"],
        [str(base_id + 3), "", "45000", "0.33"],
        [str(base_id + 4), "27", "-1", "0.44"],
        [str(base_id + 5), "53", "1000001", "0.55"],
        [str(base_id + 6), "38", str(10000 + secrets.randbelow(800000)), "0.66"],
    ]

    # Vary both the input and expected output counts at verification time.
    for offset in range(7, 13 + secrets.randbelow(6)):
        age = "" if offset % 4 == 0 else str(20 + secrets.randbelow(50))
        if offset % 5 == 0:
            income = str(1000001 + secrets.randbelow(500000))
        elif offset % 6 == 0:
            income = str(-1 - secrets.randbelow(5000))
        else:
            income = str(secrets.randbelow(1000001))
        rows.append([str(base_id + offset), age, income, f"0.{offset:02d}"])

    expected_rows = [row for row in rows if row[1] != "" and 0 <= int(row[2]) <= 1000000]
    expected_content = "\n".join(
        ["id,age,income,score"] + [",".join(row) for row in expected_rows]
    )

    with open(raw_path, "w") as f:
        f.write("id,age,income,score\n")
        for row in rows:
            f.write(",".join(row) + "\n")

    if os.path.exists(cleaned_path):
        os.remove(cleaned_path)

    sentinel = "pre-existing log entry that must be preserved"
    with open(log_path, "w") as f:
        f.write(sentinel + "\n")

    before = datetime.now()
    result = subprocess.run(
        [script_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    after = datetime.now()

    assert result.returncode == 0, (
        f"Executing {script_path} failed with exit code {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(cleaned_path), "The script did not generate cleaned_data.csv."

    with open(cleaned_path, "r") as f:
        actual_content = f.read().strip()
    assert actual_content == expected_content, "The script did not correctly clean the runtime dataset."

    with open(log_path, "r") as f:
        log_lines = f.read().splitlines()
    assert len(log_lines) == 2, "The script must append exactly one log entry per run."
    assert log_lines[0] == sentinel, "The script overwrote the existing experiment log instead of appending."

    expected_counts = f"Initial: {len(rows)} rows, Cleaned: {len(expected_rows)} rows"
    match = re.fullmatch(
        r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] " + re.escape(expected_counts),
        log_lines[1],
    )
    assert match, "The appended log entry has incorrect formatting or runtime-derived counts."

    logged_time = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    assert before - timedelta(seconds=2) <= logged_time <= after + timedelta(seconds=2), (
        "The log timestamp was not dynamically generated when the script ran."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
