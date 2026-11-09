#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import importlib.util
import os
import re
import subprocess
import sys
import uuid

HOME_DIR = "/home/user"
LOGS_DIR = os.path.join(HOME_DIR, "logs")
MONITOR = os.path.join(HOME_DIR, "uptime_monitor.py")
MRE_LOG = os.path.join(HOME_DIR, "mre.log")
TIMELINE_LOG = os.path.join(HOME_DIR, "consolidated_timeline.log")
WEB_LOG = os.path.join(LOGS_DIR, "web.log")
DB_LOG = os.path.join(LOGS_DIR, "db.log")
CACHE_LOG = os.path.join(LOGS_DIR, "cache.log")

CANONICAL_LOGS = {
    WEB_LOG: [
        "2023-11-01 10:00:01|web|UP|Starting web server",
        "2023-11-01 10:05:22|web|UP|User requested path /login",
        "2023-11-01 10:15:00|web|DOWN|Unhandled exception: User typed a | in the username field",
        "2023-11-01 10:16:05|web|UP|Web server restarted successfully",
    ],
    DB_LOG: [
        "2023-11-01 10:00:00|db|UP|Database initialized",
        "2023-11-01 10:05:23|db|UP|Query executed successfully",
        "2023-11-01 10:15:01|db|UP|Connection lost from web service",
        "2023-11-01 10:16:06|db|UP|Connection established from web service",
    ],
    CACHE_LOG: [
        "2023-11-01 10:00:02|cache|UP|Redis cache started",
        "2023-11-01 10:05:23|cache|UP|Cache miss for user session",
        "2023-11-01 10:12:00|cache|UP|Evicting old keys | count=450",
        "2023-11-01 10:16:06|cache|UP|Cache hit for user session",
    ],
}


def load_monitor():
    assert os.path.isfile(MONITOR), f"File {MONITOR} is missing."
    spec = importlib.util.spec_from_file_location("submitted_uptime_monitor", MONITOR)
    assert spec is not None and spec.loader is not None, f"Cannot import {MONITOR}."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "parse_log_line", None)), "parse_log_line is missing or not callable."
    return module


def test_fixed_parser_and_executable(tmp_path):
    module = load_monitor()
    token = uuid.uuid4().hex
    cases = [
        ("2024-02-03 04:05:06", "hidden-web", "DOWN", f"unexpected | character | token={token}"),
        ("2024-02-03 04:05:07", "hidden-cache", "UP", f"brackets [ok], unicode café, and || token={token}"),
    ]

    hidden_log = tmp_path / "hidden_edge_cases.log"
    with hidden_log.open("w", encoding="utf-8") as f:
        for timestamp, service, status, message in cases:
            raw = f"{timestamp}|{service}|{status}|{message}\n"
            assert module.parse_log_line(raw) == (timestamp, service, status, message)
            f.write(raw)

    result = subprocess.run(
        [sys.executable, MONITOR, str(hidden_log)],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, f"uptime_monitor.py crashed on edge-case input: {result.stderr}"
    for _, _, _, message in cases:
        assert message in result.stdout, "The executable did not preserve the complete message field."


def test_mre_log_valid():
    assert os.path.isfile(MRE_LOG), f"File {MRE_LOG} is missing."
    with open(MRE_LOG, "r", encoding="utf-8") as f:
        raw = f.read()

    physical_lines = raw.splitlines()
    assert len(physical_lines) == 1, f"{MRE_LOG} must contain exactly one line."
    assert physical_lines[0].strip(), f"{MRE_LOG} must contain one nonempty line."

    lines = [line.strip() for line in physical_lines if line.strip()]
    assert len(lines) == 1, f"{MRE_LOG} must contain exactly one line."
    parts = lines[0].split('|')
    assert len(parts) > 4, f"The line in {MRE_LOG} must have more than 3 pipe characters to trigger the bug."

    timestamp, service, status = parts[:3]
    datetime.datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
    assert service and status, "The MRE must retain the documented timestamp, service, and status fields."

    try:
        _timestamp, _service, _status, _message = lines[0].split('|')
    except ValueError:
        pass
    else:
        raise AssertionError("The MRE would not trigger the original unpacking crash.")

    module = load_monitor()
    expected = tuple(lines[0].split('|', 3))
    assert module.parse_log_line(lines[0] + "\n") == expected, "The fixed parser does not correctly parse the MRE."


def test_consolidated_timeline():
    assert os.path.isfile(TIMELINE_LOG), f"File {TIMELINE_LOG} is missing."

    for log_file, canonical_lines in CANONICAL_LOGS.items():
        assert os.path.isfile(log_file), f"Source log {log_file} is missing."
        with open(log_file, "r", encoding="utf-8") as f:
            source_lines = [line.rstrip("\n\r") for line in f]
        assert source_lines == canonical_lines, f"Source log {log_file} was altered."

    # Reconstruct the expected timeline.
    events = []
    log_files = [WEB_LOG, DB_LOG, CACHE_LOG]
    for log_file in log_files:
        if not os.path.isfile(log_file):
            continue
        with open(log_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split('|', 3)
                if len(parts) == 4:
                    events.append(parts)

    events.sort(key=lambda x: (x[0], x[1], x[2], x[3]))
    expected_lines = [f"[{event[0]}] [{event[1]}] [{event[2]}] {event[3]}" for event in events]

    with open(TIMELINE_LOG, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), "The number of lines in consolidated_timeline.log is incorrect."

    # Preserve the original membership and exact-format comparison.
    actual_sorted = sorted(actual_lines)
    expected_sorted = sorted(expected_lines)
    for actual, expected in zip(actual_sorted, expected_sorted):
        assert actual == expected, f"Timeline mismatch. Expected: '{expected}', Got: '{actual}'"

    # Additionally require the submitted file itself to be chronological.
    pattern = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[([^\]]+)\] \[([^\]]+)\] (.*)$")
    actual_timestamps = []
    for line in actual_lines:
        match = pattern.fullmatch(line)
        assert match is not None, f"Invalid timeline format: '{line}'"
        actual_timestamps.append(datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S"))

    assert actual_timestamps == sorted(actual_timestamps), "consolidated_timeline.log is not sorted chronologically."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
