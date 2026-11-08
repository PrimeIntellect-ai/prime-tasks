#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

SOURCE = "/home/user/process_etl.c"
EXECUTABLE = "/home/user/process_etl"
INPUT = "/home/user/etl_dump.csv"
OUTPUT = "/home/user/clean_data.csv"


def compile_program():
    subprocess.run(
        ["gcc", SOURCE, "-o", EXECUTABLE],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )


def run_program():
    subprocess.run(
        [EXECUTABLE],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist. Did you run your C program?"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def word_count(notes):
    count = 0
    in_word = False
    for byte in notes.encode("utf-8"):
        is_alnum = (48 <= byte <= 57) or (65 <= byte <= 90) or (97 <= byte <= 122)
        if is_alnum and not in_word:
            count += 1
        in_word = is_alnum
    return count


def expected_output(records):
    result = []
    current_id = None
    pending = None
    last_valid = 0.0

    for record_id, timestamp, username, measurement, notes in records:
        if measurement not in ("", "NA"):
            last_valid = float(measurement)
        normalized = username.strip(" \t").lower()
        pending = f"{record_id},{normalized},{last_valid:.1f},{word_count(notes)}"

        if current_id is None:
            current_id = record_id
        elif record_id != current_id:
            # pending was just replaced, so reconstruct the previous group's last row.
            raise AssertionError("expected_output requires grouped processing helper")

    # This simple branch is unused; grouped implementation below is authoritative.
    return result + ([pending] if pending is not None else [])


def derive_expected(records):
    output = []
    last_valid = 0.0
    current_id = None
    current_line = None

    for record_id, timestamp, username, measurement, notes in records:
        if current_id is not None and record_id != current_id:
            output.append(current_line)

        if measurement not in ("", "NA"):
            last_valid = float(measurement)

        normalized = username.strip(" \t").lower()
        current_line = f"{record_id},{normalized},{last_valid:.1f},{word_count(notes)}"
        current_id = record_id

    if current_line is not None:
        output.append(current_line)
    return output


def write_records(records):
    with open(INPUT, "w", encoding="utf-8", newline="") as f:
        for record in records:
            f.write(",".join(record) + "\n")


def test_c_source_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile your C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_clean_data_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist. Did you run your C program?"

    records = [
        ("101", "1620000000", " Alice ", "45.5", "First note"),
        ("101", "1620000010", " ALICE", "NA", "Retry note!"),
        ("102", "1620000020", "Bob", "NA", "No measurement here..."),
        ("103", "1620000030", " ChArLiE", "50.0", "Valid row with résumé"),
        ("103", "1620000040", "charlie ", "NA", "Valid row with resume"),
        ("104", "1620000050", "  DAVE  ", "", "Empty measurement field"),
    ]
    expected_lines = [
        "101,alice,45.5,2",
        "102,bob,45.5,3",
        "103,charlie,50.0,4",
        "104,dave,50.0,3",
    ]

    write_records(records)
    compile_program()
    run_program()
    actual_lines = read_output()

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} rows in {OUTPUT}, but found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Row {i+1} in {OUTPUT} does not match expected output.\n"
            f"Expected: {expected}\nActual:   {actual}"
        )


def test_program_on_unseen_input():
    rng = random.SystemRandom()
    records = [
        ("200", "1700000000", "\tFIRST User\t", "NA", "!!!"),
        ("200", "1700000001", "Ignored", "12.3", "discarded valid row"),
        ("200", "1700000002", "  BeTa  ", "", "café--42"),
        ("201", "1700000003", "\tGAMMA ", "NA", "résumé + test_case"),
        ("202", "1700000004", " Delta", "8.4", "A😀B...C"),
        ("202", "1700000005", "DELTA\t", "NA", "last retry"),
    ]

    usernames = [" Alice ", "\tBOB\t", " MiXeD42 ", "user_name", "  ZED"]
    measurements = ["NA", "", "1.2", "17.6", "93.4", "-5.1"]
    notes = [
        "alpha beta",
        "one,two;three",
        "café déjà vu",
        "A😀B 99-bottles",
        "___ punctuation ___",
        "x1 y2 z3",
    ]

    for offset in range(18):
        record_id = str(300 + offset)
        for retry in range(rng.randint(1, 3)):
            records.append((
                record_id,
                str(1800000000 + offset * 10 + retry),
                rng.choice(usernames),
                rng.choice(measurements),
                rng.choice(notes),
            ))

    expected_lines = derive_expected(records)
    write_records(records)
    run_program()
    actual_lines = read_output()
    assert actual_lines == expected_lines, (
        "Program output was incorrect for an unseen valid ETL input.\n"
        f"Expected: {expected_lines!r}\nActual:   {actual_lines!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
