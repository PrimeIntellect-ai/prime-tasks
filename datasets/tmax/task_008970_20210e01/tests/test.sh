#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone

import pytest

WORKSPACE = "/home/user/workspace"
DATA_DIR = os.path.join(WORKSPACE, "data")
PROCESSED_DIR = os.path.join(WORKSPACE, "processed")
PYTHON_SCRIPT = os.path.join(WORKSPACE, "process_log.py")
BASH_SCRIPT = os.path.join(WORKSPACE, "run_pipeline.sh")
FINAL_CSV = os.path.join(WORKSPACE, "final_series.csv")


def run_as_user(command, timeout=30):
    result = subprocess.run(
        ["runuser", "-u", "user", "--"] + command,
        cwd=WORKSPACE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, result.stdout
    return result


def clear_directory(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        item = os.path.join(path, name)
        if os.path.isdir(item) and not os.path.islink(item):
            shutil.rmtree(item)
        else:
            os.unlink(item)


def write_broken_jsonl(path, records):
    with open(path, "w", encoding="utf-8") as handle:
        for timestamp, value, message in records:
            handle.write(
                '{"timestamp": "' + timestamp + '", "size_bytes": ' + str(value)
                + ', "message": "' + message + '"}\n'
            )
    os.chmod(path, 0o644)


def read_csv_strict(path):
    with open(path, "r", encoding="utf-8", newline="") as handle:
        rows = list(csv.reader(handle))
    assert rows and rows[0] == ["timestamp", "size_bytes"], f"Incorrect header in {path}: {rows[:1]}"
    for row in rows[1:]:
        assert len(row) == 2, f"Malformed row in {path}: {row}"
    return rows[1:]


def iso_z(value):
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def test_data_copied():
    """Check if the jsonl files were copied to the data directory."""
    expected_files = ["log_A.jsonl", "log_B.jsonl", "log_C.jsonl"]
    for name in expected_files:
        path = os.path.join(DATA_DIR, name)
        assert os.path.isfile(path), f"Expected file {path} was not copied to the data directory."


def test_scripts_exist():
    """Check if the required scripts were created."""
    assert os.path.isfile(PYTHON_SCRIPT), f"Python script {PYTHON_SCRIPT} is missing."
    assert os.path.isfile(BASH_SCRIPT), f"Bash script {BASH_SCRIPT} is missing."


def test_process_log_on_unseen_malformed_input():
    """Execute the submitted parser on a fresh malformed file and verify hourly interpolation and formatting."""
    token = secrets.token_hex(8)
    input_path = os.path.join("/tmp", f"parser_{token}.jsonl")
    output_path = os.path.join(PROCESSED_DIR, f"parser_{token}.csv")
    base = datetime(2024, 1, 1, tzinfo=timezone.utc) + timedelta(days=secrets.randbelow(300))
    start = 700 + secrets.randbelow(5000)
    step = 7 + secrets.randbelow(90)
    slash = chr(92)

    write_broken_jsonl(input_path, [
        (iso_z(base), start, "bad " + slash + "uZZZZ value"),
        (iso_z(base + timedelta(hours=3)), start + 3 * step, "short " + slash + "u12"),
    ])
    if os.path.exists(output_path):
        os.unlink(output_path)

    try:
        run_as_user(["python3", PYTHON_SCRIPT, input_path])
        assert os.path.isfile(output_path), "process_log.py did not create the required same-basename CSV"
        expected = [
            [iso_z(base + timedelta(hours=i)), f"{start + i * step:.1f}"]
            for i in range(4)
        ]
        assert read_csv_strict(output_path) == expected
    finally:
        if os.path.exists(input_path):
            os.unlink(input_path)
        if os.path.exists(output_path):
            os.unlink(output_path)


def test_pipeline_executes_parser_in_parallel_and_merges_unseen_inputs():
    """Run the submitted DAG on generated files, require overlapping parser jobs, then rerun it on the task inputs."""
    backup_root = tempfile.mkdtemp(prefix="pipeline_backup_")
    backup_data = os.path.join(backup_root, "data")
    shutil.copytree(DATA_DIR, backup_data)
    real_script = PYTHON_SCRIPT + ".verifier_real"
    event_log = os.path.join(backup_root, "events.jsonl")
    open(event_log, "w").close()
    os.chmod(event_log, 0o666)

    token = secrets.token_hex(6)
    names = [f"fleet_{token}_{i}.jsonl" for i in range(3)]
    base = datetime(2025, 1, 1, tzinfo=timezone.utc) + timedelta(days=secrets.randbelow(200))
    offset = secrets.randbelow(400)
    slash = chr(92)
    expected_rows = []

    generated = [
        (names[0], base + timedelta(hours=8), 1000 + offset, 25, 2),
        (names[1], base, 2000 + offset, 40, 3),
        (names[2], base + timedelta(hours=5), 3000 + offset, 15, 2),
    ]

    try:
        clear_directory(DATA_DIR)
        clear_directory(PROCESSED_DIR)
        if os.path.exists(FINAL_CSV):
            os.unlink(FINAL_CSV)

        for name, start_time, start_value, step, gap in generated:
            write_broken_jsonl(os.path.join(DATA_DIR, name), [
                (iso_z(start_time), start_value, "broken " + slash + "uQ123"),
                (iso_z(start_time + timedelta(hours=gap)), start_value + gap * step, "tail " + slash + "u0"),
            ])
            for hour in range(gap + 1):
                expected_rows.append([
                    iso_z(start_time + timedelta(hours=hour)),
                    f"{start_value + hour * step:.1f}",
                ])
        expected_rows.sort(key=lambda row: row[0])

        os.rename(PYTHON_SCRIPT, real_script)
        wrapper = f'''#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time

LOG = {event_log!r}
REAL = {real_script!r}
name = os.path.basename(sys.argv[-1]) if len(sys.argv) > 1 else ""

def emit(kind):
    record = json.dumps({{"kind": kind, "name": name, "time": time.time(), "pid": os.getpid()}}) + "\\n"
    fd = os.open(LOG, os.O_WRONLY | os.O_APPEND)
    try:
        os.write(fd, record.encode("utf-8"))
    finally:
        os.close(fd)

emit("start")
time.sleep(1.2)
try:
    code = subprocess.call([sys.executable, REAL] + sys.argv[1:])
finally:
    emit("end")
sys.exit(code)
'''
        with open(PYTHON_SCRIPT, "w", encoding="utf-8") as handle:
            handle.write(wrapper)
        os.chmod(PYTHON_SCRIPT, 0o755)

        run_as_user(["bash", BASH_SCRIPT], timeout=40)

        assert os.path.isfile(FINAL_CSV), "run_pipeline.sh did not create final_series.csv"
        assert read_csv_strict(FINAL_CSV) == expected_rows
        for name in names:
            output = os.path.join(PROCESSED_DIR, os.path.splitext(name)[0] + ".csv")
            assert os.path.isfile(output), f"Pipeline did not create intermediate output {output}"

        with open(event_log, "r", encoding="utf-8") as handle:
            events = [json.loads(line) for line in handle if line.strip()]
        starts = {event["name"]: event["time"] for event in events if event["kind"] == "start" and event["name"] in names}
        ends = {event["name"]: event["time"] for event in events if event["kind"] == "end" and event["name"] in names}
        assert set(starts) == set(names), "run_pipeline.sh did not execute process_log.py for every JSONL input"
        assert set(ends) == set(names), "run_pipeline.sh did not wait for every process_log.py job"
        assert max(starts.values()) < min(ends.values()), "process_log.py jobs did not overlap; inputs were not processed in parallel"
    finally:
        if os.path.exists(PYTHON_SCRIPT):
            os.unlink(PYTHON_SCRIPT)
        if os.path.exists(real_script):
            os.rename(real_script, PYTHON_SCRIPT)
        clear_directory(DATA_DIR)
        for name in os.listdir(backup_data):
            shutil.copy2(os.path.join(backup_data, name), os.path.join(DATA_DIR, name))
        clear_directory(PROCESSED_DIR)
        if os.path.exists(FINAL_CSV):
            os.unlink(FINAL_CSV)
        shutil.rmtree(backup_root, ignore_errors=True)

    # Execute the restored submitted artifacts on the original task data so the
    # original intermediate-file and exact-result assertions below test a fresh run.
    run_as_user(["bash", BASH_SCRIPT], timeout=40)


def test_processed_files_exist():
    """Check if intermediate processed CSV files exist."""
    expected_files = ["log_A.csv", "log_B.csv", "log_C.csv"]
    for name in expected_files:
        path = os.path.join(PROCESSED_DIR, name)
        assert os.path.isfile(path), f"Processed intermediate file {path} is missing."


def test_final_series_csv():
    """Check if the final merged and interpolated CSV is correct."""
    assert os.path.isfile(FINAL_CSV), f"Final output file {FINAL_CSV} is missing."

    expected_data = [
        ("2023-11-01T00:00:00Z", 1000.0),
        ("2023-11-01T01:00:00Z", 1100.0),
        ("2023-11-01T02:00:00Z", 1200.0),
        ("2023-11-01T03:00:00Z", 1300.0),
        ("2023-11-01T04:00:00Z", 1400.0),
        ("2023-11-02T00:00:00Z", 2000.0),
        ("2023-11-02T01:00:00Z", 2250.0),
        ("2023-11-02T02:00:00Z", 2500.0),
        ("2023-11-03T10:00:00Z", 5000.0),
        ("2023-11-03T11:00:00Z", 5050.0),
        ("2023-11-03T12:00:00Z", 5100.0),
    ]

    actual_data = []
    with open(FINAL_CSV, "r", encoding="utf-8") as handle:
        reader = csv.reader(handle)
        header = next(reader, None)
        assert header == ["timestamp", "size_bytes"], f"Incorrect header in {FINAL_CSV}. Got {header}."
        for row in reader:
            assert len(row) == 2, f"Malformed row in {FINAL_CSV}: {row}"
            timestamp, size_bytes_str = row
            try:
                size_bytes = float(size_bytes_str)
            except ValueError:
                pytest.fail(f"Invalid size_bytes value '{size_bytes_str}' in row {row}")
            actual_data.append((timestamp, size_bytes))

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows, but got {len(actual_data)}."
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual[0] == expected[0], f"Row {i+1}: Expected timestamp {expected[0]}, got {actual[0]}."
        assert abs(actual[1] - expected[1]) < 1e-5, f"Row {i+1}: Expected size_bytes {expected[1]}, got {actual[1]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
