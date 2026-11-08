#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest


def test_analyzer_c_exists():
    assert os.path.isfile("/home/user/analyzer.c"), "/home/user/analyzer.c is missing."


def test_analyzer_executable_exists():
    path = "/home/user/analyzer"
    assert os.path.isfile(path), "/home/user/analyzer executable is missing."
    assert os.access(path, os.X_OK), "/home/user/analyzer is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/analyzer is not a compiled ELF executable."


def test_anomalies_log_content():
    log_path = "/home/user/anomalies.log"
    assert os.path.isfile(log_path), f"{log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_lines = [
        "TIMESTAMP: 1620000360, AVG_TEMP: 82.20, CPU: 10",
        "TIMESTAMP: 1620000420, AVG_TEMP: 87.00, CPU: 10",
        "TIMESTAMP: 1620000480, AVG_TEMP: 90.40, CPU: 5"
    ]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_path}, found {len(content)}."
    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} in {log_path} does not match. Expected '{expected}', got '{actual.strip()}'."


def test_run_pipeline_sh():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "/home/user/analyzer" in content, f"{script_path} does not seem to execute /home/user/analyzer."


def test_crontab_txt():
    cron_path = "/home/user/crontab.txt"
    assert os.path.isfile(cron_path), f"{cron_path} is missing."

    with open(cron_path, "r") as f:
        content = f.read().strip()

    match = re.search(r'^(\*/5|0,5,10,15,20,25,30,35,40,45,50,55)\s+\*\s+\*\s+\*\s+\*\s+(.+)$', content, re.MULTILINE)
    assert match is not None, f"{cron_path} does not contain a valid 5-minute cron schedule."

    command = match.group(2)
    assert "/home/user/run_pipeline.sh" in command, f"Cron command does not execute /home/user/run_pipeline.sh. Found: {command}"


def expanded_expected(rows):
    expanded = []
    for timestamp, temperature, cpu in rows:
        if expanded:
            next_timestamp = expanded[-1][0] + 60
            previous_temperature = expanded[-1][1]
            previous_cpu = expanded[-1][2]
            while next_timestamp < timestamp:
                expanded.append((next_timestamp, previous_temperature, previous_cpu))
                next_timestamp += 60
        expanded.append((timestamp, temperature, cpu))

    result = []
    temperatures = []
    for timestamp, temperature, cpu in expanded:
        temperatures.append(temperature)
        window = temperatures[-5:]
        average = sum(window) / len(window)
        if average > 80.0 and cpu < 50:
            result.append(f"TIMESTAMP: {timestamp}, AVG_TEMP: {average:.2f}, CPU: {cpu}")
    return result


def write_input(rows):
    with open("/home/user/sensor_data.csv", "w") as f:
        for timestamp, temperature, cpu in rows:
            f.write(f"{timestamp},{temperature:.1f},{cpu}\n")


def run_and_check(command, rows):
    marker = "PREEXISTING LOG ENTRY"
    write_input(rows)
    with open("/home/user/anomalies.log", "w") as f:
        f.write(marker + "\n")

    completed = subprocess.run(command, cwd="/home/user", timeout=10,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True)
    assert completed.returncode == 0, (
        f"Command {command!r} failed with status {completed.returncode}. "
        f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )
    assert os.path.isfile("/home/user/anomalies.log"), "Analyzer did not produce anomalies.log."
    with open("/home/user/anomalies.log", "r") as f:
        actual = f.read().splitlines()
    expected = [marker] + expanded_expected(rows)
    assert actual == expected, f"Analyzer output mismatch. Expected {expected!r}, got {actual!r}."


def test_analyzer_and_wrapper_on_changed_inputs():
    sensor_path = "/home/user/sensor_data.csv"
    log_path = "/home/user/anomalies.log"
    original_sensor = open(sensor_path, "rb").read()
    original_log = open(log_path, "rb").read()

    base = 1700000000 + secrets.randbelow(50000) * 60
    bump = secrets.randbelow(4)
    cases = [
        [
            (base, 70.0 + bump, 75),
            (base + 60, 84.0 + bump, 49),
            (base + 180, 86.0 + bump, 20),
            (base + 240, 79.0, 50),
            (base + 420, 95.0 + bump, 10),
            (base + 480, 96.0, 49),
        ],
        [
            (base + 1200, 81.0 + bump, 49),
            (base + 1320, 79.0, 49),
            (base + 1380, 80.0, 50),
            (base + 1560, 92.0 + bump, 15),
            (base + 1620, 60.0, 10),
        ],
    ]

    with tempfile.TemporaryDirectory(prefix="analyzer-check-") as tmpdir:
        rebuilt = os.path.join(tmpdir, "analyzer_from_source")
        compilation = subprocess.run(
            ["gcc", "-std=c11", "-O2", "/home/user/analyzer.c", "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compilation.returncode == 0, (
            "analyzer.c does not compile successfully: " + compilation.stderr
        )
        try:
            run_and_check([rebuilt], cases[0])
            run_and_check(["/home/user/analyzer"], cases[1])
            run_and_check(["/home/user/run_pipeline.sh"], cases[0])
        finally:
            with open(sensor_path, "wb") as f:
                f.write(original_sensor)
            with open(log_path, "wb") as f:
                f.write(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
