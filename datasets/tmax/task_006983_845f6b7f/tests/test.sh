#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import shutil
import stat
import subprocess
from collections import defaultdict

HOME = "/home/user"
INPUT = os.path.join(HOME, "app_logs.jsonl")
OUTPUT = os.path.join(HOME, "anomalies.csv")

ORIGINAL = [
    ("2023-10-01T10:00:01Z", "/api/users", 100, "Mozilla/5.0", None),
    ("2023-10-01T10:00:02Z", "/api/users", 105, "Chrome", "u002X"),
    ("2023-10-01T10:00:03Z", "/api/users", 95, "Safari", None),
    ("2023-10-01T10:00:04Z", "/api/users", 110, "Edge", "u123Z"),
    ("2023-10-01T10:00:05Z", "/api/users", 100, "Mozilla/5.0", None),
    ("2023-10-01T10:00:06Z", "/api/users", 450, "BadBot", None),
    ("2023-10-01T10:00:07Z", "/api/users", 105, "Chrome", None),
    ("2023-10-01T10:00:01Z", "/api/auth", 50, "Mozilla", None),
    ("2023-10-01T10:00:02Z", "/api/auth", 52, "Chrome", "uGGGG"),
    ("2023-10-01T10:00:03Z", "/api/auth", 48, "Safari", None),
    ("2023-10-01T10:00:04Z", "/api/auth", 51, "Edge", None),
    ("2023-10-01T10:00:05Z", "/api/auth", 49, "Mozilla", None),
    ("2023-10-01T10:00:06Z", "/api/auth", 60, "Curl", None),
    ("2023-10-01T10:00:07Z", "/api/auth", 200, "Python", None),
]

DYNAMIC_1 = [
    ("2024-02-03T12:00:06Z", "/beta", 61, "B6", "u12Q4"),
    ("2024-02-03T12:00:03Z", "/alpha", 10, "A3", None),
    ("2024-02-03T12:00:01Z", "/beta", 20, "B1", None),
    ("2024-02-03T12:00:06Z", "/alpha", 31, "A6", "u00ZZ"),
    ("2024-02-03T12:00:02Z", "/alpha", 10, "A2", "u002X"),
    ("2024-02-03T12:00:05Z", "/beta", 20, "B5", None),
    ("2024-02-03T12:00:01Z", "/alpha", 10, "A1", None),
    ("2024-02-03T12:00:04Z", "/beta", 20, "B4", None),
    ("2024-02-03T12:00:05Z", "/alpha", 10, "A5", None),
    ("2024-02-03T12:00:02Z", "/beta", 22, "B2", None),
    ("2024-02-03T12:00:04Z", "/alpha", 10, "A4", None),
    ("2024-02-03T12:00:03Z", "/beta", 18, "B3", "uGGGG"),
    ("2024-02-03T12:00:07Z", "/short", 9999, "S1", "u0XX0"),
]

DYNAMIC_2 = [
    ("2025-06-01T00:00:07Z", "/rolling", 500, "R7", "uABCG"),
    ("2025-06-01T00:00:02Z", "/rolling", 20, "R2", None),
    ("2025-06-01T00:00:06Z", "/boundary", 6, "X6", None),
    ("2025-06-01T00:00:05Z", "/rolling", 50, "R5", None),
    ("2025-06-01T00:00:01Z", "/rolling", 10, "R1", "u002X"),
    ("2025-06-01T00:00:04Z", "/rolling", 40, "R4", None),
    ("2025-06-01T00:00:06Z", "/rolling", 100, "R6", None),
    ("2025-06-01T00:00:03Z", "/rolling", 30, "R3", None),
    ("2025-06-01T00:00:01Z", "/boundary", 2, "X1", None),
    ("2025-06-01T00:00:02Z", "/boundary", 2, "X2", "uQQQQ"),
    ("2025-06-01T00:00:03Z", "/boundary", 2, "X3", None),
    ("2025-06-01T00:00:04Z", "/boundary", 2, "X4", None),
    ("2025-06-01T00:00:05Z", "/boundary", 2, "X5", None),
]


def encoded_line(record):
    timestamp, endpoint, response_time, user_agent, bad_escape = record
    obj = {
        "timestamp": timestamp,
        "endpoint": endpoint,
        "response_time_ms": response_time,
        "user_agent": user_agent,
    }
    line = json.dumps(obj)
    if bad_escape is not None:
        replacement = '"' + user_agent + chr(92) + bad_escape + '"'
        line = line.replace(json.dumps(user_agent), replacement)
    return line


def expected_rows(records):
    grouped = defaultdict(list)
    for timestamp, endpoint, response_time, _ua, _bad in records:
        grouped[endpoint].append((timestamp, response_time))

    result = []
    for endpoint, requests in grouped.items():
        requests.sort(key=lambda item: item[0])
        for index in range(5, len(requests)):
            timestamp, response_time = requests[index]
            rolling_avg = sum(value for _ts, value in requests[index - 5:index]) / 5.0
            if response_time > 3.0 * rolling_avg:
                result.append([
                    timestamp,
                    endpoint,
                    str(response_time),
                    f"{rolling_avg:.1f}",
                ])
    result.sort(key=lambda row: row[0])
    return [["timestamp", "endpoint", "response_time_ms", "rolling_avg"]] + result


def remove_output():
    if os.path.lexists(OUTPUT):
        if os.path.isdir(OUTPUT) and not os.path.islink(OUTPUT):
            shutil.rmtree(OUTPUT)
        else:
            os.unlink(OUTPUT)


def run_case(script, records):
    with open(INPUT, "w", encoding="utf-8") as handle:
        for record in records:
            handle.write(encoded_line(record) + "\n")
    remove_output()

    completed = subprocess.run(
        ["python3", script],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"{script} exited with {completed.returncode}: {completed.stderr[-1000:]}"
    )
    assert os.path.isfile(OUTPUT), f"{script} did not create {OUTPUT}"
    with open(OUTPUT, "r", newline="", encoding="utf-8") as handle:
        actual = list(csv.reader(handle))
    assert actual == expected_rows(records), (
        f"{script} produced incorrect output. Expected {expected_rows(records)}, got {actual}"
    )


def python_script_candidates():
    candidates = []
    skipped_dirs = {"__pycache__", ".git", ".venv", "venv", "site-packages"}
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [name for name in dirs if name not in skipped_dirs]
        for name in files:
            path = os.path.join(root, name)
            if path in (INPUT, OUTPUT) or os.path.islink(path):
                continue
            try:
                mode = os.stat(path).st_mode
                if not stat.S_ISREG(mode) or os.path.getsize(path) > 2_000_000:
                    continue
                with open(path, "rb") as handle:
                    source = handle.read()
                compile(source, path, "exec")
            except (OSError, SyntaxError, UnicodeDecodeError, ValueError):
                continue
            candidates.append(path)
    return sorted(candidates, key=lambda path: (path.count(os.sep), path))


def test_00_processing_script_exists_and_works():
    candidates = python_script_candidates()
    assert candidates, "No Python processing script was found under /home/user."

    failures = []
    for script in candidates:
        try:
            run_case(script, DYNAMIC_1)
            run_case(script, DYNAMIC_2)
            # Leave the required output for the supplied log fixture in place.
            run_case(script, ORIGINAL)
            return
        except Exception as exc:
            failures.append(f"{script}: {exc}")

    raise AssertionError(
        "No Python script correctly processed the supplied and independent log cases:\n"
        + "\n".join(failures[-10:])
    )


def test_anomalies_csv_exists():
    csv_path = "/home/user/anomalies.csv"
    assert os.path.exists(csv_path), f"The file {csv_path} was not created."
    assert os.path.isfile(csv_path), f"The path {csv_path} is not a file."


def test_anomalies_csv_contents():
    csv_path = "/home/user/anomalies.csv"
    assert os.path.exists(csv_path), f"The file {csv_path} does not exist."

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The anomalies.csv file is empty."

    header = rows[0]
    expected_header = ["timestamp", "endpoint", "response_time_ms", "rolling_avg"]
    assert header == expected_header, f"Expected header {expected_header}, but got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == 2, f"Expected exactly 2 anomaly rows, but got {len(data_rows)}."

    expected_rows_fixed = [
        ["2023-10-01T10:00:06Z", "/api/users", "450", "102.0"],
        ["2023-10-01T10:00:07Z", "/api/auth", "200", "52.0"]
    ]

    for i, expected in enumerate(expected_rows_fixed):
        assert data_rows[i] == expected, f"Row {i+1} mismatch. Expected {expected}, but got {data_rows[i]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
