#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import secrets
import stat
import subprocess
import unicodedata

import pytest

PROJECT = "/home/user/cleaner"
SOURCE = "/home/user/cleaner/src/main.rs"
INPUT = "/home/user/data/reviews.csv"
OUTPUT = "/home/user/data/cleaned_reviews.csv"
EXECUTABLE = "/home/user/cleaner/target/debug/cleaner"

CANONICAL_INPUT = (
    b"id,review_2023_01,review_2023_02,review_2023_03\n"
    b"p1,cafe\xcc\x81,,good\n"
    b"p2,\xff\xfehello,Great,\n"
    b"p3,,\xe3\x81\x82\xe3\x82\x8a\xe3\x81\x8c\xe3\x81\xa8\xe3\x81\x86,\xd9\x85\xd9\x85\xd8\xaa\xd8\xa7\xd8\xb2\n"
)


def run_cleaner():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [EXECUTABLE],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Cleaner exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout.decode('utf-8', 'replace')}\n"
        f"stderr:\n{result.stderr.decode('utf-8', 'replace')}"
    )


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_on_original_input():
    assert os.path.lexists(SOURCE), "Rust source /home/user/cleaner/src/main.rs is missing."
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), "src/main.rs must be a regular Rust source file."

    build = subprocess.run(
        ["cargo", "build", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, (
        f"Rust project failed to compile.\n"
        f"stdout:\n{build.stdout.decode('utf-8', 'replace')}\n"
        f"stderr:\n{build.stderr.decode('utf-8', 'replace')}"
    )
    assert os.path.isfile(EXECUTABLE), "Compilation did not produce the cleaner executable."

    with open(INPUT, "wb") as f:
        f.write(CANONICAL_INPUT)
    run_cleaner()


def test_cleaned_reviews_exists():
    assert os.path.isfile(OUTPUT), "The output file /home/user/data/cleaned_reviews.csv is missing."


def test_cleaned_reviews_content():
    rows = []
    with open(OUTPUT, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
            assert header == ["id", "month", "review"], f"Header is incorrect. Expected ['id', 'month', 'review'], got {header}"
            for row in reader:
                rows.append(row)
        except StopIteration:
            pytest.fail("The CSV file is empty (missing header and data).")
        except UnicodeDecodeError as e:
            pytest.fail(f"The CSV file contains invalid UTF-8 bytes: {e}")

    expected_rows = [
        ["p1", "2023_01", "caf\u00e9"],
        ["p1", "2023_03", "good"],
        ["p2", "2023_01", "\ufffd\ufffdhello"],
        ["p2", "2023_02", "Great"],
        ["p3", "2023_02", "ありがとう"],
        ["p3", "2023_03", "ممتاز"],
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)}."
    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual == expected, f"Row {i+1} is incorrect.\nExpected: {expected}\nActual:   {actual}"


def test_unicode_normalization():
    with open(OUTPUT, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row_num, row in enumerate(reader, start=2):
            review = row.get("review", "")
            assert unicodedata.is_normalized("NFC", review), f"Row {row_num}: The review text '{review}' is not in Unicode Normalization Form C (NFC)."


def csv_quote_bytes(value):
    if any(ch in value for ch in (b",", b'"', b"\r", b"\n")):
        return b'"' + value.replace(b'"', b'""') + b'"'
    return value


def test_program_on_additional_randomized_input():
    token = secrets.token_hex(12)
    token_bytes = token.encode("ascii")
    ids = [("item_" + secrets.token_hex(6)).encode("ascii") for _ in range(4)]
    records = [
        [ids[0], b"cafe\xcc\x81-" + token_bytes, b"", b'comma, quote " and\nnewline ' + token_bytes],
        [ids[1], b"\xff" + token_bytes + b"\xfeend", "A\u030a".encode("utf-8"), b""],
        [ids[2], b"", "ありがとう-".encode("utf-8") + token_bytes, "ممتاز-".encode("utf-8") + token_bytes],
        [ids[3], b"", b"", b""],
    ]
    header = [b"id", b"review_2023_01", b"review_2023_02", b"review_2023_03"]
    raw = b",".join(header) + b"\n"
    for record in records:
        raw += b",".join(csv_quote_bytes(field) for field in record) + b"\n"

    with open(INPUT, "wb") as f:
        f.write(raw)
    run_cleaner()

    decoded_rows = list(csv.reader(io.StringIO(raw.decode("utf-8", "replace"), newline="")))
    expected = []
    for record in decoded_rows[1:]:
        for column, review in zip(decoded_rows[0][1:], record[1:]):
            if review != "":
                expected.append([record[0], column[len("review_"):], unicodedata.normalize("NFC", review)])

    assert os.path.isfile(OUTPUT), "The cleaner did not create cleaned_reviews.csv for the additional input."
    with open(OUTPUT, "r", encoding="utf-8", newline="") as f:
        actual_rows = list(csv.reader(f))

    assert actual_rows, "The generated CSV is empty."
    assert actual_rows[0] == ["id", "month", "review"], f"Incorrect header: {actual_rows[0]}"
    assert actual_rows[1:] == expected, f"Additional-input output mismatch.\nExpected: {expected!r}\nActual: {actual_rows[1:]!r}"
    for row in actual_rows[1:]:
        assert len(row) == 3, f"Output row does not have exactly three columns: {row!r}"
        assert unicodedata.is_normalized("NFC", row[2]), f"Review is not NFC normalized: {row[2]!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
