#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import re
import struct
import subprocess
import tempfile
from collections import Counter

LOG_DIR = "/home/user/raw_logs"
ARCHIVE_BIN = "/home/user/archive.bin"
ARCHIVER_C = "/home/user/archiver.c"
ARCHIVER = "/home/user/archiver"
USER_DICT = "/home/user/user_dict.csv"

EXPECTED_USERS = {105: "alice", 106: "bob", 107: "charlie"}
EXPECTED_USERS.update({uid: f"user{uid}" for uid in range(108, 201)})

EXPECTED_LOG_SEQUENCES = [
    [(1700000000, 105, "LOGIN"), (1700000005, 106, "DOWNLOAD")],
    [(1700000010, 105, "UPLOAD"), (1700000015, 107, "LOGOUT"),
     (1700000020, 999, "UNKNOWN_ACTION")],
]

ACTION_CODES = {
    "LOGIN": 0x01,
    "LOGOUT": 0x02,
    "DOWNLOAD": 0x03,
    "UPLOAD": 0x04,
}
LINE_RE = re.compile(r"^\[(\d+)\]\s+(\d+)\s+(\S+)\s*$")


def load_dictionary(path=USER_DICT):
    result = {}
    with open(path, "r", encoding="ascii") as f:
        for line_no, line in enumerate(f, 1):
            line = line.rstrip("\r\n")
            assert line, f"Blank line in user dictionary at line {line_no}"
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid dictionary row at line {line_no}: {line!r}"
            uid_text, username = parts
            assert uid_text.isdigit(), f"Invalid UID at line {line_no}: {uid_text!r}"
            assert username.isalnum(), f"Invalid username at line {line_no}: {username!r}"
            uid = int(uid_text)
            assert uid not in result, f"Duplicate UID in dictionary: {uid}"
            result[uid] = username
    return result


def read_log_sequences():
    sequences = []
    for name in os.listdir(LOG_DIR):
        if not name.endswith(".log"):
            continue
        path = os.path.join(LOG_DIR, name)
        assert os.path.isfile(path), f"Log entry is not a regular file: {path}"
        sequence = []
        with open(path, "r", encoding="ascii") as f:
            for line_no, line in enumerate(f, 1):
                match = LINE_RE.match(line)
                assert match, f"Malformed log line in {path}:{line_no}: {line!r}"
                sequence.append((int(match.group(1)), int(match.group(2)), match.group(3)))
        sequences.append(sequence)
    return sequences


def encode_record(timestamp, uid, action, users):
    username = users.get(uid, "UNKNOWN").encode("ascii")
    assert len(username) <= 16
    return struct.pack("<I", timestamp) + username.ljust(16, b"\0") + bytes([
        ACTION_CODES.get(action, 0xFF)
    ])


def possible_archives(sequences, users):
    # The instruction does not prescribe inter-file traversal order, so accept any
    # concatenation of whole files while requiring line order within each file.
    for ordering in itertools.permutations(sequences):
        yield b"".join(
            encode_record(timestamp, uid, action, users)
            for sequence in ordering
            for timestamp, uid, action in sequence
        )


def test_user_dict_csv_exists_and_contents():
    assert os.path.isfile(USER_DICT), f"User dictionary not found: {USER_DICT}"
    assert load_dictionary() == EXPECTED_USERS, "user_dict.csv does not match the Redis user_map"


def test_archive_bin_size_and_mmap():
    # Retain the original existence, line-count, exact-size, and source checks.
    assert os.path.isdir(LOG_DIR), f"Directory not found: {LOG_DIR}"

    sequences = read_log_sequences()
    assert sequences, f"No .log files found in {LOG_DIR}"
    total_lines = sum(len(sequence) for sequence in sequences)

    assert os.path.isfile(ARCHIVE_BIN), f"Output binary not found: {ARCHIVE_BIN}"
    expected_size = total_lines * 21
    actual_size = os.path.getsize(ARCHIVE_BIN)
    assert actual_size == expected_size, (
        f"Metric failed: Expected {expected_size} bytes (21 bytes per record for "
        f"{total_lines} records), got {actual_size} bytes."
    )

    assert os.path.isfile(ARCHIVER_C), f"Source code not found: {ARCHIVER_C}"
    with open(ARCHIVER_C, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert "mmap" in source, "Metric failed: Source code does not use mmap."

    # Ensure the extracted input is the complete supplied dataset rather than a
    # substituted set of files chosen merely to satisfy the size assertion.
    assert Counter(tuple(s) for s in sequences) == Counter(tuple(s) for s in EXPECTED_LOG_SEQUENCES), (
        "raw_logs does not contain the complete extracted source log data"
    )

    users = load_dictionary()
    with open(ARCHIVE_BIN, "rb") as f:
        actual = f.read()
    assert any(actual == expected for expected in possible_archives(sequences, users)), (
        "archive.bin has incorrect timestamps, usernames, action codes, padding, or record ordering"
    )


def run_controlled_test(program):
    with tempfile.TemporaryDirectory(prefix="archiver-test-") as temp_dir:
        logs = os.path.join(temp_dir, "logs")
        os.mkdir(logs)
        records = [
            (1, 42, "LOGIN"),
            (4294967294, 777, "LOGOUT"),
            (123, 999, "DOWNLOAD"),
            (124, 42, "UPLOAD"),
            (125, 42, "OTHER_ACTION"),
        ]
        with open(os.path.join(logs, "case.log"), "w", encoding="ascii") as f:
            for timestamp, uid, action in records:
                f.write(f"[{timestamp}] {uid} {action}\n")

        output = os.path.join(temp_dir, "output.bin")
        subprocess.run([program, logs, output], cwd="/home/user", check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        assert os.path.isfile(output), "Archiver did not create its requested output file"
        with open(output, "rb") as f:
            actual = f.read()
        users = {42: "abcdefghijklmnop", 777: "z"}
        expected = b"".join(encode_record(ts, uid, action, users)
                            for ts, uid, action in records)
        assert actual == expected, (
            "Archiver failed controlled records covering timestamp encoding, dictionary lookup, "
            "UNKNOWN users, all action mappings, padding, and line order"
        )


def test_archiver_is_executable_and_works_on_derived_inputs():
    assert os.path.isfile(ARCHIVER), f"Compiled program not found: {ARCHIVER}"
    assert os.access(ARCHIVER, os.X_OK), f"Compiled program is not executable: {ARCHIVER}"

    with open(USER_DICT, "rb") as f:
        original_dictionary = f.read()
    try:
        with open(USER_DICT, "wb") as f:
            f.write(b"42,abcdefghijklmnop\n777,z\n")

        # Exercise the submitted executable.
        run_controlled_test(ARCHIVER)

        # Independently compile and exercise the submitted source, preventing an
        # unrelated executable from being paired with decorative source code.
        with tempfile.TemporaryDirectory(prefix="compile-test-") as build_dir:
            rebuilt = os.path.join(build_dir, "archiver")
            subprocess.run(["gcc", "-O2", "-o", rebuilt, ARCHIVER_C], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            symbols = subprocess.run(["nm", "-D", rebuilt], check=True,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, timeout=10).stdout
            assert re.search(r"\bU\s+mmap(?:@|\b)", symbols), (
                "Compiled archiver does not actually reference the mmap function"
            )
            run_controlled_test(rebuilt)
    finally:
        with open(USER_DICT, "wb") as f:
            f.write(original_dictionary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
