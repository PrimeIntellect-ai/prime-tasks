#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/process_logs.sh")
INPUT_FILE = Path("/home/user/incoming/data.csv")
OUTPUT_FILE = Path("/home/user/output/max_memory.csv")
CRON_FILE = Path("/home/user/cron_backup.txt")
CRON_PATTERN = re.compile(r"^0\s+\*\s+\*\s+\*\s+\*\s+/home/user/process_logs\.sh\b", re.MULTILINE)


def test_script_exists_and_executable():
    """Verify that the process_logs.sh script exists and is executable."""
    script_path = str(SCRIPT_PATH)
    assert os.path.exists(script_path), f"Script missing: {script_path}"
    assert os.path.isfile(script_path), f"Path is not a file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    first_line = SCRIPT_PATH.read_text(errors="replace").splitlines()[0]
    assert re.match(r"^#!(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+(?:-S\s+)?bash)\s*$", first_line), \
        "process_logs.sh must be a Bash script with a Bash shebang"


def test_output_csv_content():
    """Verify that the output CSV file is correctly formatted and aggregated."""
    output_file = str(OUTPUT_FILE)
    assert os.path.exists(output_file), f"Output file missing: {output_file}"
    assert os.path.isfile(output_file), f"Path is not a file: {output_file}"

    expected_content = (
        "hour,hostname,max_value\n"
        "2023-10-12 08:00:00,server-a,2048\n"
        "2023-10-12 08:00:00,server-b,512\n"
        "2023-10-12 09:00:00,server-a,4096\n"
        "2023-10-12 09:00:00,server-b,8192\n"
    )

    with open(output_file, "r") as f:
        actual_content = f.read()

    # Normalize newlines and strip trailing whitespace
    actual_lines = [line.strip() for line in actual_content.strip().splitlines()]
    expected_lines = [line.strip() for line in expected_content.strip().splitlines()]

    assert actual_lines == expected_lines, "Output CSV content does not match expected aggregated data."


def test_cron_backup():
    """Verify that the cron backup file exists and contains the correct cron job."""
    cron_file = str(CRON_FILE)
    assert os.path.exists(cron_file), f"Cron backup file missing: {cron_file}"
    assert os.path.isfile(cron_file), f"Path is not a file: {cron_file}"

    with open(cron_file, "r") as f:
        cron_content = f.read()

    match = CRON_PATTERN.search(cron_content)
    assert match is not None, f"Cron backup does not contain the correct schedule for /home/user/process_logs.sh at minute 0. Content:\n{cron_content}"


def test_cron_job_is_actually_installed_and_backup_is_current():
    """Reject a fabricated backup that does not correspond to an installed crontab."""
    backup = CRON_FILE.read_text().rstrip("\n")
    installed = []

    # The interactive agent may run as user or as root depending on the harness.
    for username in ("user", "root"):
        result = subprocess.run(
            ["crontab", "-u", username, "-l"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        if result.returncode == 0:
            content = result.stdout.rstrip("\n")
            if CRON_PATTERN.search(content):
                installed.append((username, content))

    assert installed, "The required hourly job is not installed in the user or root crontab"
    assert any(content == backup for _, content in installed), \
        "cron_backup.txt is not a dump of the installed crontab containing the required job"


def test_script_executes_correctly_on_changed_multiline_input():
    """Run the submitted artifact on fresh data and derive the expected aggregation."""
    token = secrets.token_hex(4)
    host_a = f"node-a-{token}"
    host_b = f"node-b-{token}"
    host_c = f"node-c-{token}"
    base = secrets.randbelow(50000) + 1000

    rows = [
        ["2041-07-03 11:59:59", host_b, "memory_leak_bytes", str(base + 7), "trace line 1\ntrace line 2\ntrace line 3"],
        ["2041-07-03 10:45:10", host_a, "memory_leak_bytes", str(base + 90), "contains, a comma\nand a newline"],
        ["2041-07-03 10:01:02", host_a, "memory_leak_bytes", str(base + 5), "lower value"],
        ["2041-07-03 10:30:00", host_b, "memory_leak_bytes", str(base + 20), "first\nsecond"],
        ["2041-07-03 10:55:00", host_b, "memory_leak_bytes", str(base + 70), "new maximum"],
        ["2041-07-02 23:59:58", host_c, "memory_leak_bytes", str(base + 2), "previous day\nstack frame"],
        ["2041-07-03 09:00:00", host_a, "memory_leak_byte", str(base + 9999), "near-match must be ignored"],
        ["2041-07-03 10:59:59", host_c, "cpu_usage", str(base + 8888), "other metric\nignored"],
    ]

    input_before = INPUT_FILE.read_bytes()
    output_existed = OUTPUT_FILE.exists()
    output_before = OUTPUT_FILE.read_bytes() if output_existed else None

    try:
        with INPUT_FILE.open("w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "hostname", "metric_name", "value", "message"])
            writer.writerows(rows)

        result = subprocess.run(
            [str(SCRIPT_PATH)],
            cwd="/tmp",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, \
            f"process_logs.sh failed with exit code {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert OUTPUT_FILE.exists() and OUTPUT_FILE.is_file(), \
            "Running process_logs.sh did not create /home/user/output/max_memory.csv"

        aggregates = {}
        for timestamp, hostname, metric_name, value, _message in rows:
            if metric_name != "memory_leak_bytes":
                continue
            hour = timestamp[:13] + ":00:00"
            key = (hour, hostname)
            aggregates[key] = max(aggregates.get(key, int(value)), int(value))

        expected_lines = ["hour,hostname,max_value"]
        expected_lines.extend(
            f"{hour},{hostname},{aggregates[(hour, hostname)]}"
            for hour, hostname in sorted(aggregates)
        )

        actual = OUTPUT_FILE.read_text()
        actual_lines = actual.strip().splitlines()
        assert actual_lines == expected_lines, \
            f"Unexpected output for changed multiline input. Expected {expected_lines!r}, got {actual_lines!r}"
        assert '"' not in actual, "Output fields must be comma-separated without quotes"
        assert all(line.count(",") == 2 for line in actual_lines), "Each output row must contain exactly three fields"
    finally:
        INPUT_FILE.write_bytes(input_before)
        if output_existed:
            OUTPUT_FILE.write_bytes(output_before)
        elif OUTPUT_FILE.exists():
            OUTPUT_FILE.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
