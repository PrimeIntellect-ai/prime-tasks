#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import os
import re
import secrets
import subprocess
import time

import pytest

OUTPUT_FILE = "/home/user/output/clean_events.csv"
SOURCE_FILE = "/home/user/dedup_etl.cpp"
EXECUTABLE = "/home/user/dedup_etl"
INPUT_FILES = [
    "/home/user/data/chunk_A.csv",
    "/home/user/data/chunk_B.csv",
    "/home/user/data/chunk_C.csv",
]
HEADER = ["event_id", "timestamp", "user_name", "action"]


def read_output():
    with open(OUTPUT_FILE, "rb") as f:
        content = f.read()
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as e:
        pytest.fail(f"Output file is not valid UTF-8: {e}")
    return list(csv.reader(text.splitlines()))


def assert_valid_output(expected_rows):
    assert os.path.isfile(OUTPUT_FILE), (
        f"Output file {OUTPUT_FILE} is missing. Did the program run successfully?"
    )
    rows = read_output()
    assert len(rows) > 0, "Output file is empty."
    assert rows[0] == HEADER, f"Expected header {HEADER}, got {rows[0]}"

    data_rows = rows[1:]
    assert all(len(row) == 4 for row in data_rows), "Output contains malformed CSV rows."
    event_ids = [row[0] for row in data_rows]
    assert len(event_ids) == len(set(event_ids)), (
        "Duplicate event_ids found in the output. Deduplication failed."
    )
    assert data_rows == sorted(data_rows, key=lambda x: (x[1], x[0])), (
        "Output data is not sorted correctly by timestamp and event_id."
    )
    assert len(data_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} records, got {len(data_rows)}."
    )
    for i, (actual, expected) in enumerate(zip(data_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i + 1} mismatch. Expected {expected}, got {actual}."
        )


def test_complete_etl_implementation():
    # Preserve all checks against the result the agent was asked to generate.
    assert os.path.isfile(SOURCE_FILE), "Source file /home/user/dedup_etl.cpp is missing."
    assert os.path.isfile(EXECUTABLE), "Compiled executable /home/user/dedup_etl is missing."
    assert os.access(EXECUTABLE, os.X_OK), "File /home/user/dedup_etl is not executable."

    original_expected = [
        ["E101", "2023-10-01T10:00:00", "José", "login"],
        ["E102", "2023-10-01T10:01:00", "Bob", "click"],
        ["E103", "2023-10-01T10:02:00", "Müller", "purchase"],
        ["E104", "2023-10-01T10:04:00", "François", "login"],
        ["E105", "2023-10-01T10:05:00", "Alice", "logout"],
        ["E106", "2023-10-01T10:06:00", "Charlie", "click"],
        ["E107", "2023-10-01T10:08:00", "Diana", "purchase"],
        ["E108", "2023-10-01T10:10:00", "Björn", "logout"],
    ]
    assert_valid_output(original_expected)

    # Confirm the submitted source contains a standard C++ parallelism facility.
    with open(SOURCE_FILE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    parallel_pattern = re.compile(
        r"(?:std::)?execution\s*::\s*par\b|"
        r"(?:std::)?async\s*\(|"
        r"std\s*::\s*thread\b|"
        r"\bthread\s+[A-Za-z_]"
    )
    assert parallel_pattern.search(source_without_comments), (
        "Source does not use std::execution::par, std::thread, or std::async."
    )

    # Compile the submitted source using the exact command required by the task.
    compile_result = subprocess.run(
        [
            "g++", "-std=c++17", "-O3", "-pthread",
            SOURCE_FILE, "-o", EXECUTABLE,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        "Submitted source failed to compile with the required command:\n"
        + compile_result.stderr
    )

    # Replace all chunks with a large, runtime-generated dataset. This detects
    # fixed-output programs and also keeps worker threads alive long enough to observe.
    token = secrets.token_hex(5).upper()
    record_count = 120000
    raw_names = [
        b"Jos\xe9", b"M\xfcller", b"Fran\xe7ois", b"Bj\xf6rn",
        b"Ana\xefs", b"S\xf8ren", b"Zo\xeb", b"Ren\xe9", b"ASCII",
    ]
    actions = ["login", "click", "purchase", "logout", "view"]
    chunks = [[], [], []]
    expected = []
    start = datetime.datetime(2024, 2, 1, 0, 0, 0)

    for i in range(record_count):
        # Four records share each timestamp, requiring event_id tie-breaking.
        event_id = f"{token}-{record_count - i:06d}"
        timestamp = (start + datetime.timedelta(seconds=i // 4)).isoformat()
        name_bytes = raw_names[i % len(raw_names)] + f"-{i % 97}".encode("ascii")
        action = actions[i % len(actions)]
        raw_row = [
            event_id.encode("ascii"),
            timestamp.encode("ascii"),
            name_bytes,
            action.encode("ascii"),
        ]
        chunks[i % 3].append(raw_row)
        if i % 4 == 0:
            chunks[(i % 3 + 1) % 3].append(list(raw_row))
        expected.append([event_id, timestamp, name_bytes.decode("latin-1"), action])

    for path, records in zip(INPUT_FILES, chunks):
        with open(path, "wb") as f:
            f.write(b"event_id,timestamp,user_name,action\n")
            for row in records:
                f.write(b",".join(row) + b"\n")

    expected.sort(key=lambda row: (row[1], row[0]))
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    process = subprocess.Popen(
        [EXECUTABLE], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    max_threads = 0
    deadline = time.monotonic() + 60
    while process.poll() is None:
        try:
            max_threads = max(max_threads, len(os.listdir(f"/proc/{process.pid}/task")))
        except FileNotFoundError:
            pass
        if time.monotonic() > deadline:
            process.kill()
            stdout, stderr = process.communicate()
            pytest.fail(
                "Executable timed out on generated input.\n"
                + stderr.decode("utf-8", errors="replace")
            )
        time.sleep(0.0005)

    stdout, stderr = process.communicate()
    assert process.returncode == 0, (
        f"Executable exited with status {process.returncode}:\n"
        + stderr.decode("utf-8", errors="replace")
    )
    assert max_threads > 1, (
        "No parallel execution was observed while processing the large dataset."
    )
    assert_valid_output(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
