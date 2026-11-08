#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import calendar
import os
import random
import re
import subprocess
import time
from datetime import datetime, timezone

SCRIPT_PATH = "/home/user/run_etl.sh"
APP_PATH = "/home/user/raw/app.log"
SEC_PATH = "/home/user/raw/sec.log"
CSV_PATH = "/home/user/processed/alerts.csv"
LOG_PATH = "/home/user/etl.log"
LAST_RUN_WINDOW = None


def run_script():
    env = os.environ.copy()
    env["TZ"] = "UTC"
    started = int(time.time())
    result = subprocess.run(
        ["bash", SCRIPT_PATH], capture_output=True, text=True, env=env
    )
    finished = int(time.time())
    assert result.returncode == 0, (
        f"Script execution failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )
    return started, finished


def assert_current_success_log(expected_count, started, finished):
    assert os.path.isfile(LOG_PATH), f"Pipeline log {LOG_PATH} was not created."
    with open(LOG_PATH, "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) > 0, f"Pipeline log {LOG_PATH} is empty."

    last_line = lines[-1]
    pattern = rf"^\[(\d{{10}})\] SUCCESS: processed {expected_count} alerts$"
    match = re.match(pattern, last_line)
    assert match, (
        "Pipeline log entry does not match expected format or count.\n"
        f"Expected pattern: {pattern}\nGot: {last_line}"
    )
    timestamp = int(match.group(1))
    assert started <= timestamp <= finished, (
        f"Log timestamp {timestamp} is not the current execution time "
        f"({started} through {finished})."
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_etl_pipeline_execution():
    global LAST_RUN_WINDOW
    LAST_RUN_WINDOW = run_script()

    assert os.path.isfile(CSV_PATH), f"Output CSV {CSV_PATH} was not created."
    with open(CSV_PATH, "r") as f:
        csv_content = f.read().strip()

    expected_csv = (
        "epoch,severity,source\n"
        "1697361300,INFO,app\n"
        "1697364270,WARN,sec\n"
        "1697364300,ERROR,app\n"
        "1697364360,CRIT,sec\n"
        "1697364435,FATAL,app"
    )
    assert csv_content == expected_csv, (
        "CSV content does not match expected output.\n"
        f"Expected:\n{expected_csv}\n\nGot:\n{csv_content}"
    )


def test_etl_log_format():
    assert LAST_RUN_WINDOW is not None
    started, finished = LAST_RUN_WINDOW
    assert_current_success_log(5, started, finished)


def test_pipeline_parses_runtime_generated_inputs_and_appends_log():
    rng = random.SystemRandom()
    count = rng.randint(6, 9)
    base = rng.randint(1609459200, 1767225600)
    epochs = rng.sample(range(base, base + 86400), count)
    severities = ["debug", "NOTICE", "warning", "Error", "ALERT", "info", "crit", "fatal", "warn"]

    records = []
    app_lines = []
    sec_lines = []
    for index, epoch in enumerate(epochs):
        source = "app" if index % 2 == 0 else "sec"
        severity = severities[index]
        dt = datetime.fromtimestamp(epoch, timezone.utc)
        if source == "app":
            app_lines.append(
                f"[{dt.strftime('%Y-%m-%d %H:%M:%S')}] {severity}: runtime message {index}"
            )
        else:
            sec_lines.append(
                f"{dt.strftime('%m/%d/%Y %H:%M:%S')} {severity}: runtime message {index}"
            )
        records.append((calendar.timegm(dt.utctimetuple()), severity.upper(), source))

    rng.shuffle(app_lines)
    rng.shuffle(sec_lines)
    with open(APP_PATH, "w") as f:
        f.write("\n".join(app_lines) + "\n")
    with open(SEC_PATH, "w") as f:
        f.write("\n".join(sec_lines) + "\n")

    before_lines = []
    if os.path.exists(LOG_PATH):
        with open(LOG_PATH, "r") as f:
            before_lines = f.read().strip().splitlines()

    started, finished = run_script()

    expected_lines = ["epoch,severity,source"] + [
        f"{epoch},{severity},{source}"
        for epoch, severity, source in sorted(records, key=lambda row: row[0])
    ]
    assert os.path.isfile(CSV_PATH), f"Output CSV {CSV_PATH} was not created."
    with open(CSV_PATH, "r") as f:
        actual_lines = f.read().strip().splitlines()
    assert actual_lines == expected_lines, (
        "CSV did not correctly parse, normalize, merge, and numerically sort "
        "the runtime-generated inputs.\n"
        f"Expected: {expected_lines}\nGot: {actual_lines}"
    )

    with open(LOG_PATH, "r") as f:
        after_lines = f.read().strip().splitlines()
    assert len(after_lines) == len(before_lines) + 1, (
        "The script must append exactly one execution entry to etl.log."
    )
    assert_current_success_log(count, started, finished)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
