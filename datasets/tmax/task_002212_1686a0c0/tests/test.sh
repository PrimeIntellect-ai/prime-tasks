#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import subprocess
import sys

RAW_LOG = "/home/user/raw_app.log"
CSV_FILE = "/home/user/parsed_metrics.csv"
AGGREGATOR = "/home/user/aggregator.py"
JSON_FILE = "/home/user/dashboard_summary.json"
LOG_FILE = "/home/user/dashboard.log"


def expected_csv_lines():
    lines = []
    with open(RAW_LOG, "r") as f:
        for line in f:
            if "[METRIC]" in line:
                parts = line.strip().split()
                timestamp = parts[0]
                endpoint = parts[2].split("=", 1)[1]
                latency = parts[3].split("=", 1)[1].replace("ms", "")
                status = parts[4].split("=", 1)[1]
                lines.append(f"{timestamp},{endpoint},{latency},{status}")
    return lines


def expected_p90_from_csv():
    latencies = {}
    with open(CSV_FILE, "r") as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(",")
            assert len(parts) == 4, f"Invalid CSV format: {line}"
            endpoint = parts[1]
            latency = int(parts[2])
            latencies.setdefault(endpoint, []).append(latency)

    result = {}
    for endpoint, values in latencies.items():
        values = sorted(values)
        result[endpoint] = values[math.ceil(0.9 * len(values)) - 1]
    return result


def read_logs_in_chronological_order():
    # RotatingFileHandler keeps the oldest available chunk in the highest
    # numbered backup and the newest chunk in the unnumbered file.
    paths = [
        f"{LOG_FILE}.3",
        f"{LOG_FILE}.2",
        f"{LOG_FILE}.1",
        LOG_FILE,
    ]
    lines = []
    for path in paths:
        if os.path.exists(path):
            with open(path, "r") as f:
                lines.extend(line.strip() for line in f if line.strip())
    return lines


def test_parsed_metrics_csv():
    assert os.path.exists(RAW_LOG), f"{RAW_LOG} is missing."
    assert os.path.exists(CSV_FILE), f"Expected extracted CSV at {CSV_FILE} does not exist."

    expected_lines = expected_csv_lines()
    with open(CSV_FILE, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in CSV, got {len(actual_lines)}."
    )
    assert actual_lines == expected_lines, (
        "CSV contents do not match the expected extraction from raw_app.log."
    )


def test_p90_json_summary():
    assert os.path.exists(CSV_FILE), f"{CSV_FILE} must exist."
    assert os.path.exists(JSON_FILE), f"Expected JSON summary at {JSON_FILE} does not exist."

    expected_p90 = expected_p90_from_csv()
    with open(JSON_FILE, "r") as f:
        try:
            actual_p90 = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{JSON_FILE} is not valid JSON."

    assert actual_p90 == expected_p90, (
        f"JSON summary P90 values do not match expected. "
        f"Expected {expected_p90}, got {actual_p90}."
    )


def test_rotating_log_files():
    assert os.path.exists(LOG_FILE), f"Expected log file {LOG_FILE} does not exist."

    with open(JSON_FILE, "r") as f:
        actual_p90 = json.load(f)

    expected_log_lines = [
        f"Endpoint {endpoint} P90: {actual_p90[endpoint]}ms"
        for endpoint in sorted(actual_p90)
    ]
    actual_log_lines = read_logs_in_chronological_order()

    assert actual_log_lines == expected_log_lines, (
        "Log lines across log files do not match expected format or chronological "
        f"order. Expected {expected_log_lines}, got {actual_log_lines}."
    )


def test_aggregator_exists_and_uses_required_handler():
    assert os.path.isfile(AGGREGATOR), f"Expected Python script at {AGGREGATOR}."

    # Remove prior outputs so this execution cannot pass by reusing stale files.
    for path in glob.glob(f"{LOG_FILE}*"):
        os.remove(path)
    if os.path.exists(JSON_FILE):
        os.remove(JSON_FILE)

    runner = "/tmp/run_instrumented_aggregator.py"
    report = "/tmp/aggregator_handler_report.json"
    with open(runner, "w") as f:
        f.write(r'''import json
import logging.handlers
import os
import runpy

report_path = "/tmp/aggregator_handler_report.json"
original = logging.handlers.RotatingFileHandler
instances = []

class RecordingRotatingFileHandler(original):
    def __init__(self, *args, **kwargs):
        self.seen_messages = []
        self.seen_levels = []
        super().__init__(*args, **kwargs)
        instances.append(self)

    def emit(self, record):
        self.seen_messages.append(record.getMessage())
        self.seen_levels.append(record.levelno)
        return super().emit(record)

logging.handlers.RotatingFileHandler = RecordingRotatingFileHandler
runpy.run_path("/home/user/aggregator.py", run_name="__main__")

records = []
for handler in instances:
    records.append({
        "filename": os.path.abspath(handler.baseFilename),
        "maxBytes": handler.maxBytes,
        "backupCount": handler.backupCount,
        "format": handler.formatter._fmt if handler.formatter else None,
        "messages": handler.seen_messages,
        "levels": handler.seen_levels,
    })
with open(report_path, "w") as out:
    json.dump(records, out)
''')

    completed = subprocess.run(
        [sys.executable, runner],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        "aggregator.py failed when executed:\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(report), "No handler instrumentation report was produced."

    expected_p90 = expected_p90_from_csv()
    expected_messages = [
        f"Endpoint {endpoint} P90: {expected_p90[endpoint]}ms"
        for endpoint in sorted(expected_p90)
    ]

    with open(report, "r") as f:
        handlers = json.load(f)

    matching_handlers = [
        handler for handler in handlers
        if handler["filename"] == LOG_FILE
        and handler["maxBytes"] == 150
        and handler["backupCount"] == 3
        and handler["format"] == "%(message)s"
        and handler["messages"] == expected_messages
        and handler["levels"] == [20] * len(expected_messages)
    ]
    assert matching_handlers, (
        "aggregator.py did not emit the required INFO messages through a "
        "RotatingFileHandler configured with dashboard.log, maxBytes=150, "
        "backupCount=3, and format '%(message)s'."
    )

    assert os.path.exists(JSON_FILE), "aggregator.py did not create dashboard_summary.json."
    with open(JSON_FILE, "r") as f:
        actual_p90 = json.load(f)
    assert actual_p90 == expected_p90, (
        f"Executed aggregator produced incorrect JSON: {actual_p90}."
    )

    assert os.path.exists(LOG_FILE), "aggregator.py did not create dashboard.log."
    actual_messages = read_logs_in_chronological_order()
    assert actual_messages == expected_messages, (
        f"Executed aggregator produced incorrect log lines: {actual_messages}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
