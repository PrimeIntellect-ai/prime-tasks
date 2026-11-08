#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import random
import secrets
import stat
import subprocess
import uuid
import pytest

SCRIPT_PATH = "/home/user/calculate_billing.py"
CORRUPT_LOG_PATH = "/home/user/corrupt_lines.log"
BILLING_SUMMARY_PATH = "/home/user/billing_summary.json"
APP_LOGS_PATH = "/home/user/app_logs.csv"

CANONICAL_LOGS = """timestamp,user_id,bytes,duration,status
2023-10-01T10:00,user1,5242880,10.0,200
2023-10-01T10:05,user2,1048576,5.0,200
2023-10-01T10:10,user1,ERR,12.0,500
2023-10-01T10:15,user3,20971520,100.0,200
2023-10-01T10:20,user2,,8.0,400
2023-10-01T10:25,user4,10485760,20.0,200
"""


def run_script(input_text):
    with open(APP_LOGS_PATH, "w", newline="") as f:
        f.write(input_text)

    for output_path in (CORRUPT_LOG_PATH, BILLING_SUMMARY_PATH):
        try:
            os.remove(output_path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    with open(APP_LOGS_PATH, "r", newline="") as f:
        assert f.read() == input_text, "The script must not modify its input log."


def test_script_is_present_and_regular():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} is missing."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a regular file, not a symlink."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."


def test_unseen_log_behavior():
    rng = random.SystemRandom()
    user_a = "user_" + uuid.uuid4().hex
    user_b = "user_" + uuid.uuid4().hex

    rows = [
        ["2026-01-01T00:00", user_a, str(1048576 * rng.randint(1, 20)), str(rng.randint(1, 80) / 4), "200"],
        ["2026-01-01T00:01", user_a, "not-a-number-" + secrets.token_hex(4), "7.5", "500"],
        ["2026-01-01T00:02", user_b, str(1048576 * rng.randint(1, 20)), str(rng.randint(1, 80) / 4), "200"],
        ["2026-01-01T00:03", user_b, "3145728", "", "400"],
        ["2026-01-01T00:04", user_a, str(rng.randint(1, 9000000)), str(rng.randint(1, 80) / 4), "200"],
        ["2026-01-01T00:05", user_b, "", "2.25", "400"],
    ]
    rng.shuffle(rows)

    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(["timestamp", "user_id", "bytes", "duration", "status"])
    writer.writerows(rows)
    input_text = stream.getvalue()

    expected_corrupt = []
    expected_billing = {}
    for line_number, row in enumerate(rows, start=2):
        try:
            b = float(row[2])
            d = float(row[3])
        except ValueError:
            expected_corrupt.append(str(line_number))
            continue
        cost = (b / 1048576.0) * 0.02 + d * 0.005
        expected_billing[row[1]] = expected_billing.get(row[1], 0.0) + cost
    expected_billing = {user: round(total, 4) for user, total in expected_billing.items()}

    run_script(input_text)

    assert os.path.isfile(CORRUPT_LOG_PATH), f"File {CORRUPT_LOG_PATH} is missing."
    with open(CORRUPT_LOG_PATH, "r") as f:
        actual_corrupt = [line.strip() for line in f if line.strip()]
    assert actual_corrupt == expected_corrupt, (
        f"Expected corrupt lines {expected_corrupt}, got {actual_corrupt}."
    )

    assert os.path.isfile(BILLING_SUMMARY_PATH), f"File {BILLING_SUMMARY_PATH} is missing."
    with open(BILLING_SUMMARY_PATH, "r") as f:
        try:
            actual_billing = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {BILLING_SUMMARY_PATH} is not valid JSON.")
    assert actual_billing == expected_billing, (
        f"Expected billing {expected_billing}, got {actual_billing}."
    )


def test_corrupt_lines_log():
    run_script(CANONICAL_LOGS)
    assert os.path.isfile(CORRUPT_LOG_PATH), f"File {CORRUPT_LOG_PATH} is missing."

    expected_corrupt_lines = []

    with open(APP_LOGS_PATH, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        for i, row in enumerate(reader, start=2):
            try:
                float(row[2])
                float(row[3])
            except ValueError:
                expected_corrupt_lines.append(str(i))

    with open(CORRUPT_LOG_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_corrupt_lines, (
        f"Contents of {CORRUPT_LOG_PATH} are incorrect. "
        f"Expected {expected_corrupt_lines}, got {actual_lines}."
    )


def test_billing_summary_json():
    run_script(CANONICAL_LOGS)
    assert os.path.isfile(BILLING_SUMMARY_PATH), f"File {BILLING_SUMMARY_PATH} is missing."

    expected_billing = {}
    with open(APP_LOGS_PATH, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                b = float(row['bytes'])
                d = float(row['duration'])
                user = row['user_id']
                cost = (b / 1048576.0) * 0.02 + (d * 0.005)
                expected_billing[user] = expected_billing.get(user, 0.0) + cost
            except ValueError:
                continue

    for user in expected_billing:
        expected_billing[user] = round(expected_billing[user], 4)

    with open(BILLING_SUMMARY_PATH, 'r') as f:
        try:
            actual_billing = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {BILLING_SUMMARY_PATH} is not a valid JSON.")

    assert actual_billing == expected_billing, (
        f"Contents of {BILLING_SUMMARY_PATH} are incorrect. "
        f"Expected {expected_billing}, got {actual_billing}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
