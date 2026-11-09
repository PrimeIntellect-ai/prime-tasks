#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import subprocess
import time
import uuid
from datetime import datetime, timedelta

import pytest

SOURCE_PATH = "/home/user/analyze_drift.go"
BASELINE_PATH = "/home/user/baseline.txt"
CHANGES_PATH = "/home/user/changes.log"
REPORT_PATH = "/home/user/drift_report.csv"
BINARY_PATH = "/tmp/analyze_drift_test"


def tokenize(text):
    text = text.lower()
    text = re.sub(r'[^a-z0-9]', ' ', text)
    tokens = set(text.split())
    return tokens


def calculate_jaccard(set1, set2):
    if not set1 and not set2:
        return 1.0
    intersection = len(set1.intersection(set2))
    union = len(set1.union(set2))
    return intersection / union


def run_tool(timeout=20):
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"analyze_drift.go exited with {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "Program did not create drift_report.csv"


@pytest.fixture(scope="session", autouse=True)
def compiled_program():
    assert os.path.isfile(SOURCE_PATH), f"File not found: {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, f"Go source is empty: {SOURCE_PATH}"

    build = subprocess.run(
        ["go", "build", "-o", BINARY_PATH, SOURCE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"Go program failed to compile: {build.stderr}"
    assert os.path.isfile(BINARY_PATH), "Go build did not produce an executable"

    with open(BASELINE_PATH, "rb") as f:
        original_baseline = f.read()
    with open(CHANGES_PATH, "rb") as f:
        original_changes = f.read()

    run_tool()
    try:
        yield
    finally:
        with open(BASELINE_PATH, "wb") as f:
            f.write(original_baseline)
        with open(CHANGES_PATH, "wb") as f:
            f.write(original_changes)
        try:
            run_tool()
        except Exception:
            pass


def test_drift_report():
    baseline_path = "/home/user/baseline.txt"
    changes_path = "/home/user/changes.log"
    report_path = "/home/user/drift_report.csv"

    assert os.path.isfile(baseline_path), f"File not found: {baseline_path}"
    assert os.path.isfile(changes_path), f"File not found: {changes_path}"
    assert os.path.isfile(report_path), f"File not found: {report_path}"

    with open(baseline_path, "r") as f:
        baseline_text = f.read()
    baseline_tokens = tokenize(baseline_text)

    expected_rows = []
    last_dt = None

    with open(changes_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(" | ", 1)
            if len(parts) != 2:
                continue
            ts_str, config_text = parts

            if ts_str == "MISSING":
                assert last_dt is not None, "First line cannot have MISSING timestamp"
                current_dt = last_dt + timedelta(minutes=5)
            else:
                current_dt = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")

            last_dt = current_dt
            formatted_ts = current_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

            config_tokens = tokenize(config_text)
            score = calculate_jaccard(baseline_tokens, config_tokens)
            expected_rows.append((formatted_ts, f"{score:.4f}"))

    actual_rows = []
    with open(report_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                actual_rows.append(tuple(row))

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, found {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}"


def test_program_handles_derived_inputs_and_empty_sets():
    a = "tok" + uuid.uuid4().hex
    b = "tok" + uuid.uuid4().hex
    c = "tok" + uuid.uuid4().hex

    with open(BASELINE_PATH, "w") as f:
        f.write(f"{a}! {b}\n{a}\n")
    with open(CHANGES_PATH, "w") as f:
        f.write(
            "2025-02-03T04:05:06Z | " + a.upper() + ";;" + b.upper() + "\n"
            "MISSING | " + a + "," + c + "\n"
            "MISSING | !!!\n"
            "2025-02-03T05:00:00Z | " + c + "\n"
            "MISSING | " + a + " " + b + " " + c + "\n"
        )

    run_tool()
    with open(REPORT_PATH, "r", newline="") as f:
        actual = f.read().splitlines()
    assert actual == [
        "2025-02-03T04:05:06Z,1.0000",
        "2025-02-03T04:10:06Z,0.3333",
        "2025-02-03T04:15:06Z,0.0000",
        "2025-02-03T05:00:00Z,0.0000",
        "2025-02-03T05:05:00Z,0.6667",
    ]

    with open(BASELINE_PATH, "w") as f:
        f.write("--- !!!\n")
    with open(CHANGES_PATH, "w") as f:
        f.write("2026-01-01T00:00:00Z | ... !!!\n")
    run_tool()
    with open(REPORT_PATH, "r", newline="") as f:
        assert f.read().splitlines() == ["2026-01-01T00:00:00Z,1.0000"]


def test_changes_file_is_streamed_with_bounded_memory():
    line_count = 60000
    start = datetime(2024, 1, 1, 0, 0, 0)
    padding = "!" * 900

    with open(BASELINE_PATH, "w") as f:
        f.write("streamtoken\n")
    with open(CHANGES_PATH, "w") as f:
        f.write("2024-01-01T00:00:00Z | streamtoken " + padding + "\n")
        repeated = "MISSING | streamtoken " + padding + "\n"
        for _ in range(line_count - 1):
            f.write(repeated)

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    proc = subprocess.Popen(
        [BINARY_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
    )
    max_rss_kb = 0
    deadline = time.monotonic() + 40
    while proc.poll() is None:
        assert time.monotonic() < deadline, "Program timed out on the large streaming input"
        try:
            with open(f"/proc/{proc.pid}/status", "r") as status:
                for line in status:
                    if line.startswith("VmRSS:"):
                        max_rss_kb = max(max_rss_kb, int(line.split()[1]))
                        break
        except FileNotFoundError:
            pass
        time.sleep(0.002)

    stderr = proc.communicate()[1]
    assert proc.returncode == 0, f"Program failed on large input: {stderr}"
    assert max_rss_kb < 40 * 1024, (
        f"Program used {max_rss_kb / 1024:.1f} MiB while reading a roughly 55 MiB log; "
        "changes.log must be streamed line-by-line"
    )

    count = 0
    first = None
    last = None
    with open(REPORT_PATH, "r") as f:
        for raw in f:
            row = raw.rstrip("\n")
            if count == 0:
                first = row
            last = row
            count += 1

    expected_last = start + timedelta(minutes=5 * (line_count - 1))
    assert count == line_count
    assert first == "2024-01-01T00:00:00Z,1.0000"
    assert last == expected_last.strftime("%Y-%m-%dT%H:%M:%SZ") + ",1.0000"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
