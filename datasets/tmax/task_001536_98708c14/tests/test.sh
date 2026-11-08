#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import random
import re
import secrets
import subprocess
from datetime import datetime, timezone, timedelta

SCRIPT_PATH = "/home/user/process_logs.py"
INPUT_PATH = "/home/user/input_logs.csv"
OUTPUT_PATH = "/home/user/cleaned_logs.csv"
LOG_PATH = "/home/user/pipeline.log"
HEADERS = ["timestamp", "ip_address", "method", "endpoint", "user_agent"]

ORIGINAL_INPUT = """timestamp,ip_address,method,endpoint,user_agent
2023-10-01T10:00:00Z,192.168.1.5,get,/api/v1/data,Mozilla/5.0
2023-10-01T10:05:00Z,192.168.1.5,GET,/api/v1/data,Mozilla/5.0
2023-10-01T10:10:00Z,10.0.0.15,post,/api/v1/login,curl/7.68.0
2023-10-01T09:55:00Z,192.168.1.100,GeT,/api/v1/data,Mozilla/5.0
2023-10-01T10:15:00Z,172.16.254.1,OPTIONS,/api/v1/data,PostmanRuntime/7.28.4
"""

EXPECTED_ORIGINAL = """timestamp,ip_address,method,endpoint,user_agent
2023-10-01T09:55:00Z,192.168.X.X,GET,/api/v1/data,Mozilla/5.0
2023-10-01T10:10:00Z,10.0.X.X,POST,/api/v1/login,curl/7.68.0
2023-10-01T10:15:00Z,172.16.X.X,OPTIONS,/api/v1/data,PostmanRuntime/7.28.4"""


def test_crontab_configuration():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab. Has it been set?"

    crontab_content = result.stdout.strip()
    expected_pattern = r"^0\s+\*\s+\*\s+\*\s+\*\s+/usr/bin/env\s+python3\s+/home/user/process_logs\.py$"
    match_found = any(re.match(expected_pattern, line.strip()) for line in crontab_content.splitlines())
    assert match_found, "Crontab does not contain the correct scheduling for /home/user/process_logs.py"


def write_rows(rows):
    with open(INPUT_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=HEADERS)
        writer.writeheader()
        writer.writerows(rows)


def expected_rows(rows):
    selected = {}
    for row in rows:
        parts = row["ip_address"].split(".")
        masked_ip = f"{parts[0]}.{parts[1]}.X.X"
        method = row["method"].upper()
        combined = f'{masked_ip}|{method}|{row["endpoint"]}|{row["user_agent"]}'
        digest = hashlib.sha256(combined.encode("utf-8")).hexdigest()
        transformed = {
            "timestamp": row["timestamp"],
            "ip_address": masked_ip,
            "method": method,
            "endpoint": row["endpoint"],
            "user_agent": row["user_agent"],
        }
        if digest not in selected or transformed["timestamp"] < selected[digest]["timestamp"]:
            selected[digest] = transformed
    return sorted(selected.values(), key=lambda row: row["timestamp"])


def run_and_check_log(original_count, deduplicated_count, fixed_original_pattern=False):
    before = open(LOG_PATH, "rb").read() if os.path.exists(LOG_PATH) else b""
    started = datetime.now(timezone.utc)
    result = subprocess.run(["/usr/bin/env", "python3", SCRIPT_PATH], capture_output=True, text=True)
    finished = datetime.now(timezone.utc)
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"

    assert os.path.isfile(LOG_PATH), f"Pipeline log {LOG_PATH} was not created."
    after = open(LOG_PATH, "rb").read()
    assert after.startswith(before), "The script did not append to pipeline.log; existing content was changed."
    appended = after[len(before):].decode("utf-8")
    appended_lines = appended.splitlines()
    assert len(appended_lines) == 1, f"Expected exactly one appended log line, got {len(appended_lines)}."

    with open(LOG_PATH, "r", encoding="utf-8") as f:
        log_lines = f.read().strip().splitlines()
    assert len(log_lines) > 0, "Pipeline log is empty."
    last_line = log_lines[-1]
    assert last_line == appended_lines[0], "The appended line is not the final pipeline log line."

    if fixed_original_pattern:
        log_pattern = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Processed 5 original rows into 3 deduplicated rows\.$"
    else:
        log_pattern = rf"^\[\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}\] Processed {original_count} original rows into {deduplicated_count} deduplicated rows\.$"
    assert re.match(log_pattern, last_line), f"Pipeline log line format or values incorrect. Got: {last_line}"

    timestamp_text = last_line[1:20]
    logged_at = datetime.strptime(timestamp_text, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    assert started - timedelta(seconds=2) <= logged_at <= finished + timedelta(seconds=2), \
        f"Pipeline timestamp is not the current UTC time: {timestamp_text}"


def test_script_execution_and_output():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    with open(INPUT_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(ORIGINAL_INPUT)
    with open(LOG_PATH, "w", encoding="utf-8") as f:
        f.write("[2000-01-01 00:00:00] Processed 0 original rows into 0 deduplicated rows.\n")

    run_and_check_log(5, 3, fixed_original_pattern=True)

    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        actual_csv = f.read().strip()
    assert actual_csv == EXPECTED_ORIGINAL, f"Content of {OUTPUT_PATH} does not match expected output."

    token = secrets.token_hex(12)
    endpoint_a = f"/generated/{token}/alpha"
    endpoint_b = f"/generated/{token}/beta"
    ua_a = f"Verifier,{token}"
    ua_b = f"Agent/{token}"
    rows = [
        {"timestamp": "2041-06-03T12:40:00Z", "ip_address": "203.44.90.8", "method": "pUt", "endpoint": endpoint_a, "user_agent": ua_a},
        {"timestamp": "2041-06-03T11:05:00Z", "ip_address": "203.44.1.250", "method": "PUT", "endpoint": endpoint_a, "user_agent": ua_a},
        {"timestamp": "2041-06-03T13:15:00Z", "ip_address": "203.44.77.2", "method": "put", "endpoint": endpoint_a, "user_agent": ua_a},
        {"timestamp": "2041-06-03T10:55:00Z", "ip_address": "203.44.2.3", "method": "delete", "endpoint": endpoint_a, "user_agent": ua_a},
        {"timestamp": "2041-06-03T09:30:00Z", "ip_address": "203.44.8.9", "method": "PUT", "endpoint": endpoint_b, "user_agent": ua_a},
        {"timestamp": "2041-06-03T09:35:00Z", "ip_address": "203.44.8.10", "method": "put", "endpoint": endpoint_b, "user_agent": ua_b},
        {"timestamp": "2041-06-03T08:20:00Z", "ip_address": "198.51.100.42", "method": "gEt", "endpoint": endpoint_a, "user_agent": ua_a},
        {"timestamp": "2041-06-03T14:20:00Z", "ip_address": "198.51.7.99", "method": "GET", "endpoint": endpoint_a, "user_agent": ua_a},
    ]
    random.SystemRandom().shuffle(rows)
    expected = expected_rows(rows)
    write_rows(rows)

    run_and_check_log(len(rows), len(expected))

    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADERS, "Output headers or column order are incorrect."
        actual_rows = list(reader)
    assert actual_rows == expected, "Output failed randomized normalization, masking, hash-key deduplication, earliest-row selection, CSV handling, or timestamp sorting."

    with open(INPUT_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(ORIGINAL_INPUT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
