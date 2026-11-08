#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import secrets
import subprocess
from datetime import datetime, timedelta
import pytest

RAW_EVENTS_PATH = "/home/user/raw_events.jsonl"
SCRIPT_PATH = "/home/user/process_logs.py"
ANONYMIZED_EVENTS_PATH = "/home/user/anonymized_events.jsonl"
EVENT_VOLUME_PATH = "/home/user/event_volume.csv"
LOC_REPORT_PATH = "/home/user/loc_report.html"
OUTPUT_PATHS = [ANONYMIZED_EVENTS_PATH, EVENT_VOLUME_PATH, LOC_REPORT_PATH]

RUNNER_PATH = "/tmp/run_process_logs_guarded.py"
RUNNER_SOURCE = r'''
import builtins
import io
import os
import runpy
import sys

RAW_PATH = os.path.realpath("/home/user/raw_events.jsonl")
ORIGINAL_OPEN = builtins.open
ORIGINAL_IO_OPEN = io.open

class StreamingReadGuard:
    def __init__(self, wrapped):
        self._wrapped = wrapped

    def read(self, *args, **kwargs):
        raise RuntimeError("raw_events.jsonl must be processed line-by-line; bulk read() is forbidden")

    def readlines(self, *args, **kwargs):
        raise RuntimeError("raw_events.jsonl must be processed line-by-line; readlines() is forbidden")

    def readline(self, *args, **kwargs):
        return self._wrapped.readline(*args, **kwargs)

    def __iter__(self):
        return self

    def __next__(self):
        return next(self._wrapped)

    def __enter__(self):
        self._wrapped.__enter__()
        return self

    def __exit__(self, *args):
        return self._wrapped.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._wrapped, name)

def should_guard(file, mode):
    try:
        path = os.path.realpath(os.fspath(file))
    except (TypeError, ValueError):
        return False
    return path == RAW_PATH and "r" in mode and "+" not in mode

def guarded_builtin_open(file, mode="r", *args, **kwargs):
    handle = ORIGINAL_OPEN(file, mode, *args, **kwargs)
    return StreamingReadGuard(handle) if should_guard(file, mode) else handle

def guarded_io_open(file, mode="r", *args, **kwargs):
    handle = ORIGINAL_IO_OPEN(file, mode, *args, **kwargs)
    return StreamingReadGuard(handle) if should_guard(file, mode) else handle

builtins.open = guarded_builtin_open
io.open = guarded_io_open
sys.argv = ["/home/user/process_logs.py"]
runpy.run_path("/home/user/process_logs.py", run_name="__main__")
'''


def anonymized_copy(event):
    expected = dict(event)
    local, separator, domain = event["user_email"].partition("@")
    assert separator, "Test input email is invalid"
    expected["user_email"] = "***@" + domain
    prefix, separator, last_octet = event["ip_address"].rpartition(".")
    assert separator, "Test input IP is invalid"
    expected["ip_address"] = prefix + ".XXX"
    return expected


def expected_results(events):
    minute_counts = {}
    for event in events:
        ts = datetime.strptime(event["timestamp"], "%Y-%m-%dT%H:%M:%SZ")
        minute = ts.strftime("%Y-%m-%dT%H:%M:00Z")
        minute_counts[minute] = minute_counts.get(minute, 0) + 1

    minute_keys = sorted(minute_counts)
    start_min = datetime.strptime(minute_keys[0], "%Y-%m-%dT%H:%M:00Z")
    end_min = datetime.strptime(minute_keys[-1], "%Y-%m-%dT%H:%M:00Z")
    rows = []
    zero_minutes = 0
    peak_count = 0
    current = start_min
    while current <= end_min:
        minute = current.strftime("%Y-%m-%dT%H:%M:00Z")
        count = minute_counts.get(minute, 0)
        rows.append({"minute": minute, "event_count": str(count)})
        zero_minutes += count == 0
        peak_count = max(peak_count, count)
        current += timedelta(minutes=1)

    report = (
        "<html>\n"
        "<body>\n"
        "<h1>Localization Operations Report</h1>\n"
        f"<p>Total events processed: {len(events)}</p>\n"
        f"<p>Peak events in a single minute: {peak_count}</p>\n"
        f"<p>Minutes with zero events: {zero_minutes}</p>\n"
        "</body>\n"
        "</html>\n"
    )
    return rows, zero_minutes, peak_count, report


def remove_outputs():
    for path in OUTPUT_PATHS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_script_guarded():
    with open(RUNNER_PATH, "w", encoding="utf-8") as runner:
        runner.write(RUNNER_SOURCE)
    result = subprocess.run(
        ["python3", RUNNER_PATH],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "process_logs.py failed when executed or did not stream the raw input.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_outputs_match(events):
    expected_rows, zero_minutes, peak_count, expected_report = expected_results(events)

    assert os.path.exists(ANONYMIZED_EVENTS_PATH), f"File missing: {ANONYMIZED_EVENTS_PATH}"
    with open(ANONYMIZED_EVENTS_PATH, "r", encoding="utf-8") as f:
        actual_events = [json.loads(line) for line in f if line.strip()]
    assert actual_events == [anonymized_copy(event) for event in events], (
        "Anonymized records must correspond in order to the input records, preserve all "
        "non-PII fields, and preserve the email domain and IP prefix."
    )

    assert os.path.exists(EVENT_VOLUME_PATH), f"File missing: {EVENT_VOLUME_PATH}"
    with open(EVENT_VOLUME_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert "minute" in reader.fieldnames and "event_count" in reader.fieldnames, (
            "CSV headers must be 'minute' and 'event_count'"
        )
        actual_rows = list(reader)
    assert actual_rows == expected_rows

    assert os.path.exists(LOC_REPORT_PATH), f"File missing: {LOC_REPORT_PATH}"
    with open(LOC_REPORT_PATH, "r", encoding="utf-8") as f:
        actual_report = f.read()
    assert actual_report == expected_report, "HTML report does not exactly match the required template"


def test_script_exists_executes_and_processes_unseen_input():
    assert os.path.isfile(SCRIPT_PATH), f"Python script missing: {SCRIPT_PATH}"

    with open(RAW_EVENTS_PATH, "rb") as f:
        original_raw = f.read()

    token = secrets.token_hex(8)
    probe_events = [
        {
            "timestamp": "2041-06-07T08:10:59Z",
            "user_email": f"first-{token}@alpha.example",
            "ip_address": "172.16.4.9",
            "event_type": "probe_start",
            "ui_string_id": f"probe_{token}_a",
        },
        {
            "timestamp": "2041-06-07T08:12:01Z",
            "user_email": f"second-{token}@beta.example.org",
            "ip_address": "203.0.113.27",
            "event_type": "probe_middle",
            "ui_string_id": f"probe_{token}_b",
        },
        {
            "timestamp": "2041-06-07T08:12:44Z",
            "user_email": f"third-{token}@gamma.test",
            "ip_address": "10.20.30.40",
            "event_type": "probe_middle_2",
            "ui_string_id": f"probe_{token}_c",
        },
        {
            "timestamp": "2041-06-07T08:14:00Z",
            "user_email": f"fourth-{token}@delta.invalid",
            "ip_address": "192.0.2.254",
            "event_type": "probe_end",
            "ui_string_id": f"probe_{token}_d",
        },
    ]

    try:
        with open(RAW_EVENTS_PATH, "w", encoding="utf-8") as f:
            for event in probe_events:
                f.write(json.dumps(event) + "\n")
        remove_outputs()
        run_script_guarded()
        assert_outputs_match(probe_events)
    finally:
        with open(RAW_EVENTS_PATH, "wb") as f:
            f.write(original_raw)
        remove_outputs()
        run_script_guarded()


@pytest.fixture(scope="module")
def truth_data():
    if not os.path.exists(RAW_EVENTS_PATH):
        pytest.fail(f"Input file {RAW_EVENTS_PATH} is missing.")

    events = []
    with open(RAW_EVENTS_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                events.append(json.loads(line))

    if not events:
        pytest.fail("Input file is empty.")

    total_events = len(events)

    minute_counts = {}
    for e in events:
        ts = datetime.strptime(e["timestamp"], "%Y-%m-%dT%H:%M:%SZ")
        minute_str = ts.strftime("%Y-%m-%dT%H:%M:00Z")
        minute_counts[minute_str] = minute_counts.get(minute_str, 0) + 1

    minutes_sorted = sorted(minute_counts.keys())
    start_min = datetime.strptime(minutes_sorted[0], "%Y-%m-%dT%H:%M:00Z")
    end_min = datetime.strptime(minutes_sorted[-1], "%Y-%m-%dT%H:%M:00Z")

    expected_csv_rows = []
    current_min = start_min
    zero_minutes = 0
    peak_count = 0

    while current_min <= end_min:
        m_str = current_min.strftime("%Y-%m-%dT%H:%M:00Z")
        count = minute_counts.get(m_str, 0)
        expected_csv_rows.append({"minute": m_str, "event_count": str(count)})
        if count == 0:
            zero_minutes += 1
        if count > peak_count:
            peak_count = count
        current_min += timedelta(minutes=1)

    return {
        "events": events,
        "total_events": total_events,
        "expected_csv_rows": expected_csv_rows,
        "zero_minutes": zero_minutes,
        "peak_count": peak_count,
    }


def test_anonymized_events_file(truth_data):
    assert os.path.exists(ANONYMIZED_EVENTS_PATH), f"File missing: {ANONYMIZED_EVENTS_PATH}"

    count = 0
    actual_events = []
    with open(ANONYMIZED_EVENTS_PATH, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            count += 1
            data = json.loads(line)
            actual_events.append(data)

            email = data.get("user_email", "")
            assert email.startswith("***@"), f"Email not anonymized correctly: {email}"

            ip = data.get("ip_address", "")
            assert ip.endswith(".XXX"), f"IP address not anonymized correctly: {ip}"

    assert count == truth_data["total_events"], f"Expected {truth_data['total_events']} anonymized events, found {count}"
    expected_events = [anonymized_copy(event) for event in truth_data["events"]]
    assert actual_events == expected_events, (
        "Anonymized records must correspond in order to the input and preserve timestamps, "
        "email domains, IP prefixes, and all other fields."
    )


def test_event_volume_csv(truth_data):
    assert os.path.exists(EVENT_VOLUME_PATH), f"File missing: {EVENT_VOLUME_PATH}"

    actual_rows = []
    with open(EVENT_VOLUME_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert "minute" in reader.fieldnames and "event_count" in reader.fieldnames, "CSV headers must be 'minute' and 'event_count'"
        for row in reader:
            actual_rows.append(row)

    expected_rows = truth_data["expected_csv_rows"]
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, found {len(actual_rows)}"

    for actual, expected in zip(actual_rows, expected_rows):
        assert actual["minute"] == expected["minute"], f"Expected minute {expected['minute']}, found {actual['minute']}"
        assert actual["event_count"] == expected["event_count"], f"Expected count {expected['event_count']} for minute {expected['minute']}, found {actual['event_count']}"


def test_loc_report_html(truth_data):
    assert os.path.exists(LOC_REPORT_PATH), f"File missing: {LOC_REPORT_PATH}"

    with open(LOC_REPORT_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    expected_total = f"Total events processed: {truth_data['total_events']}"
    expected_peak = f"Peak events in a single minute: {truth_data['peak_count']}"
    expected_zero = f"Minutes with zero events: {truth_data['zero_minutes']}"

    assert expected_total in content, f"Expected '{expected_total}' in HTML report."
    assert expected_peak in content, f"Expected '{expected_peak}' in HTML report."
    assert expected_zero in content, f"Expected '{expected_zero}' in HTML report."

    expected_content = (
        "<html>\n"
        "<body>\n"
        "<h1>Localization Operations Report</h1>\n"
        f"<p>{expected_total}</p>\n"
        f"<p>{expected_peak}</p>\n"
        f"<p>{expected_zero}</p>\n"
        "</body>\n"
        "</html>\n"
    )
    assert content == expected_content, "HTML report does not exactly match the required template"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
