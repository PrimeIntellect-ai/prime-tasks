#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import secrets
import string
import struct
import subprocess

LOGS_PATH = "/home/user/recovered_logs.txt"
HASH_PATH = "/home/user/recovered_logs.sha256"
SOURCE_PATH = "/home/user/parser.c"
DATA_PATH = "/home/user/suspect_data.dat"
BINARY_PATH = "/tmp/parser_under_test"

EXPECTED_CONTENT = (
    "EVENT: START\n"
    "USER: root API_KEY=**************** action=login\n"
    "API_KEY=****************\n"
    "CONNECTION TERMINATED\n"
)


def test_recovered_logs_exists_and_correct():
    assert os.path.exists(LOGS_PATH), f"File {LOGS_PATH} is missing."
    assert os.path.isfile(LOGS_PATH), f"Path {LOGS_PATH} is not a file."

    with open(LOGS_PATH, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert actual_content.strip() == EXPECTED_CONTENT.strip(), (
        f"Content of {LOGS_PATH} does not match expected output.\n"
        f"Expected:\n{EXPECTED_CONTENT}\n"
        f"Actual:\n{actual_content}"
    )


def test_sha256_file_exists_and_correct():
    assert os.path.exists(HASH_PATH), f"File {HASH_PATH} is missing."
    assert os.path.isfile(HASH_PATH), f"Path {HASH_PATH} is not a file."

    with open(LOGS_PATH, "rb") as f:
        file_bytes = f.read()
    expected_hash = hashlib.sha256(file_bytes).hexdigest()

    with open(HASH_PATH, "r", encoding="utf-8") as f:
        hash_content = f.read().strip()

    assert expected_hash in hash_content, (
        f"The SHA-256 hash in {HASH_PATH} does not match the actual hash of {LOGS_PATH}.\n"
        f"Expected hash: {expected_hash}"
    )


def test_c_source_code_exists():
    assert os.path.exists(SOURCE_PATH), f"C source file {SOURCE_PATH} is missing."
    assert os.path.isfile(SOURCE_PATH), f"Path {SOURCE_PATH} is not a file."


def make_frame(payload, bad_checksum=False):
    checksum = 0
    for byte in payload:
        checksum ^= byte
    if bad_checksum:
        checksum ^= 1
    return b"\xBE\xEF" + struct.pack("<H", len(payload)) + payload + bytes([checksum])


def safe_garbage(length):
    # Excluding 0xBE ensures the random separators cannot accidentally contain magic.
    return bytes(random.randrange(0, 0xBE) for _ in range(length))


def test_parser_compiles_and_processes_original_and_generated_dumps():
    subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE_PATH, "-o", BINARY_PATH],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK)

    with open(DATA_PATH, "rb") as f:
        original_dump = f.read()
    with open(LOGS_PATH, "rb") as f:
        saved_logs = f.read()

    try:
        original_run = subprocess.run(
            [BINARY_PATH],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert original_run.stdout == EXPECTED_CONTENT.encode("ascii"), (
            "The compiled parser did not produce the required output for the original dump."
        )
        assert saved_logs == original_run.stdout, (
            "recovered_logs.txt is not the exact output produced by the compiled parser."
        )

        alphabet = string.ascii_letters + string.digits
        for trial in range(3):
            secret = "".join(secrets.choice(alphabet) for _ in range(16))
            event_id = secrets.token_hex(10)
            ordinary = f"EVENT-{trial}: {event_id}".encode("ascii")
            sensitive = f"USER API_KEY={secret} action=read".encode("ascii")
            short_key = b"API_KEY=Only15Chars1234 remains"
            final_key = f"API_KEY={secret}".encode("ascii")
            newline_payload = f"LINE-{event_id}\n".encode("ascii")
            invalid_payload = f"INVALID-{event_id}".encode("ascii")

            dump = b"".join([
                safe_garbage(11 + trial),
                make_frame(ordinary),
                safe_garbage(7),
                make_frame(invalid_payload, bad_checksum=True),
                make_frame(sensitive),
                b"\xBE\x00\xEF",
                make_frame(short_key),
                make_frame(newline_payload),
                safe_garbage(5),
                make_frame(final_key),
                b"\xBE\xEF\x20",  # truncated frame header
            ])

            expected = b"".join([
                ordinary + b"\n",
                f"USER API_KEY={'*' * 16} action=read\n".encode("ascii"),
                short_key + b"\n",
                newline_payload,
                f"API_KEY={'*' * 16}\n".encode("ascii"),
            ])

            with open(DATA_PATH, "wb") as f:
                f.write(dump)

            result = subprocess.run(
                [BINARY_PATH],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.stdout == expected, (
                f"Parser output was incorrect on generated dump {trial}.\n"
                f"Expected: {expected!r}\nActual: {result.stdout!r}"
            )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_dump)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
