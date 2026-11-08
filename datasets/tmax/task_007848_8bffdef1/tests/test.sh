#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import difflib
import os
import re
import secrets
import stat
import subprocess
from collections import Counter
from datetime import datetime, timedelta, timezone

SCRIPT_PATH = "/home/user/run_etl.sh"
CSV_PATH = "/home/user/correlated_errors.csv"
LOG_PATH = "/home/user/etl_pipeline.log"
APP_A_PATH = "/home/user/app_a.log"
APP_B_PATH = "/home/user/app_b.log"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_run_script_and_check_csv():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    assert os.path.isfile(CSV_PATH), f"Output CSV {CSV_PATH} was not created."
    with open(CSV_PATH, "r", newline="") as f:
        lines = list(csv.reader(f))

    assert len(lines) == 2, f"Expected 2 correlated pairs, but found {len(lines)}."

    msgA1 = "Connection reset by peer"
    msgB1 = "Connection was reset by peer"
    ratio1 = round(difflib.SequenceMatcher(None, msgA1, msgB1).ratio(), 2)
    msgA2 = "Database timeout occurred during query"
    msgB2 = "Database timeout during query execution"
    ratio2 = round(difflib.SequenceMatcher(None, msgA2, msgB2).ratio(), 2)

    expected_pair_1 = ["1698240600", "1698240660", f"{ratio1:.2f}", msgA1, msgB1]
    expected_pair_2 = ["1698242400", "1698242520", f"{ratio2:.2f}", msgA2, msgB2]

    def match_pair(expected, actual):
        return (
            expected[0] == actual[0]
            and expected[1] == actual[1]
            and abs(float(expected[2]) - float(actual[2])) < 0.02
            and expected[3] == actual[3]
            and expected[4] == actual[4]
        )

    assert any(match_pair(expected_pair_1, row) for row in lines), \
        f"Expected pair 1 not found or incorrect in CSV: {expected_pair_1}"
    assert any(match_pair(expected_pair_2, row) for row in lines), \
        f"Expected pair 2 not found or incorrect in CSV: {expected_pair_2}"


def test_etl_against_fresh_inputs_and_logging():
    token = secrets.token_hex(10)
    base_epoch = 1710000000 + secrets.randbelow(20000000)
    base_epoch -= base_epoch % 60

    a_zone = timezone(timedelta(hours=-4))
    b_zone = timezone(timedelta(hours=5, minutes=30))

    a_records = [
        (base_epoch, f"Critical service {token} connection reset by peer"),
        (base_epoch + 1800, f"Worker {token} exhausted memory while processing batch"),
        (base_epoch + 3600, f"Boundary {token} request failed"),
        (base_epoch + 7200, f"Completely unrelated alpha {token}"),
    ]
    b_records = [
        (base_epoch + 121, f"Critical service {token} connection was reset by peer"),
        (base_epoch + 2100, f"Worker {token} exhausted memory during processing batch"),
        (base_epoch + 3901, f"Boundary {token} request failed"),
        (base_epoch + 10800, f"Different diagnostic omega {token[::-1]}"),
    ]

    def format_a(epoch, message):
        stamp = datetime.fromtimestamp(epoch, a_zone).strftime("%Y-%m-%d %H:%M:%S %z")
        return f"{stamp} | {message}\n"

    def format_b(epoch, message):
        stamp = datetime.fromtimestamp(epoch, b_zone).strftime("%d/%b/%Y:%H:%M:%S %z")
        return f"{stamp} - {message}\n"

    expected = []
    for epoch_a, msg_a in a_records:
        for epoch_b, msg_b in b_records:
            ratio = difflib.SequenceMatcher(None, msg_a, msg_b).ratio()
            if abs(epoch_a - epoch_b) <= 300 and ratio >= 0.70:
                expected.append((str(epoch_a), str(epoch_b), f"{ratio:.2f}", msg_a, msg_b))

    assert expected, "Verifier generated no correlated test pairs."

    original_a = open(APP_A_PATH, "rb").read()
    original_b = open(APP_B_PATH, "rb").read()
    before_log = open(LOG_PATH, "r").read() if os.path.exists(LOG_PATH) else ""

    try:
        with open(APP_A_PATH, "w") as f:
            f.writelines(format_a(epoch, message) for epoch, message in a_records)
        with open(APP_B_PATH, "w") as f:
            f.writelines(format_b(epoch, message) for epoch, message in b_records)

        started = datetime.now(timezone.utc)
        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
        finished = datetime.now(timezone.utc)
        assert result.returncode == 0, f"Script failed on fresh inputs. stderr: {result.stderr}"
        assert os.path.isfile(CSV_PATH), f"Output CSV {CSV_PATH} was not created."

        with open(CSV_PATH, "r", newline="") as f:
            rows = list(csv.reader(f))
        assert all(len(row) == 5 for row in rows), "Every CSV row must contain exactly five fields."
        actual = Counter(tuple(row) for row in rows)
        assert actual == Counter(expected), f"Fresh-input CSV mismatch. Expected {expected}, got {rows}"

        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
        after_log = open(LOG_PATH, "r").read()
        assert after_log.startswith(before_log), "The pipeline log was overwritten instead of appended to."
        appended = after_log[len(before_log):]
        pattern = re.compile(
            r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC\] PIPELINE SUCCESS - Processed "
            + str(len(expected))
            + r" correlated pairs$",
            re.MULTILINE,
        )
        matches = pattern.findall(appended)
        assert matches, f"No correctly formatted log entry for {len(expected)} pairs was appended."
        logged_at = datetime.strptime(matches[-1], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        assert started - timedelta(seconds=2) <= logged_at <= finished + timedelta(seconds=2), \
            "The appended pipeline timestamp does not reflect this execution in UTC."
    finally:
        with open(APP_A_PATH, "wb") as f:
            f.write(original_a)
        with open(APP_B_PATH, "wb") as f:
            f.write(original_b)


def test_pipeline_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        content = f.read()
    assert "PIPELINE SUCCESS - Processed 2 correlated pairs" in content, \
        f"Expected success message not found in {LOG_PATH}."


def test_cron_job():
    result = subprocess.run(["crontab", "-l", "-u", "user"], capture_output=True, text=True)
    if result.returncode != 0:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."

    cron_lines = result.stdout.strip().split("\n")
    found_cron = False
    found_full_hourly_cron = False
    for line in cron_lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6:
            minute = parts[0]
            command = " ".join(parts[5:])
            if minute == "0" and SCRIPT_PATH in command:
                found_cron = True
            if parts[:5] == ["0", "*", "*", "*", "*"] and SCRIPT_PATH in command:
                found_full_hourly_cron = True

    assert found_cron, f"Cron job for {SCRIPT_PATH} at minute 0 not found in crontab."
    assert found_full_hourly_cron, \
        f"Cron job for {SCRIPT_PATH} must use the full hourly schedule '0 * * * *'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
