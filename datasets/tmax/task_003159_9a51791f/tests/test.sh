#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import subprocess
import tempfile

import pytest

PIPELINE_DIR = "/home/user/pipeline"
SCRIPT_PATH = os.path.join(PIPELINE_DIR, "run_job.sh")
SOURCE_PATH = os.path.join(PIPELINE_DIR, "process_sensor.c")
EXECUTABLE_PATH = os.path.join(PIPELINE_DIR, "process_sensor")
LOG_PATH = os.path.join(PIPELINE_DIR, "results.log")
RAW_PATH = "/home/user/data/raw_sensor.csv"


def run_checked(command, cwd=None):
    result = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with return code {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result


def read_single_result(expected):
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created."
    with open(LOG_PATH, "r", encoding="utf-8") as handle:
        content = handle.read()
    assert content.strip().splitlines() == [expected], (
        f"Expected exactly one result line {expected!r}; got:\n{content}"
    )


def write_random_csv(path):
    rng = random.SystemRandom()
    while True:
        count = rng.randint(7, 13)
        temps = [45, 46]
        temps.extend(rng.randint(-20, 80) for _ in range(count - 2))
        rng.shuffle(temps)
        remainder = (sum(temps) * 100) % count
        if remainder * 2 != count:
            break

    rows = []
    for index, temp in enumerate(temps):
        if index % 3 == 0:
            note = f"sensor note {rng.randrange(10**9)}\ncontinued on another line"
        elif index % 3 == 1:
            note = f"ordinary note {rng.randrange(10**9)}"
        else:
            note = f"three-line note\nvalue {rng.randrange(10**9)}\nfinished"
        rows.append([
            str(rng.randrange(1000, 999999)),
            f"2026-08-{index + 1:02d} 12:34",
            f"{temp}.0",
            f"{rng.randrange(10, 95)}.0",
            note,
        ])

    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["id", "timestamp", "temp", "humidity", "notes"])
        writer.writerows(rows)

    expected = (
        f"Records: {count}, AvgTemp: {sum(temps) / count:.2f}, "
        f"Anomalies: {sum(temp > 45 for temp in temps)}"
    )
    return expected


def test_run_job_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_c_program_exists():
    assert os.path.isfile(SOURCE_PATH), f"C source file {SOURCE_PATH} does not exist."


def test_c_source_compiles_and_processes_unseen_csv_files():
    binary = os.path.join(tempfile.mkdtemp(prefix="sensor-verifier-"), "process_sensor")
    run_checked(["/usr/bin/gcc", SOURCE_PATH, "-o", binary])
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)
    with open(binary, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Compiled processor is not an ELF executable."

    for _ in range(3):
        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as handle:
            csv_path = handle.name
        try:
            expected = write_random_csv(csv_path)
            if os.path.exists(LOG_PATH):
                os.remove(LOG_PATH)
            run_checked([binary, csv_path], cwd=PIPELINE_DIR)
            read_single_result(expected)
        finally:
            if os.path.exists(csv_path):
                os.remove(csv_path)


def test_pipeline_execution_and_results():
    original_raw = tempfile.NamedTemporaryFile(delete=False)
    original_raw.close()
    shutil.copyfile(RAW_PATH, original_raw.name)

    try:
        # Retain the original fixed-input assertion, but remove stale artifacts first.
        for path in (LOG_PATH, EXECUTABLE_PATH):
            if os.path.exists(path):
                os.remove(path)
        run_checked([SCRIPT_PATH], cwd=PIPELINE_DIR)
        assert os.path.isfile(EXECUTABLE_PATH), "run_job.sh did not create process_sensor."
        assert os.access(EXECUTABLE_PATH, os.X_OK), "process_sensor is not executable."
        with open(EXECUTABLE_PATH, "rb") as handle:
            assert handle.read(4) == b"\x7fELF", "run_job.sh did not produce an ELF executable."
        expected_line = "Records: 5, AvgTemp: 31.74, Anomalies: 2"
        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created."
        with open(LOG_PATH, "r", encoding="utf-8") as handle:
            content = handle.read()
        assert expected_line in content, (
            f"Expected output {expected_line!r} not found in {LOG_PATH}. Content:\n{content}"
        )

        # Confirm the automation recompiles and runs against the required raw-data path.
        expected_random = write_random_csv(RAW_PATH)
        os.remove(LOG_PATH)
        os.remove(EXECUTABLE_PATH)
        run_checked([SCRIPT_PATH], cwd=PIPELINE_DIR)
        assert os.path.isfile(EXECUTABLE_PATH), "run_job.sh did not recreate process_sensor."
        with open(EXECUTABLE_PATH, "rb") as handle:
            assert handle.read(4) == b"\x7fELF", "run_job.sh did not compile a native executable."
        read_single_result(expected_random)
    finally:
        shutil.copyfile(original_raw.name, RAW_PATH)
        os.remove(original_raw.name)


def test_cron_job_scheduled():
    result = subprocess.run(
        ["crontab", "-l", "-u", "user"], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, "No crontab found for user 'user'."
    cron_output = result.stdout.strip()
    match = re.search(
        r'^15\s+3\s+\*\s+\*\s+\*\s+.*run_job\.sh', cron_output, re.MULTILINE
    )
    assert match is not None, (
        "Cron job for 3:15 AM running run_job.sh not found in crontab. "
        f"Crontab content:\n{cron_output}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
