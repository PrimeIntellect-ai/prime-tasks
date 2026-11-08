#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import hashlib
import pathlib
import secrets
import subprocess
import pytest

RAW_LOGS_PATH = "/home/user/raw_logs.txt"
REJECTED_LOGS_PATH = "/home/user/rejected_logs.txt"
CLEAN_EVENTS_PATH = "/home/user/clean_events.jsonl"
STATS_PATH = "/home/user/stats.csv"
OUTPUT_PATHS = [REJECTED_LOGS_PATH, CLEAN_EVENTS_PATH, STATS_PATH]

ORIGINAL_RAW_LOGS = """2023-10-01T14:32:01Z | ERROR | Process failed. Client IP: 192.168.1.50, Time taken: 120ms, ErrorCode: E404
2023-10-01T14:32:02Z | WARN | Timeout occurred. Client IP: 10.0.0.5, Time taken: 300ms, ErrorCode: E504
2023-10-01T14:32:03Z | ERROR | Process failed. Client IP: 192.168.1.50, Time taken: 120ms, ErrorCode: E404
2023-10-01T14:32:04Z | ERROR | Bad data. Client IP: 999.999.999.9999, Time taken: 50ms, ErrorCode: E400
2023-10-01T14:32:05Z | ERROR | Corrupted state. Client IP: 172.16.0.1, Time taken: -10ms, ErrorCode: E500
2023-10-01T14:32:06Z | INFO | System check. Client IP: 192.168.1.100, Time taken: 45ms, ErrorCode: E200
2023-10-01T14:32:07Z | WARN | Timeout occurred. Client IP: 10.0.0.5, Time taken: 310ms, ErrorCode: E504
2023-10-01T14:32:08Z | ERROR | Process failed. Client IP: 192.168.1.50, Time taken: 120ms, ErrorCode: E404
2023-10-01T14:32:09Z | INFO | Irrelevant log entry without specific patterns
"""

def parse_raw_logs():
    if not os.path.exists(RAW_LOGS_PATH):
        return []
    with open(RAW_LOGS_PATH, "r") as f:
        return f.read().strip().split("\n")

def process_logs(raw_lines):
    rejected = []
    clean = []
    seen_hashes = set()

    pattern = re.compile(r"^(.*?)\s*\|\s*(.*?)\s*\|.*Client IP:\s*(.*?),\s*Time taken:\s*(-?\d+)ms,\s*ErrorCode:\s*(.*?)$")
    ip_pattern = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")

    for line in raw_lines:
        match = pattern.search(line)
        if not match:
            continue

        timestamp, level, ip, duration_str, code = match.groups()
        duration = int(duration_str)

        is_invalid = False
        if duration < 0:
            is_invalid = True
        if not ip_pattern.match(ip):
            is_invalid = True

        if is_invalid:
            rejected.append(line)
            continue

        hash_str = f"{ip}_{code}_{duration}"
        hash_val = hashlib.sha256(hash_str.encode("utf-8")).hexdigest()

        if hash_val not in seen_hashes:
            seen_hashes.add(hash_val)
            clean.append({
                "timestamp": timestamp,
                "level": level,
                "ip": ip,
                "duration": duration,
                "code": code
            })

    return rejected, clean

def compute_stats(clean_events):
    stats = {}
    for ev in clean_events:
        code = ev["code"]
        if code not in stats:
            stats[code] = {"count": 0, "total_duration": 0}
        stats[code]["count"] += 1
        stats[code]["total_duration"] += ev["duration"]

    result = []
    for code in sorted(stats.keys()):
        count = stats[code]["count"]
        avg = stats[code]["total_duration"] / count
        result.append([code, str(count), f"{avg:.2f}"])
    return result

def write_raw(contents):
    with open(RAW_LOGS_PATH, "w") as f:
        f.write(contents)

def clear_outputs():
    for path in OUTPUT_PATHS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

def outputs_match(raw_text):
    expected_rejected, expected_clean = process_logs(raw_text.strip().split("\n"))
    expected_stats = compute_stats(expected_clean)
    try:
        with open(REJECTED_LOGS_PATH, "r") as f:
            actual_rejected = [line.strip() for line in f if line.strip()]
        actual_clean = []
        with open(CLEAN_EVENTS_PATH, "r") as f:
            for line in f:
                if line.strip():
                    actual_clean.append(json.loads(line))
        with open(STATS_PATH, "r") as f:
            rows = list(csv.reader(f))
    except (OSError, ValueError, json.JSONDecodeError):
        return False
    return (actual_rejected == expected_rejected and
            actual_clean == expected_clean and
            len(rows) > 0 and
            rows[0] == ["ErrorCode", "EventCount", "AvgDuration"] and
            rows[1:] == expected_stats)

def find_python_scripts():
    excluded = {os.path.realpath(RAW_LOGS_PATH)} | {os.path.realpath(p) for p in OUTPUT_PATHS}
    scripts = []
    for path in pathlib.Path("/home/user").rglob("*"):
        try:
            if not path.is_file() or os.path.realpath(path) in excluded:
                continue
            is_python = path.suffix.lower() == ".py"
            if not is_python:
                with path.open("rb") as f:
                    first_line = f.readline(256).lower()
                is_python = first_line.startswith(b"#!") and b"python" in first_line
            if is_python:
                scripts.append(str(path))
        except (OSError, UnicodeError):
            continue
    return sorted(set(scripts))

def test_00_pipeline_script_executes_on_unseen_input():
    token = secrets.randbelow(8000) + 1000
    code_a = f"E{token}"
    code_b = f"W{token + 1}"
    duration_a = secrets.randbelow(150) + 11
    duration_b = duration_a + secrets.randbelow(100) + 1
    duration_c = duration_b + secrets.randbelow(100) + 1
    octet = secrets.randbelow(180) + 20

    hidden_raw = "\n".join([
        f"2026-04-01T01:00:00Z | ERROR | First event. Client IP: 10.20.{octet}.1, Time taken: {duration_a}ms, ErrorCode: {code_a}",
        f"2026-04-01T01:00:01Z | WARN | Second event. Client IP: 10.20.{octet}.2, Time taken: {duration_b}ms, ErrorCode: {code_a}",
        f"2026-04-01T01:00:02Z | INFO | Duplicate retry. Client IP: 10.20.{octet}.1, Time taken: {duration_a}ms, ErrorCode: {code_a}",
        f"2026-04-01T01:00:03Z | ERROR | Other code. Client IP: 172.22.{octet}.3, Time taken: {duration_c}ms, ErrorCode: {code_b}",
        f"2026-04-01T01:00:04Z | ERROR | Negative. Client IP: 192.168.2.3, Time taken: -{duration_a}ms, ErrorCode: {code_b}",
        f"2026-04-01T01:00:05Z | ERROR | Bad IP. Client IP: 1234.1.2.3, Time taken: {duration_b}ms, ErrorCode: {code_a}",
        "2026-04-01T01:00:06Z | INFO | Unstructured line without fields"
    ]) + "\n"

    scripts = find_python_scripts()
    assert scripts, "No Python ETL script was found under /home/user."

    selected = None
    for script in scripts:
        write_raw(hidden_raw)
        clear_outputs()
        try:
            result = subprocess.run(
                ["python3", script], cwd="/home/user",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=15
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0 and outputs_match(hidden_raw):
            selected = script
            break

    assert selected is not None, "No submitted Python script correctly processed an unseen raw log input."

    write_raw(ORIGINAL_RAW_LOGS)
    clear_outputs()
    result = subprocess.run(
        ["python3", selected], cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, f"ETL script failed on the supplied logs: {result.stderr}"

def test_rejected_logs():
    assert os.path.isfile(REJECTED_LOGS_PATH), f"File not found: {REJECTED_LOGS_PATH}"
    raw_lines = parse_raw_logs()
    expected_rejected, _ = process_logs(raw_lines)

    with open(REJECTED_LOGS_PATH, "r") as f:
        actual_rejected = [line.strip() for line in f if line.strip()]

    assert actual_rejected == expected_rejected, "rejected_logs.txt does not contain the correct invalid lines."

def test_clean_events():
    assert os.path.isfile(CLEAN_EVENTS_PATH), f"File not found: {CLEAN_EVENTS_PATH}"
    raw_lines = parse_raw_logs()
    _, expected_clean = process_logs(raw_lines)

    actual_clean = []
    with open(CLEAN_EVENTS_PATH, "r") as f:
        for line in f:
            if line.strip():
                try:
                    actual_clean.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON line in {CLEAN_EVENTS_PATH}: {line}")

    assert len(actual_clean) == len(expected_clean), "clean_events.jsonl has incorrect number of records."
    for actual, expected in zip(actual_clean, expected_clean):
        assert actual == expected, f"Mismatch in clean_events.jsonl. Expected {expected}, got {actual}"

def test_stats_csv():
    assert os.path.isfile(STATS_PATH), f"File not found: {STATS_PATH}"
    raw_lines = parse_raw_logs()
    _, expected_clean = process_logs(raw_lines)
    expected_stats = compute_stats(expected_clean)

    with open(STATS_PATH, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "stats.csv is empty."
    assert rows[0] == ["ErrorCode", "EventCount", "AvgDuration"], "Incorrect header in stats.csv"

    actual_stats = rows[1:]
    assert actual_stats == expected_stats, f"stats.csv data mismatch. Expected {expected_stats}, got {actual_stats}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
