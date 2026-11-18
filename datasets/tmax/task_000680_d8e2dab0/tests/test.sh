#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import re
import stat
import subprocess
from datetime import datetime
from pathlib import Path


def test_grouped_csv_content():
    processed_file = "/home/user/data/processed/grouped.csv"
    assert os.path.isfile(processed_file), f"Processed file {processed_file} does not exist."

    expected_content = (
        "sensor,event_count,avg_value\n"
        "SensorA,2,11.5\n"
        "SensorB,2,150.0\n"
        "SensorC,1,5.0"
    )

    with open(processed_file, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {processed_file} does not match expected grouped output."


def test_run_log_content():
    log_file = "/home/user/logs/run.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"Log file {log_file} is empty."

    pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Processed 5 unique records, dropped 4 duplicates\.$")
    match_found = any(pattern.match(line) for line in lines)
    assert match_found, f"No line in {log_file} matches the expected log format and counts."


def test_schedule_cron_content():
    cron_file = "/home/user/schedule.cron"
    assert os.path.isfile(cron_file), f"Cron schedule file {cron_file} does not exist."

    with open(cron_file, "r") as f:
        content = f.read().strip().lower()

    pattern = re.compile(r"^0\s+0\s+\*\s+\*\s+(0|7|sun)\s+/usr/bin/python3\s+/home/user/process\.py$")
    assert pattern.match(content), f"Cron entry in {cron_file} is incorrect. Found: {content}"


def test_zz_process_script_on_independent_fixture():
    script = Path("/home/user/process.py")
    raw_file = Path("/home/user/data/raw/sensor_data.csv")
    processed_file = Path("/home/user/data/processed/grouped.csv")
    log_file = Path("/home/user/logs/run.log")

    assert script.exists(), f"Required script {script} does not exist."
    assert stat.S_ISREG(os.lstat(script).st_mode), f"{script} is not a regular file."

    fixture_rows = [
        {"id": "10", "timestamp": "200", "sensor": "Gamma", "value": "10.0"},
        {"id": "11", "timestamp": "200", "sensor": "Gamma", "value": "10.0"},
        {"id": "12", "timestamp": "100", "sensor": "Gamma", "value": "10.00"},
        {"id": "13", "timestamp": "200", "sensor": "Gamma", "value": "20.0"},
        {"id": "14", "timestamp": "201", "sensor": "Gamma", "value": "20.0"},
        {"id": "15", "timestamp": "050", "sensor": "Alpha", "value": "-1.0"},
        {"id": "16", "timestamp": "050", "sensor": "Alpha", "value": "-1.0"},
        {"id": "17", "timestamp": "051", "sensor": "Alpha", "value": "2.0"},
        {"id": "18", "timestamp": "999", "sensor": "Beta", "value": "4.5"},
    ]

    seen = set()
    unique_rows = []
    for row in fixture_rows:
        digest = hashlib.md5(
            f"{row['timestamp']}|{row['sensor']}|{row['value']}".encode()
        ).hexdigest()
        if digest not in seen:
            seen.add(digest)
            unique_rows.append(row)

    grouped = {}
    for row in unique_rows:
        grouped.setdefault(row["sensor"], []).append(float(row["value"]))
    expected_rows = [
        [sensor, str(len(values)), f"{round(sum(values) / len(values), 1):.1f}"]
        for sensor, values in sorted(grouped.items())
    ]
    expected_unique = len(unique_rows)
    expected_dropped = len(fixture_rows) - expected_unique

    def backup(path):
        return path.read_bytes() if path.exists() else None

    def restore(path, data):
        if data is None:
            if path.exists():
                path.unlink()
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    raw_backup = backup(raw_file)
    processed_backup = backup(processed_file)
    log_backup = backup(log_file)

    try:
        raw_file.parent.mkdir(parents=True, exist_ok=True)
        with raw_file.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["id", "timestamp", "sensor", "value"])
            writer.writeheader()
            writer.writerows(fixture_rows)

        if processed_file.exists():
            processed_file.unlink()
        prior_log_lines = log_file.read_text().splitlines() if log_file.exists() else []

        result = subprocess.run(
            ["/usr/bin/python3", str(script)],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Executing {script} failed with status {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )

        assert processed_file.is_file(), "The script did not create grouped.csv."
        with processed_file.open(newline="") as f:
            reader = csv.reader(f)
            actual_csv = list(reader)
        assert actual_csv, "grouped.csv is empty."
        assert actual_csv[0] == ["sensor", "event_count", "avg_value"], "Incorrect grouped.csv columns."
        assert actual_csv[1:] == expected_rows, "The script produced incorrect deduplication or aggregation results."

        assert log_file.is_file(), "The script did not create or append to run.log."
        new_log_lines = log_file.read_text().splitlines()
        assert new_log_lines[:-1] == prior_log_lines, "The script did not append exactly one log entry."
        assert len(new_log_lines) == len(prior_log_lines) + 1, "The script must append one completion log entry."

        pattern = re.compile(
            rf"^\[(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})\] "
            rf"Processed {expected_unique} unique records, dropped {expected_dropped} duplicates\.$"
        )
        match = pattern.fullmatch(new_log_lines[-1])
        assert match, "The appended log entry has incorrect format or dynamically derived counts."
        datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    finally:
        restore(raw_file, raw_backup)
        restore(processed_file, processed_backup)
        restore(log_file, log_backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
