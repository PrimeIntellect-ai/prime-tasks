#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import string
import subprocess

import pytest

SOURCE = "/home/user/processor.cpp"
BINARY = "/tmp/verified_processor"
INPUT = "/home/user/raw_reviews.csv"
OUTPUT = "/home/user/clean_features.jsonl"
LOG = "/home/user/pipeline.log"


def run_processor():
    for path in (OUTPUT, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Compiled processor exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def clean_text(text):
    lowered = text.lower()
    filtered = "".join(c for c in lowered if c in string.ascii_lowercase + string.digits + " ")
    return " ".join(filtered.split())


def derive_expected(rows):
    records = []
    counts = []
    previous_valid_user = None
    skipped = 0

    for _, user_id, review in rows:
        if previous_valid_user is not None and user_id == previous_valid_user:
            skipped += 1
            continue

        cleaned = clean_text(review)
        count = 0 if not cleaned else len(cleaned.split(" "))
        counts.append(count)
        rolling = sum(counts[-3:]) / len(counts[-3:])
        records.append({
            "user_id": user_id,
            "clean_text": cleaned,
            "word_count": count,
            "rolling_avg_3": rolling,
        })
        previous_valid_user = user_id

    return records, skipped


def mixed_case(word):
    return "".join(c.upper() if i % 2 == 0 else c for i, c in enumerate(word))


def random_word():
    return "".join(secrets.choice(string.ascii_lowercase) for _ in range(random.randint(5, 10)))


def assert_generated_outputs(expected, skipped):
    assert os.path.exists(OUTPUT), f"Expected output file {OUTPUT} is missing."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected), f"Expected {len(expected)} generated records, found {len(lines)}."

    for index, (line, wanted) in enumerate(zip(lines, expected), 1):
        try:
            actual = json.loads(line)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Generated output line {index} is not valid JSON: {exc}")

        assert actual.get("user_id") == wanted["user_id"]
        assert actual.get("clean_text") == wanted["clean_text"]
        assert type(actual.get("word_count")) is int
        assert actual["word_count"] == wanted["word_count"]
        assert type(actual.get("rolling_avg_3")) in (int, float)
        assert abs(actual["rolling_avg_3"] - wanted["rolling_avg_3"]) < 0.005

        match = re.search(r'"rolling_avg_3"\s*:\s*(-?\d+\.\d{2})(?=\s*[,}])', line)
        assert match, f"Generated record {index} must format rolling_avg_3 with exactly two decimal places."
        assert match.group(1) == f'{wanted["rolling_avg_3"]:.2f}'

    assert os.path.exists(LOG), f"Expected log file {LOG} is missing."
    with open(LOG, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected_log = f"[INFO] Processed {len(expected)} valid records. Skipped {skipped} duplicate records."
    assert content == expected_log


def test_processor_compiles_and_processes_derived_input():
    assert os.path.isfile(SOURCE), f"Expected C++ source file {SOURCE} is missing or is not a file."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"processor.cpp did not compile.\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )

    with open(INPUT, "rb") as f:
        original_input = f.read()

    words = [random_word() for _ in range(8)]
    ids = ["id_" + secrets.token_hex(5) for _ in range(5)]
    rows = [
        ("2000", ids[0], f"  {mixed_case(words[0])}!!!   {mixed_case(words[1])} 123 "),
        ("2001", ids[0], "THIS DUPLICATE MUST BE SKIPPED"),
        ("2002", ids[0], "THIS CONSECUTIVE DUPLICATE MUST ALSO BE SKIPPED"),
        ("2003", ids[1], "!!!___"),
        ("2004", ids[2], f"{mixed_case(words[2])}-{mixed_case(words[3])}   {words[4]}"),
        ("2005", ids[2], "ANOTHER DUPLICATE"),
        ("2006", ids[3], f"9{mixed_case(words[5])}     {words[6]}"),
        ("2007", ids[4], f"{mixed_case(words[7])} 42"),
    ]
    expected, skipped = derive_expected(rows)

    try:
        with open(INPUT, "w", encoding="utf-8", newline="") as f:
            f.write("timestamp,user_id,review_text\n")
            for timestamp, user_id, review in rows:
                f.write(f"{timestamp},{user_id},{review}\n")

        run_processor()
        assert_generated_outputs(expected, skipped)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        if os.path.exists(BINARY):
            run_processor()


def test_clean_features_jsonl():
    file_path = "/home/user/clean_features.jsonl"
    assert os.path.exists(file_path), f"Expected output file {file_path} is missing."

    expected_records = [
        {"user_id": "u1", "clean_text": "great product highly recommend", "word_count": 4, "rolling_avg_3": 4.00},
        {"user_id": "u2", "clean_text": "terrible service wont buy again", "word_count": 5, "rolling_avg_3": 4.50},
        {"user_id": "u3", "clean_text": "okay but 100 too expensive", "word_count": 5, "rolling_avg_3": 4.67},
        {"user_id": "u4", "clean_text": "i love it", "word_count": 3, "rolling_avg_3": 4.33},
        {"user_id": "u5", "clean_text": "wait what", "word_count": 2, "rolling_avg_3": 3.33},
        {"user_id": "u6", "clean_text": "multiple spaces here", "word_count": 3, "rolling_avg_3": 2.67}
    ]

    actual_records = []
    with open(file_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_records.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {file_path} is not valid JSON: {line}")

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} records, but found {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual.get("user_id") == expected["user_id"], f"Record {i+1} user_id mismatch. Expected {expected['user_id']}, got {actual.get('user_id')}"
        assert actual.get("clean_text") == expected["clean_text"], f"Record {i+1} clean_text mismatch. Expected '{expected['clean_text']}', got '{actual.get('clean_text')}'"
        assert actual.get("word_count") == expected["word_count"], f"Record {i+1} word_count mismatch. Expected {expected['word_count']}, got {actual.get('word_count')}"
        actual_avg = actual.get("rolling_avg_3")
        assert actual_avg is not None, f"Record {i+1} is missing 'rolling_avg_3'"
        assert isinstance(actual_avg, (int, float)), f"Record {i+1} 'rolling_avg_3' must be a number"
        assert abs(actual_avg - expected["rolling_avg_3"]) < 0.005, f"Record {i+1} rolling_avg_3 mismatch. Expected {expected['rolling_avg_3']}, got {actual_avg}"

    with open(file_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
        for i, line in enumerate(lines):
            expected_str = f"{expected_records[i]['rolling_avg_3']:.2f}"
            assert expected_str in line, f"Record {i+1} does not appear to have 'rolling_avg_3' formatted to exactly 2 decimal places. Expected to find '{expected_str}' in line."


def test_pipeline_log():
    file_path = "/home/user/pipeline.log"
    assert os.path.exists(file_path), f"Expected log file {file_path} is missing."
    expected_log = "[INFO] Processed 6 valid records. Skipped 2 duplicate records."
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == expected_log, f"Log file content mismatch. Expected '{expected_log}', got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
