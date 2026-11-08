#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import calendar
import datetime
import json
import os
import random
import secrets
import subprocess
import time

import pytest

MERGER = "/home/user/merger"
SOURCE = "/home/user/merger.c"
CSV_INPUT = "/home/user/service_a.csv"
JSONL_INPUT = "/home/user/service_b.jsonl"
OUTPUT = "/home/user/matches.csv"


def test_merger_c_exists():
    file_path = SOURCE
    assert os.path.isfile(file_path), f"Source file missing: {file_path}"


def test_merger_executable_exists():
    file_path = MERGER
    assert os.path.isfile(file_path), f"Compiled executable missing: {file_path}"
    assert os.access(file_path, os.X_OK), f"File is not executable: {file_path}"
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled executable is not an ELF binary"


def test_matches_csv_correct():
    file_path = OUTPUT
    assert os.path.isfile(file_path), f"Output file missing: {file_path}"

    with open(file_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "btn_save,save_btn,2,2",
        "btn_start,start_btn,4,2"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in matches.csv, but got {len(lines)}"

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'"


def levenshtein_bytes(left, right):
    a = left.encode("utf-8")
    b = right.encode("utf-8")
    previous = list(range(len(b) + 1))
    for i, av in enumerate(a, 1):
        current = [i]
        for j, bv in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (av != bv),
            ))
        previous = current
    return previous[-1]


def csv_epoch(value):
    return calendar.timegm(time.strptime(value, "%Y:%m:%d-%H:%M:%S"))


def json_epoch(value):
    return calendar.timegm(time.strptime(value, "%Y-%m-%dT%H:%M:%SZ"))


def expected_output(a_records, b_records):
    matches = []
    for ats, akey, source in a_records:
        atime = csv_epoch(ats)
        for record in b_records:
            diff = abs(atime - json_epoch(record["ts"]))
            distance = levenshtein_bytes(source, record["src"])
            if diff <= 5 and distance <= 3:
                matches.append((akey, f'{akey},{record["key"]},{diff},{distance}'))
    matches.sort(key=lambda item: item[0])
    return [line for _, line in matches]


def run_case(a_records, b_records):
    with open(CSV_INPUT, "w", encoding="utf-8", newline="") as f:
        for ts, key, source in a_records:
            f.write(f"{ts},{key},{source}\n")

    with open(JSONL_INPUT, "w", encoding="ascii", newline="") as f:
        for record in b_records:
            f.write(json.dumps(record, ensure_ascii=True) + "\n")

    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)

    result = subprocess.run(
        [MERGER],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )
    assert result.returncode == 0, (
        f"merger exited with {result.returncode}; stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT), "merger did not create /home/user/matches.csv"

    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual = [line.rstrip("\r\n") for line in f if line.strip()]
    expected = expected_output(a_records, b_records)
    assert actual == expected, f"Expected {expected!r}, got {actual!r}"


def test_merger_behavior_on_fresh_inputs():
    fixed_a = [
        ("2024:02:29-12:03:00", "zulu", "Hello"),
        ("2024:02:29-12:00:00", "alpha", "e"),
        ("2024:02:29-12:02:00", "mike", "Save"),
        ("2024:02:29-12:01:00", "beta", 'a"b\\c'),
    ]
    fixed_b = [
        {"ts": "2024-02-29T12:03:05Z", "key": "hello_unicode", "src": "Héllo"},
        {"ts": "2024-02-29T11:59:55Z", "key": "accented_e", "src": "é"},
        {"ts": "2024-02-29T12:02:00Z", "key": "byte_distance_four", "src": "Sávé"},
        {"ts": "2024-02-29T12:01:03Z", "key": "escaped_json", "src": 'a"b\\c'},
        {"ts": "2024-02-29T12:03:06Z", "key": "too_late", "src": "Hello"},
        {"ts": "2024-02-29T12:00:00Z", "key": "too_different", "src": "completely different"},
    ]
    run_case(fixed_a, fixed_b)

    rng = random.SystemRandom()
    base = datetime.datetime(2025, 7, 14, 9, 30, 0, tzinfo=datetime.timezone.utc)
    random_a = []
    random_b = []
    for i in range(7):
        moment = base + datetime.timedelta(seconds=25 * i)
        key = f"k_{secrets.token_hex(4)}"
        source = "café" if i == 0 else f"text_{secrets.token_hex(3)}"
        random_a.append((moment.strftime("%Y:%m:%d-%H:%M:%S"), key, source))

        offset = rng.randint(-5, 5)
        matched_text = source if i == 0 else source + "x"
        random_b.append({
            "ts": (moment + datetime.timedelta(seconds=offset)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "key": f"b_{secrets.token_hex(4)}",
            "src": matched_text,
        })
        random_b.append({
            "ts": (moment + datetime.timedelta(seconds=6)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "key": f"late_{secrets.token_hex(3)}",
            "src": source,
        })
        random_b.append({
            "ts": moment.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "key": f"far_{secrets.token_hex(3)}",
            "src": "XXXXXXXXXXXXXXXXXXXXXXXX",
        })

    rng.shuffle(random_b)
    run_case(random_a, random_b)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
