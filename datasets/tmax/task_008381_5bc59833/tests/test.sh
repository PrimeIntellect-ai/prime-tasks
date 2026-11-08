#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
from datetime import datetime, timezone

SCRIPT_PATH = '/home/user/analyze_logs.sh'
REPORT_PATH = '/home/user/anomaly_report.txt'
LOG_A_PATH = '/home/user/logs/server_A.log'
LOG_B_PATH = '/home/user/logs/server_B.log'


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_script_exists_and_executable():
    script_path = '/home/user/analyze_logs.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_runs_and_creates_report():
    run_script()
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist after running the script."


def test_anomaly_report_exists():
    report_path = '/home/user/anomaly_report.txt'
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."


def compute_expected_anomaly():
    log_a_path = '/home/user/logs/server_A.log'
    log_b_path = '/home/user/logs/server_B.log'

    records = set()

    if os.path.exists(log_a_path):
        with open(log_a_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    records.add(line)

    if os.path.exists(log_b_path):
        with open(log_b_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    parts = line.split(',')
                    if len(parts) == 5:
                        ts, ip, status, resp_time, payload = parts
                        dt = datetime.fromtimestamp(int(ts), timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
                        normalized_line = f"{dt}|{ip}|{status}|{resp_time}|{payload}"
                        records.add(normalized_line)

    minutes_data = {}
    for record in records:
        parts = record.split('|')
        if len(parts) == 5:
            dt, ip, status, resp_time, payload = parts
            minute = dt[:16] # Extract YYYY-MM-DD HH:MM
            status = int(status)
            resp_time = int(resp_time)

            if minute not in minutes_data:
                minutes_data[minute] = {'errors': 0, 'resp_times': []}

            if status >= 500:
                minutes_data[minute]['errors'] += 1
            minutes_data[minute]['resp_times'].append(resp_time)

    sorted_minutes = sorted(minutes_data.keys())
    for minute in sorted_minutes:
        data = minutes_data[minute]
        errors = data['errors']
        avg_time = sum(data['resp_times']) // len(data['resp_times'])

        if errors > 3 and avg_time > 1000:
            return f"ANOMALY_MINUTE: {minute}, ERRORS: {errors}, AVG_TIME: {avg_time}ms"

    return None


def test_anomaly_report_content():
    report_path = '/home/user/anomaly_report.txt'
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, 'r') as f:
        actual_content = f.read().strip()

    expected_content = compute_expected_anomaly()

    assert expected_content is not None, "Could not compute expected anomaly from logs. Logs might be missing or corrupted."
    assert actual_content == expected_content, f"Report content is incorrect.\nExpected: '{expected_content}'\nActual: '{actual_content}'"


def test_script_dynamically_processes_changed_logs():
    with open(LOG_A_PATH, 'rb') as f:
        original_a = f.read()
    with open(LOG_B_PATH, 'rb') as f:
        original_b = f.read()
    original_report = None
    if os.path.exists(REPORT_PATH):
        with open(REPORT_PATH, 'rb') as f:
            original_report = f.read()

    # Use a verifier-generated date and response times so a fixed report cannot pass.
    base_epoch = 1735689600 + secrets.randbelow(180) * 86400
    anomaly_offset = 2 + secrets.randbelow(5)
    jitter = secrets.randbelow(200)
    records = []

    def add(minute_offset, second, status, response_time, index):
        ts = base_epoch + minute_offset * 60 + second
        records.append((ts, f"10.23.{minute_offset}.{index + 1}", status,
                        response_time, f"p{minute_offset:02d}{index:02d}{jitter:03d}"))

    # Earlier normal traffic.
    add(0, 1, 200, 180 + jitter, 0)
    add(0, 12, 500, 220 + jitter, 1)
    add(0, 33, 201, 260 + jitter, 2)
    add(anomaly_offset - 1, 5, 200, 300 + jitter, 0)
    add(anomaly_offset - 1, 25, 502, 350 + jitter, 1)

    # First anomaly: four errors split across both input formats, plus normal requests.
    anomaly_statuses = [500, 200, 502, 503, 201, 500]
    for i, status in enumerate(anomaly_statuses):
        add(anomaly_offset, 3 + i * 8, status, 1120 + jitter + i * 31, i)

    # A later anomaly ensures chronological selection is also exercised.
    for i in range(5):
        add(anomaly_offset + 3, 2 + i * 10, 500 + (i % 2) * 2,
            1300 + jitter + i * 20, i)

    a_records = records[::2]
    b_records = records[1::2]
    # Add exact cross-format duplicates; correct deduplication must count each once.
    b_records.extend([records[0], records[len(records) // 2]])

    def format_a(record):
        ts, ip, status, response_time, payload = record
        dt = datetime.fromtimestamp(ts, timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
        return f"{dt}|{ip}|{status}|{response_time}|{payload}\n"

    def format_b(record):
        ts, ip, status, response_time, payload = record
        return f"{ts},{ip},{status},{response_time},{payload}\n"

    try:
        with open(LOG_A_PATH, 'w') as f:
            f.writelines(format_a(record) for record in a_records)
        with open(LOG_B_PATH, 'w') as f:
            f.writelines(format_b(record) for record in b_records)

        expected_content = compute_expected_anomaly()
        assert expected_content is not None, "Verifier-generated logs did not contain an anomaly."

        run_script()
        assert os.path.isfile(REPORT_PATH), "Script did not create the report for changed logs."
        with open(REPORT_PATH, 'r') as f:
            actual_content = f.read().strip()
        assert actual_content == expected_content, (
            "Script did not dynamically process the changed logs.\n"
            f"Expected: '{expected_content}'\nActual: '{actual_content}'"
        )
    finally:
        with open(LOG_A_PATH, 'wb') as f:
            f.write(original_a)
        with open(LOG_B_PATH, 'wb') as f:
            f.write(original_b)
        if original_report is None:
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
        else:
            with open(REPORT_PATH, 'wb') as f:
                f.write(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
