#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import stat
import secrets
import subprocess
from datetime import datetime, timedelta
import pytest

SCRIPT_PATH = "/home/user/process_timeseries.sh"
OUTPUT_FILE = "/home/user/data/processed/metrics_summary.csv"
LOG_FILE = "/home/user/logs/pipeline.log"
CRON_FILE = "/home/user/crontab.txt"
RAW_DIR = "/home/user/data/raw"

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

def test_output_file_content():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    with open(OUTPUT_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "2023-10-01,cpu_usage,45.2",
        "2023-10-01,disk_io,10.5",
        "2023-10-02,cpu_usage,55.0",
        "2023-10-02,memory_usage,2048"
    ]

    assert sorted(lines) == sorted(expected_lines), "The content of metrics_summary.csv does not match the expected output."

def test_log_file_content():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist."

    with open(LOG_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines, "Log file is empty."

    last_line = lines[-1]

    # Expected format: [YYYY-MM-DD HH:MM:SS] Pipeline completed. Processed 4 valid records.
    pattern = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Pipeline completed\. Processed 4 valid records\.$"
    assert re.match(pattern, last_line), f"Log entry format is incorrect. Found: {last_line}"

def test_crontab_file():
    assert os.path.isfile(CRON_FILE), f"Crontab file {CRON_FILE} does not exist."

    with open(CRON_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    expected_cron = "0 2 * * * /home/user/process_timeseries.sh"

    found = any(expected_cron in line or re.sub(r'\s+', ' ', line) == expected_cron for line in lines)
    assert found, f"Expected cron expression not found in {CRON_FILE}. Ensure it runs at 2:00 AM daily."

def test_pipeline_executes_on_fresh_dynamic_inputs():
    token = secrets.token_hex(5)
    record_count = 5 + secrets.randbelow(4)
    file_count = 3
    rows_by_file = [[] for _ in range(file_count)]
    expected = []
    base_date = datetime(2024, 2, 3) + timedelta(days=secrets.randbelow(300))

    for i in range(record_count):
        day = base_date + timedelta(days=i)
        date_hyphen = day.strftime("%Y-%m-%d")
        metric = f"MeTrIc_{token.upper()}_{i}"
        value = f"{1000 + secrets.randbelow(8000)}.{secrets.randbelow(10)}"
        if i % 2:
            timestamp = day.strftime("%Y/%m/%d") + f" {10 + i:02d}:15:30"
        else:
            timestamp = date_hyphen + f"T{10 + i:02d}:15:30Z"
        rows_by_file[i % file_count].append(f"{timestamp},{metric},{value},OK")
        expected.append(f"{date_hyphen},{metric.lower()},{value}")

    # These rows must not be emitted because status matching is exact.
    rows_by_file[0].append(f"2025/01/02 01:02:03,SHOULD_NOT_APPEAR_{token},1,WARN")
    rows_by_file[1].append(f"2025-01-03T01:02:03Z,ALSO_NOT_{token},2,ok")
    rows_by_file[2].append("corrupted_line_without_commas")

    os.makedirs(RAW_DIR, exist_ok=True)
    for name in os.listdir(RAW_DIR):
        path = os.path.join(RAW_DIR, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

    for i, rows in enumerate(rows_by_file):
        path = os.path.join(RAW_DIR, f"dynamic_{token}_{i}.csv")
        with open(path, "w") as f:
            f.write("\n".join(rows) + "\n")

    for path in (OUTPUT_FILE, LOG_FILE):
        if os.path.exists(path):
            os.unlink(path)

    started = datetime.now()
    result = subprocess.run(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    finished = datetime.now()
    assert result.returncode == 0, (
        f"Pipeline failed on fresh inputs with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    assert os.path.isfile(OUTPUT_FILE), "Executing the pipeline did not create the summary file."
    with open(OUTPUT_FILE, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert sorted(actual) == sorted(expected), "Pipeline output is incorrect for fresh dynamic inputs."

    assert os.path.isfile(LOG_FILE), "Executing the pipeline did not create the log file."
    with open(LOG_FILE, "r") as f:
        log_lines = [line.strip() for line in f if line.strip()]
    assert len(log_lines) == 1, "A fresh run must append exactly one completion entry to a fresh log."

    match = re.fullmatch(
        rf"\[(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})\] Pipeline completed\. Processed {record_count} valid records\.",
        log_lines[0],
    )
    assert match, f"Dynamic-run log entry is incorrect. Found: {log_lines[0]}"
    logged_time = datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
    assert started - timedelta(seconds=2) <= logged_time <= finished + timedelta(seconds=2), \
        "The completion log timestamp was not generated at execution time."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
