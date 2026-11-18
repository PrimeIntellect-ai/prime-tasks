#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import secrets
import subprocess

import pytest

RAW_PATH = "/home/user/raw_logs.csv"
OUTPUT_PATH = "/home/user/cleaned_logs.csv"
SOURCE_PATH = "/home/user/clean_logs.c"
EXECUTABLE_PATH = "/home/user/clean_logs"
REFERENCE = "SYSTEM_STARTUP_SEQUENCE_INITIATED"


def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def get_expected_output(raw_logs_path):
    expected_rows = []
    with open(raw_logs_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            log_msg = row.get("log_message", "")
            if not log_msg:
                continue
            cleaned_msg = log_msg.replace("\n", " ")
            if not cleaned_msg:
                continue
            expected_rows.append({
                "timestamp": int(row["timestamp"]),
                "user_id": row["user_id"],
                "cleaned_log_message": cleaned_msg,
                "distance": levenshtein(cleaned_msg, REFERENCE),
            })

    expected_rows.sort(key=lambda x: x["timestamp"])
    for i, row in enumerate(expected_rows):
        if i == 0:
            row["is_anomaly"] = 0
        else:
            row["is_anomaly"] = int(
                abs(row["distance"] - expected_rows[i - 1]["distance"]) > 10
            )
    return expected_rows


def read_and_check_output(expected_data):
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} is missing."

    actual_data = []
    with open(OUTPUT_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 5, f"Expected 5 columns in output, got {len(row)} in row: {row}"
            actual_data.append({
                "timestamp": int(row[0]),
                "user_id": row[1],
                "cleaned_log_message": row[2],
                "distance": int(row[3]),
                "is_anomaly": int(row[4]),
            })

    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} rows in output, got {len(actual_data)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual["timestamp"] == expected["timestamp"], f"Row {i+1}: expected timestamp {expected['timestamp']}, got {actual['timestamp']}"
        assert actual["user_id"] == expected["user_id"], f"Row {i+1}: expected user_id {expected['user_id']}, got {actual['user_id']}"
        assert actual["cleaned_log_message"] == expected["cleaned_log_message"], f"Row {i+1}: expected message '{expected['cleaned_log_message']}', got '{actual['cleaned_log_message']}'"
        assert actual["distance"] == expected["distance"], f"Row {i+1}: expected distance {expected['distance']}, got {actual['distance']}"
        assert actual["is_anomaly"] == expected["is_anomaly"], f"Row {i+1}: expected is_anomaly {expected['is_anomaly']}, got {actual['is_anomaly']}"


def run_candidate(path):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"{path} did not generate {OUTPUT_PATH}."


def write_dataset(rows):
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(["timestamp", "user_id", "log_message"])
    writer.writerows(rows)
    with open(RAW_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(buffer.getvalue())


def make_altered_dataset():
    nonce = secrets.token_hex(8)
    base = random.SystemRandom().randint(1700000000, 1900000000)
    rows = [
        [base + 50, f"u_comma_{nonce}", f"entry,{nonce},with comma"],
        [base + 10, f"u_ref_{nonce}", REFERENCE],
        [base + 20, f"u_ten_{nonce}", REFERENCE[:-10]],
        [base + 70, f"u_empty_{nonce}", ""],
        [base + 40, f"u_multi_{nonce}", f"first {nonce}\nsecond line\nthird line"],
        [base + 30, f"u_short_{nonce}", "x"],
        [base + 60, f"u_plain_{nonce}", f"ordinary event {nonce}"],
    ]
    random.SystemRandom().shuffle(rows)
    return rows


@pytest.fixture(scope="session", autouse=True)
def restore_original_state():
    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()
    yield
    with open(RAW_PATH, "wb") as f:
        f.write(original_raw)
    run_candidate(EXECUTABLE_PATH)


def test_c_source_exists():
    assert os.path.isfile(SOURCE_PATH), "The C source file /home/user/clean_logs.c is missing."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), "The compiled executable /home/user/clean_logs is missing."
    assert os.access(EXECUTABLE_PATH, os.X_OK), "/home/user/clean_logs is not executable."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/clean_logs is not a compiled native executable."


def test_cleaned_logs_correctness():
    expected_data = get_expected_output(RAW_PATH)
    run_candidate(EXECUTABLE_PATH)
    read_and_check_output(expected_data)


def test_provided_executable_on_altered_input():
    for _ in range(2):
        write_dataset(make_altered_dataset())
        expected_data = get_expected_output(RAW_PATH)
        run_candidate(EXECUTABLE_PATH)
        read_and_check_output(expected_data)


def test_source_compiles_and_works_on_altered_input():
    rebuilt = "/tmp/clean_logs_recompiled"
    result = subprocess.run(
        ["gcc", "-O3", SOURCE_PATH, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, f"gcc -O3 failed to compile clean_logs.c: {result.stderr}"
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    for _ in range(2):
        write_dataset(make_altered_dataset())
        expected_data = get_expected_output(RAW_PATH)
        run_candidate(rebuilt)
        read_and_check_output(expected_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
