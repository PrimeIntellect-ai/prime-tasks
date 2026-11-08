#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile

REPO = "/home/user/db_triage"
SOURCE = os.path.join(REPO, "db_parser.c")
JOURNAL = os.path.join(REPO, "corrupted journal with spaces.bin")
KEY = b"SuperSecretK3y!!"


def output_lines(data):
    return [line.strip() for line in data.decode("utf-8").splitlines() if line.strip()]


def make_record(payload, checksum_delta=0):
    plain = payload.encode("utf-8")
    encrypted = bytes(byte ^ KEY[i % 16] for i, byte in enumerate(plain))
    checksum = (sum(plain) + checksum_delta) % 256
    return struct.pack("<II", 0xCAFEBABE, len(plain)) + encrypted + bytes([checksum])


def compile_parser(output_path):
    assert os.path.isfile(SOURCE), f"Missing C source: {SOURCE}"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", output_path],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"db_parser.c did not compile:\n{result.stderr}"
    assert os.path.isfile(output_path) and os.access(output_path, os.X_OK)


def run_parser(binary, journal):
    result = subprocess.run(
        [binary, journal, KEY.decode("ascii")],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Parser exited with {result.returncode}. stderr:\n"
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    return output_lines(result.stdout)


def test_recovered_data_exists_and_correct():
    file_path = "/home/user/recovered_data.txt"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. The task requires writing the recovered strings to this file."

    with open(file_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "USER_1=ALICE",
        "USER_2=BOB",
        "USER_3=CHARLIE",
        "USER_4=DAVE",
        "USER_5=EVE"
    ]

    assert lines == expected_lines, (
        f"The content of {file_path} does not match the expected recovered records.\n"
        f"Expected: {expected_lines}\n"
        f"Found: {lines}"
    )


def test_fixed_parser_recovers_original_and_generated_journals():
    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "db_parser")
        compile_parser(binary)

        expected_original = [
            "USER_1=ALICE",
            "USER_2=BOB",
            "USER_3=CHARLIE",
            "USER_4=DAVE",
            "USER_5=EVE",
        ]
        assert run_parser(binary, JOURNAL) == expected_original

        nonce = secrets.token_hex(8).upper()
        expected = [
            f"FIRST={nonce}",
            f"SECOND={nonce[::-1]}",
            f"THIRD={nonce[:8]}",
            f"FOURTH={nonce[8:]}",
            f"FIFTH={nonce.lower()}",
        ]

        journal_data = bytearray()
        journal_data += make_record(expected[0])
        journal_data += b"garbage before the next record\x00\xca\xfe"
        journal_data += make_record(expected[1])
        journal_data += make_record("INVALID_CHECKSUM_RECORD", checksum_delta=1)
        journal_data += make_record(expected[2])
        journal_data += struct.pack("<II", 0xCAFEBABE, 5000)
        journal_data += b"bad impossible length payload"
        journal_data += make_record(expected[3])
        journal_data += b"\x00\xff\xbe\xba\xfe"
        journal_data += make_record(expected[4])

        generated_journal = os.path.join(td, "generated corrupted journal with spaces.bin")
        with open(generated_journal, "wb") as f:
            f.write(journal_data)

        found = run_parser(binary, generated_journal)
        assert found == expected, (
            "The compiled parser did not recover valid records across bad magic, "
            f"a checksum failure, and an impossible length. Expected {expected}, found {found}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
