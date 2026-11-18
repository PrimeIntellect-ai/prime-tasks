#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import secrets
import subprocess

import pytest

SCRIPT_PATH = "/home/user/process_logs.sh"
INPUT_PATH = "/home/user/system_logs.csv"
OUTPUT_PATH = "/home/user/sampled_errors.csv"


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"
    if os.path.lexists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_script_exists_and_executable():
    """Verify that the process_logs.sh script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_output_file_exists():
    """Verify that the sampled_errors.csv file was generated."""
    assert os.path.exists(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file"


def test_output_file_content():
    """Verify the content of sampled_errors.csv matches the expected cleaned and sampled data."""
    expected_rows = [
        ["timestamp", "log_level", "user_id", "message"],
        ["2023-10-01T10:05:00Z", "ERROR", "USR2", "Connection timeout\nat module.network (network.c:120)\nRetrying..."],
        ["2023-10-01T10:20:00Z", "ERROR", "USR4", "Database lock exception"],
        ["2023-10-01T10:10:00Z", "CRITICAL", "USR3", "Kernel panic - not syncing"],
        ["2023-10-01T10:25:00Z", "CRITICAL", "USR5", "Out of memory\nOOM killer invoked"]
    ]

    with open(OUTPUT_PATH, 'r', newline='') as f:
        actual_rows = list(csv.reader(f))

    assert len(actual_rows) == 5, f"Expected 5 rows (including header), but got {len(actual_rows)}"
    assert actual_rows[0] == expected_rows[0], "CSV header does not match expected."
    for i in range(1, 5):
        assert actual_rows[i] == expected_rows[i], (
            f"Row {i} does not match expected data. "
            f"Expected {expected_rows[i]}, got {actual_rows[i]}"
        )


def test_user_ids_uppercase():
    """Ensure all user_ids in the output are uppercase."""
    with open(OUTPUT_PATH, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            assert row['user_id'] == row['user_id'].upper(), f"user_id {row['user_id']} is not uppercase"


def test_log_levels_order():
    """Ensure the output contains 2 ERROR logs followed by 2 CRITICAL logs."""
    with open(OUTPUT_PATH, 'r', newline='') as f:
        rows = list(csv.DictReader(f))

    assert len(rows) == 4, "Should have exactly 4 data rows."
    assert rows[0]['log_level'] == 'ERROR'
    assert rows[1]['log_level'] == 'ERROR'
    assert rows[2]['log_level'] == 'CRITICAL'
    assert rows[3]['log_level'] == 'CRITICAL'


def reference_result(rows):
    timestamp_re = re.compile(r"^(\d{4})-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
    eligible = []
    for row in rows:
        if row["log_level"] not in ("ERROR", "CRITICAL"):
            continue
        match = timestamp_re.fullmatch(row["timestamp"])
        if not match or not 2020 <= int(match.group(1)) <= 2024:
            continue
        eligible.append(dict(row))

    # Deduplication is global by exact message, retaining the earliest timestamp.
    by_message = {}
    for row in eligible:
        old = by_message.get(row["message"])
        if old is None or row["timestamp"] < old["timestamp"]:
            by_message[row["message"]] = row

    deduplicated = list(by_message.values())
    selected = []
    for level in ("ERROR", "CRITICAL"):
        group = sorted(
            (row for row in deduplicated if row["log_level"] == level),
            key=lambda row: row["timestamp"]
        )[:2]
        selected.extend(group)

    return [
        [row["timestamp"], row["log_level"], row["user_id"].upper(), row["message"]]
        for row in selected
    ]


def test_script_processes_fresh_multiline_input():
    """Execute the submitted script on unpredictable altered input and derive the answer independently."""
    token = secrets.token_hex(12)
    multiline = f"network failure {token}\nframe, one\nframe \"two\""
    shared = f"shared exact message {token}"
    rows = [
        {"timestamp": "2021-04-05T06:07:08Z", "log_level": "ERROR", "user_id": "mixEd_a", "message": multiline},
        {"timestamp": "2023-09-09T09:09:09Z", "log_level": "ERROR", "user_id": "later_a", "message": multiline},
        {"timestamp": "2020-02-02T02:02:02Z", "log_level": "ERROR", "user_id": "early_b", "message": f"error, quoted \"value\" {token}"},
        {"timestamp": "2024-08-08T08:08:08Z", "log_level": "ERROR", "user_id": "third_e", "message": f"third error {token}"},
        {"timestamp": "2020-01-01T00:00:01Z", "log_level": "CRITICAL", "user_id": "crit_shared", "message": shared},
        {"timestamp": "2021-01-01T00:00:01Z", "log_level": "ERROR", "user_id": "error_shared", "message": shared},
        {"timestamp": "2020-03-03T03:03:03Z", "log_level": "CRITICAL", "user_id": "crit_d", "message": f"critical multiline {token}\ntrace line"},
        {"timestamp": "2022-03-03T03:03:03Z", "log_level": "CRITICAL", "user_id": "crit_e", "message": f"third critical {token}"},
        {"timestamp": "2024-04-04T04:04:04Z", "log_level": "CRITICAL", "user_id": "crit_f", "message": f"fourth critical {token}"},
        {"timestamp": "2020-01-01T00:00:00Z", "log_level": "INFO", "user_id": "info", "message": multiline},
        {"timestamp": "2019-12-31T23:59:59Z", "log_level": "ERROR", "user_id": "old", "message": f"old year {token}"},
        {"timestamp": "2025-01-01T00:00:00Z", "log_level": "CRITICAL", "user_id": "future", "message": f"future year {token}"},
        {"timestamp": "2022-1-01T00:00:00Z", "log_level": "ERROR", "user_id": "badfmt", "message": f"bad format {token}"},
        {"timestamp": "2022-01-01T00:00:00Zextra", "log_level": "ERROR", "user_id": "suffix", "message": f"bad suffix {token}"},
        {"timestamp": "2022-01-01T00:00:00Z", "log_level": "error", "user_id": "lowerlevel", "message": f"wrong level {token}"},
    ]
    random.SystemRandom().shuffle(rows)
    expected = reference_result(rows)
    assert len(expected) == 4

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    try:
        with open(INPUT_PATH, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["timestamp", "log_level", "user_id", "message"])
            writer.writeheader()
            writer.writerows(rows)

        with open(OUTPUT_PATH, "w") as f:
            f.write("stale output that must be replaced\n")

        result = subprocess.run(
            [SCRIPT_PATH], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert result.returncode == 0, (
            f"Script failed on altered input with exit code {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(OUTPUT_PATH), "Script did not generate sampled_errors.csv"

        with open(OUTPUT_PATH, "r", newline="") as f:
            actual = list(csv.reader(f))
        assert actual == [["timestamp", "log_level", "user_id", "message"]] + expected
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        subprocess.run(
            [SCRIPT_PATH], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
