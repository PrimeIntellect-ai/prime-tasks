#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_mapped_errors_jsonl():
    jsonl_path = "/home/user/mapped_errors.jsonl"
    assert os.path.isfile(jsonl_path), f"Output file {jsonl_path} does not exist."

    expected_objects = [
        {"timestamp": "2023-10-01 10:00:00", "level": "ERROR", "category": "Database Issue"},
        {"timestamp": "2023-10-01 10:05:00", "level": "WARNING", "category": "Disk Issue"},
        {"timestamp": "2023-10-01 10:10:00", "level": "CRITICAL", "category": "Memory Issue"},
        {"timestamp": "2023-10-01 10:15:00", "level": "INFO", "category": "Unknown"},
        {"timestamp": "2023-10-01 10:20:00", "level": "ERROR", "category": "Database Issue"}
    ]

    with open(jsonl_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 lines in {jsonl_path}, found {len(lines)}."

    for idx, (line, expected) in enumerate(zip(lines, expected_objects)):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {idx+1} is not valid JSON: {line}")

        assert obj == expected, f"Line {idx+1} does not match expected output.\nExpected: {expected}\nGot: {obj}"

def test_pipeline_log():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read()

    expected_log = "[INFO] Processed 5 logs, 4 matched, 1 unknown"
    assert expected_log in content, f"Expected log line '{expected_log}' not found in {log_path}."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_process_logs_behavior.py
import csv
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

SCRIPT = Path("/home/user/process_logs.py")
LOGS = Path("/home/user/logs.txt")
CATEGORIES = Path("/home/user/categories.csv")
OUTPUT = Path("/home/user/mapped_errors.jsonl")
PIPELINE = Path("/home/user/pipeline.log")
PATHS = [LOGS, CATEGORIES, OUTPUT, PIPELINE]


def tokens(text):
    return set(re.sub(r"[^a-z0-9]", " ", text.lower()).split())


def expected_mapping(log_rows, category_rows):
    references = [(name, tokens(reference)) for name, reference in category_rows]
    result = []
    for timestamp, level, message in log_rows:
        message_tokens = tokens(message)
        best_name = "Unknown"
        best_score = 0.0
        for name, reference_tokens in references:
            union = message_tokens | reference_tokens
            score = len(message_tokens & reference_tokens) / len(union) if union else 0.0
            if score > best_score:
                best_score = score
                best_name = name
        result.append({
            "timestamp": timestamp,
            "level": level,
            "category": best_name if best_score != 0.0 else "Unknown",
        })
    return result


def run_case(round_number, reverse_categories=False):
    nonce = secrets.token_hex(8)
    a1, a2 = "a" + nonce, "ax" + nonce
    b1, b2 = "b" + nonce, "bx" + nonce
    c1 = "c" + nonce
    unknown = "unknown" + secrets.token_hex(8)

    category_rows = [
        ("First-" + nonce, f"{a1}! shared 123, {a2}"),
        ("Second-" + nonce, f"{b1}? shared 123; {b2}"),
        ("Third-" + nonce, f"prefix {c1} suffix"),
    ]
    if reverse_categories:
        category_rows = list(reversed(category_rows))

    log_rows = [
        (f"2026-01-0{round_number} 01:02:03", "ERROR", f"{a1.upper()}---{a2}"),
        (f"2026-01-0{round_number} 02:03:04", "WARNING", f"{b1}/{b2}"),
        (f"2026-01-0{round_number} 03:04:05", "INFO", "SHARED...123"),
        (f"2026-01-0{round_number} 04:05:06", "CRITICAL", f"prefix,{c1};suffix"),
        (f"2026-01-0{round_number} 05:06:07", "DEBUG", unknown),
    ]
    expected = expected_mapping(log_rows, category_rows)

    with CATEGORIES.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["category_name", "reference_text"])
        writer.writerows(category_rows)

    LOGS.write_text("".join(
        f"{timestamp} | {level} | {message}\n"
        for timestamp, level, message in log_rows
    ))

    seed = f"[PREEXISTING] round {round_number}"
    PIPELINE.write_text(seed + "\n")
    if OUTPUT.exists():
        OUTPUT.unlink()

    completed = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"process_logs.py failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert OUTPUT.is_file(), "Script did not create mapped_errors.jsonl"

    raw_lines = OUTPUT.read_text().splitlines()
    assert len(raw_lines) == len(expected), "Output must contain exactly one JSON line per input log"
    actual = []
    for index, line in enumerate(raw_lines, 1):
        assert line.strip(), f"Output line {index} is empty"
        obj = json.loads(line)
        assert set(obj) == {"timestamp", "level", "category"}, f"Wrong keys on output line {index}"
        actual.append(obj)
    assert actual == expected

    matched = sum(item["category"] != "Unknown" for item in expected)
    unknown_count = len(expected) - matched
    expected_log = f"[INFO] Processed {len(expected)} logs, {matched} matched, {unknown_count} unknown"
    assert PIPELINE.read_text().splitlines() == [seed, expected_log], (
        "The script must append exactly one correctly counted pipeline log line"
    )


def test_script_executes_pipeline_on_changed_inputs():
    assert SCRIPT.is_file(), "/home/user/process_logs.py does not exist or is not a file"
    assert SCRIPT.stat().st_size > 0, "/home/user/process_logs.py is empty"

    backups = {}
    for path in PATHS:
        backups[path] = path.read_bytes() if path.exists() else None

    try:
        run_case(1, reverse_categories=False)
        run_case(2, reverse_categories=True)
    finally:
        for path, data in backups.items():
            if data is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_process_logs_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
