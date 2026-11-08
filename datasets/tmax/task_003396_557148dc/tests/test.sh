#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
from collections import defaultdict
from datetime import datetime

import pytest
from jinja2 import Template

RAW_LOG_PATH = "/home/user/raw_etl.log"
TEMPLATE_PATH = "/home/user/report_template.md"
CLEANED_LOGS_PATH = "/home/user/cleaned_logs.jsonl"
BURST_REPORT_PATH = "/home/user/burst_report.md"
LINE_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \| JobID:([^|]+) \| (.*)$")


def normalize(message):
    return "".join(ch for ch in message.lower() if ch.isalnum() or ch == " ").strip()


def expected_logs():
    result = []
    with open(RAW_LOG_PATH, "rb") as f:
        raw_lines = f.readlines()

    for line_number, raw_line in enumerate(raw_lines, 1):
        raw_line = raw_line.rstrip(b"\r\n")
        try:
            decoded = raw_line.decode("utf-8")
        except UnicodeDecodeError:
            decoded = raw_line.decode("iso-8859-1")

        match = LINE_RE.fullmatch(decoded)
        assert match is not None, f"Source line {line_number} has an unexpected format"
        timestamp, job_id, message = match.groups()
        datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
        result.append({
            "timestamp": timestamp,
            "job_id": job_id.strip(),
            "normalized_message": normalize(message),
        })
    return result


def expected_jobs(logs):
    grouped = defaultdict(list)
    for entry in logs:
        grouped[(entry["job_id"], entry["normalized_message"])].append(
            datetime.strptime(entry["timestamp"], "%Y-%m-%d %H:%M:%S")
        )

    maximum_by_job = {}
    for (job_id, _message), timestamps in grouped.items():
        timestamps.sort()
        left = 0
        maximum = 0
        for right, current in enumerate(timestamps):
            while (current - timestamps[left]).total_seconds() > 300:
                left += 1
            maximum = max(maximum, right - left + 1)
        if maximum >= 4:
            maximum_by_job[job_id] = max(maximum_by_job.get(job_id, 0), maximum)

    return [
        {"job_id": job_id, "max_burst_size": maximum}
        for job_id, maximum in sorted(
            maximum_by_job.items(), key=lambda item: (-item[1], item[0])
        )
    ]


def test_cleaned_logs_jsonl():
    assert os.path.isfile(CLEANED_LOGS_PATH), f"File not found: {CLEANED_LOGS_PATH}"

    with open(CLEANED_LOGS_PATH, "r", encoding="utf-8") as f:
        lines = f.readlines()

    assert len(lines) > 0, f"File is empty: {CLEANED_LOGS_PATH}"

    parsed_logs = []
    for i, line in enumerate(lines):
        try:
            log_entry = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {CLEANED_LOGS_PATH} is not valid JSON.")

        assert "timestamp" in log_entry, f"Missing 'timestamp' key in line {i+1}"
        assert "job_id" in log_entry, f"Missing 'job_id' key in line {i+1}"
        assert "normalized_message" in log_entry, f"Missing 'normalized_message' key in line {i+1}"
        parsed_logs.append(log_entry)

    # Preserve the original normalization assertions.
    job200_logs = [log for log in parsed_logs if log["job_id"] == "JOB200"]
    assert len(job200_logs) == 5, "Expected 5 logs for JOB200"
    for log in job200_logs:
        assert log["normalized_message"] == "error connection reset by peer"

    job400_logs = [log for log in parsed_logs if log["job_id"] == "JOB400"]
    assert len(job400_logs) == 4, "Expected 4 logs for JOB400"
    for log in job400_logs:
        assert log["normalized_message"] == "retrying attempt"

    expected = expected_logs()
    assert len(parsed_logs) == len(expected), "Cleaned log must contain exactly one entry per source line"
    assert parsed_logs == expected, "Cleaned log entries, timestamps, ordering, or normalization are incorrect"
    for i, entry in enumerate(parsed_logs, 1):
        assert set(entry) == {"timestamp", "job_id", "normalized_message"}, f"Unexpected keys in line {i}"


def test_burst_report():
    assert os.path.isfile(BURST_REPORT_PATH), f"File not found: {BURST_REPORT_PATH}"

    with open(BURST_REPORT_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original report assertions.
    assert re.search(r"JOB200.*5", content), "Report must contain JOB200 with max burst size of 5"
    assert re.search(r"JOB400.*4", content), "Report must contain JOB400 with max burst size of 4"
    assert "JOB300" not in content, "Report should not contain JOB300 as it did not have a burst"
    assert content.find("JOB200") < content.find("JOB400"), "JOB200 should be listed before JOB400"

    logs = expected_logs()
    jobs = expected_jobs(logs)
    with open(TEMPLATE_PATH, "r", encoding="utf-8") as f:
        expected_report = Template(f.read()).render(jobs=jobs)

    assert content == expected_report, "Report was not correctly rendered from the template and full aggregation"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
