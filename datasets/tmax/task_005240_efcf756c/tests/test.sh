#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shlex
import subprocess
from datetime import datetime, timedelta, timezone

import pytest

SCRIPT_PATH = "/home/user/process_logs.py"
EVENTS_PATH = "/home/user/inputs/events.csv"
METRICS_PATH = "/home/user/inputs/metrics.csv"
OUTPUT_PATH = "/home/user/output/merged_data.csv"
LOG_PATH = "/home/user/logs/etl.log"

EXPECTED_ORIGINAL = (
    "minute_timestamp,event_id,action_token,avg_cpu,avg_ram\n"
    "2023-10-15 14:32:00,1,restart,87.8,60.6\n"
    "2023-10-15 14:32:00,2,warning,87.8,60.6\n"
    "2023-10-15 14:33:00,3,deploying,75.0,65.5\n"
    "2023-10-15 14:35:00,4,crash,20.5,40.0"
)


def test_process_logs_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_merged_data_csv_content():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == EXPECTED_ORIGINAL.strip(), (
        f"The content of {OUTPUT_PATH} does not match the expected output.\n"
        f"Expected:\n{EXPECTED_ORIGINAL}\n"
        f"Actual:\n{actual_content}"
    )


def test_etl_log_content():
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} does not exist."

    with open(LOG_PATH, "r") as f:
        log_content = f.read().strip()

    lines = log_content.split("\n")
    assert len(lines) > 0, "The log file is empty."

    last_line = lines[-1]
    match = re.search(
        r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] SUCCESS: Processed 4 events",
        last_line,
    )
    assert match is not None, (
        "The log file does not contain the correct success message in the last line.\n"
        f"Last line found: {last_line}"
    )


def test_pipeline_executes_and_transforms_new_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

    with open(EVENTS_PATH, "rb") as f:
        original_events = f.read()
    with open(METRICS_PATH, "rb") as f:
        original_metrics = f.read()

    rng = random.SystemRandom()
    base = datetime(2021, 1, 1, tzinfo=timezone.utc) + timedelta(
        days=rng.randrange(0, 1200), minutes=rng.randrange(0, 1440)
    )
    base = base.replace(second=0, microsecond=0)
    next_minute = base + timedelta(minutes=1)
    missing_minute = base + timedelta(minutes=4)
    ids = [str(rng.randrange(10000, 99999)) for _ in range(4)]
    cpu_base = rng.randrange(1, 50)
    ram_base = rng.randrange(10, 70)

    event_rows = [
        [ids[0], (base + timedelta(seconds=58)).isoformat().replace("+00:00", "Z"), "!!!ALPHA-beta, Ready"],
        [ids[1], (next_minute + timedelta(seconds=3)).isoformat().replace("+00:00", "Z"), "  42_Start? now"],
        [ids[2], (next_minute + timedelta(seconds=17)).astimezone(timezone(timedelta(hours=2))).isoformat(), "...Deploy!!! new"],
        [ids[3], (missing_minute + timedelta(seconds=29)).isoformat().replace("+00:00", "Z"), "No-Metrics here"],
    ]
    metric_rows = [
        [str(int((base + timedelta(seconds=5)).timestamp())), str(cpu_base + 0.2), str(ram_base + 0.1)],
        [str(int((base + timedelta(seconds=45)).timestamp())), str(cpu_base + 2.4), str(ram_base + 4.1)],
        [str(int((next_minute + timedelta(seconds=20)).timestamp())), str(cpu_base + 7.0), str(ram_base + 8.0)],
    ]

    try:
        with open(EVENTS_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["event_id", "timestamp", "raw_description"])
            writer.writerows(event_rows)
        with open(METRICS_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["unix_time", "cpu_load", "ram_usage"])
            writer.writerows(metric_rows)

        log_before = b""
        if os.path.exists(LOG_PATH):
            with open(LOG_PATH, "rb") as f:
                log_before = f.read()

        started = datetime.now()
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=60,
        )
        finished = datetime.now()
        assert result.returncode == 0, (
            "Executing process_logs.py as user failed.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.isfile(OUTPUT_PATH), "The executed pipeline did not create merged_data.csv."
        with open(OUTPUT_PATH, newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == [
                "minute_timestamp", "event_id", "action_token", "avg_cpu", "avg_ram"
            ]
            rows = list(reader)

        assert len(rows) == 4
        expected_minutes = [
            base.strftime("%Y-%m-%d %H:%M:00"),
            next_minute.strftime("%Y-%m-%d %H:%M:00"),
            next_minute.strftime("%Y-%m-%d %H:%M:00"),
            missing_minute.strftime("%Y-%m-%d %H:%M:00"),
        ]
        expected_tokens = ["alphabeta", "42start", "deploy", "nometrics"]
        for i, row in enumerate(rows):
            assert row["minute_timestamp"] == expected_minutes[i]
            assert row["event_id"] == ids[i]
            assert row["action_token"] == expected_tokens[i]

        for row in rows[:1]:
            assert float(row["avg_cpu"]) == pytest.approx(cpu_base + 1.3)
            assert float(row["avg_ram"]) == pytest.approx(ram_base + 2.1)
        for row in rows[1:3]:
            assert float(row["avg_cpu"]) == pytest.approx(cpu_base + 7.0)
            assert float(row["avg_ram"]) == pytest.approx(ram_base + 8.0)
        assert rows[3]["avg_cpu"] == ""
        assert rows[3]["avg_ram"] == ""

        with open(LOG_PATH, "rb") as f:
            log_after = f.read()
        assert log_after.startswith(log_before), "The run replaced the ETL log instead of appending to it."
        if log_before:
            assert log_before.endswith(b"\n"), "The new log entry was not appended as a separate line."
        appended = log_after[len(log_before):].decode("utf-8")
        match = re.fullmatch(
            r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] SUCCESS: Processed 4 events\n?",
            appended,
        )
        assert match is not None, f"The execution did not append exactly the required success entry: {appended!r}"
        logged_at = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
        assert started - timedelta(seconds=2) <= logged_at <= finished + timedelta(seconds=2), (
            "The success entry does not use the current system time."
        )
    finally:
        with open(EVENTS_PATH, "wb") as f:
            f.write(original_events)
        with open(METRICS_PATH, "wb") as f:
            f.write(original_metrics)

        restore = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert restore.returncode == 0, (
            "The pipeline failed when rerun on the required input files.\n"
            f"stdout:\n{restore.stdout}\nstderr:\n{restore.stderr}"
        )
        with open(OUTPUT_PATH, "r") as f:
            restored_output = f.read().strip()
        assert restored_output == EXPECTED_ORIGINAL.strip()


def test_cron_job_configured():
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"],
            capture_output=True,
            text=True,
            check=True,
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to retrieve crontab for user 'user'. Make sure the cron job is installed.")

    cron_lines = [
        line.strip() for line in crontab_output.split("\n")
        if line.strip() and not line.strip().startswith("#")
    ]

    found_cron = False
    for line in cron_lines:
        if "*/15 * * * *" in line and "process_logs.py" in line:
            found_cron = True
            break
    assert found_cron, (
        "Could not find the expected cron job for user 'user'.\n"
        "Expected schedule: */15 * * * *\n"
        "Expected script: process_logs.py\n"
        f"Current crontab:\n{crontab_output}"
    )

    runnable_cron = False
    for line in cron_lines:
        match = re.match(r"^\*/15\s+\*\s+\*\s+\*\s+\*\s+(.+)$", line)
        if not match:
            continue
        try:
            command_tokens = shlex.split(match.group(1), comments=True)
        except ValueError:
            continue
        if SCRIPT_PATH in command_tokens:
            runnable_cron = True
            break
    assert runnable_cron, (
        "The cron entry must use the exact */15 * * * * schedule and run "
        f"{SCRIPT_PATH}.\nCurrent crontab:\n{crontab_output}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
