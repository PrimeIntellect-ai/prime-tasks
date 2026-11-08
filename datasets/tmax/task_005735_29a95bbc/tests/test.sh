#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/processor_verifier.py
import csv
import os
import re
import secrets
import shutil
import subprocess

import pytest

SOURCE = "/home/user/processor.cpp"
BINARY = "/home/user/processor"
RAW = "/home/user/raw_chat.tsv"
PROCESSED = "/home/user/processed_chat.tsv"
SAMPLED = "/home/user/sampled_chat.tsv"


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def write_input(rows):
    remove_path(RAW)
    with open(RAW, "xb") as f:
        for msg_id, encoding, message in rows:
            assert b"\t" not in message and b"\n" not in message and b"\r" not in message
            f.write(msg_id.encode("ascii") + b"\t" + encoding.encode("ascii") + b"\t" + message + b"\n")


def compute_expected(rows):
    processed = []
    sampled = []
    stratum_counts = {"S": 0, "M": 0, "L": 0}
    window = []

    for msg_id, encoding, raw_message in rows:
        if encoding == "LATIN1":
            text = raw_message.decode("latin1")
        else:
            text = raw_message.decode("utf-8")

        tokens = [token for token in re.split(r"[ \.,!\?]", text) if token]
        lengths = [len(token.encode("utf-8")) for token in tokens]

        for length in lengths:
            window.append(length)
            if len(window) > 100:
                window.pop(0)

        token_count = len(lengths)
        if token_count <= 5:
            stratum = "S"
        elif token_count <= 15:
            stratum = "M"
        else:
            stratum = "L"

        average = 0.0 if not window else sum(window) / float(len(window))
        row = [msg_id, str(token_count), f"{average:.2f}", stratum]
        processed.append(row)

        if stratum_counts[stratum] < 2:
            sampled.append(row)
            stratum_counts[stratum] += 1

    return processed, sampled


def read_tsv(path):
    assert os.path.exists(path), f"Expected output file {path} is missing."
    assert os.path.isfile(path) and not os.path.islink(path), f"{path} must be a regular file."
    rows = []
    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        for row in reader:
            if row:
                rows.append(row)
    return rows


def run_processor(rows):
    write_input(rows)
    remove_path(PROCESSED)
    remove_path(SAMPLED)
    result = subprocess.run([BINARY], cwd="/home/user", stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=15)
    assert result.returncode == 0, (
        f"processor exited with status {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    return read_tsv(PROCESSED), read_tsv(SAMPLED)


def assert_rows(actual, expected, path):
    assert len(actual) == len(expected), (
        f"Row count mismatch in {path}. Expected {len(expected)}, got {len(actual)}."
    )
    for i, (actual_row, expected_row) in enumerate(zip(actual, expected)):
        assert actual_row == expected_row, (
            f"Row {i + 1} mismatch in {path}.\n"
            f"Expected: {expected_row}\nGot: {actual_row}"
        )


ORIGINAL_ROWS = [
    ("msg_01", "UTF-8", b"Hello, World!"),
    ("msg_02", "LATIN1", b"Caf\xe9 au lait."),
    ("msg_03", "UTF-8", b"This is a slightly longer message to test the medium stratum classification!"),
    ("msg_04", "UTF-8", b"Short text."),
    ("msg_05", "UTF-8", b"Another medium string with exactly eight words in it."),
    ("msg_06", "UTF-8", b"A B C D E F G H I J K L M N O P Q"),
    ("msg_07", "UTF-8", b"One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen"),
    ("msg_08", "LATIN1", b"El ni\xf1o corre r\xe1pido por el bosque verde."),
]


@pytest.fixture(scope="session", autouse=True)
def build_submission():
    assert os.path.isfile(SOURCE), f"Expected source file {SOURCE} is missing."
    assert os.path.getsize(SOURCE) > 0, f"Expected source file {SOURCE} is empty."
    assert os.path.isfile(BINARY), f"Expected compiled program {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Expected compiled program {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    rebuilt = "/home/user/.processor_verifier_build"
    remove_path(rebuilt)
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        "processor.cpp did not compile with the required command:\n" +
        result.stderr.decode("utf-8", errors="replace")
    )
    os.replace(rebuilt, BINARY)
    os.chmod(BINARY, 0o755)


@pytest.fixture(scope="module")
def original_results():
    expected = compute_expected(ORIGINAL_ROWS)
    actual = run_processor(ORIGINAL_ROWS)
    return actual, expected


def test_processed_chat_output(original_results):
    actual, expected = original_results
    assert_rows(actual[0], expected[0], PROCESSED)


def test_sampled_chat_output(original_results):
    actual, expected = original_results
    assert_rows(actual[1], expected[1], SAMPLED)


def make_random_rows():
    counts = [0, 1, 5, 6, 15, 16, 101, 3, 8, 18]
    separators = [b" ", b".", b",", b"!", b"?", b"..", b" ! "]
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    rows = []

    for row_index, count in enumerate(counts):
        encoding = "LATIN1" if row_index % 2 else "UTF-8"
        tokens = []
        for token_index in range(count):
            length = 1 + secrets.randbelow(12)
            token = "".join(secrets.choice(alphabet) for _ in range(length)).encode("ascii")
            if token_index % 4 == 0:
                token += b"\xe9" if encoding == "LATIN1" else "é".encode("utf-8")
            tokens.append(token)

        if not tokens:
            message = b" .,!?? "
        else:
            message = tokens[0]
            for token in tokens[1:]:
                message += secrets.choice(separators) + token
            message += secrets.choice([b"", b".", b"!!", b" ?"])

        rows.append((f"rnd_{row_index}_{secrets.token_hex(5)}", encoding, message))
    return rows


def test_fresh_runtime_input_and_rolling_window():
    rows = make_random_rows()
    expected_processed, expected_sampled = compute_expected(rows)
    actual_processed, actual_sampled = run_processor(rows)
    assert_rows(actual_processed, expected_processed, PROCESSED)
    assert_rows(actual_sampled, expected_sampled, SAMPLED)
PY_EOF

if python3 -m pytest /tmp/processor_verifier.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
