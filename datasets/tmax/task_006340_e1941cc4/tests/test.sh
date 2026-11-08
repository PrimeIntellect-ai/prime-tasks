#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile


def test_merged_bin_correct():
    merged_path = "/home/user/merged.bin"
    assert os.path.isfile(merged_path), f"{merged_path} does not exist."

    fragments = [
        "/home/user/backup_drive/folder2/chunk_A.frag",
        "/home/user/backup_drive/folder1/subfolder/chunk_B.frag",
        "/home/user/backup_drive/chunk_C.frag"
    ]

    expected_bytes = b""
    for frag in fragments:
        if os.path.isfile(frag):
            with open(frag, "rb") as f:
                expected_bytes += f.read()

    with open(merged_path, "rb") as f:
        actual_bytes = f.read()

    assert actual_bytes == expected_bytes, "The contents of merged.bin do not match the expected concatenated fragments in alphabetical order."


def test_parser_c_exists():
    parser_path = "/home/user/parser.c"
    assert os.path.isfile(parser_path), f"{parser_path} does not exist."


def test_parser_compiles_and_parses_dynamic_binary():
    parser_path = "/home/user/parser.c"
    merged_path = "/home/user/merged.bin"
    assert os.path.isfile(parser_path), f"{parser_path} does not exist."
    assert os.path.isfile(merged_path), f"{merged_path} does not exist."

    nonce = secrets.token_hex(16).encode("ascii")
    entries = [
        b"Dynamic entry " + nonce + b"\nStatus: OK\n",
        b"Second record\nStatus: CRITICAL\nNonce: " + nonce[::-1] + b"\nMore details here.\n",
        b"Final " + nonce[:11] + b" record\n",
    ]
    dynamic_binary = b"".join(struct.pack("<I", len(entry)) + entry for entry in entries)
    expected_output = b"".join(entries)

    with open(merged_path, "rb") as f:
        original_merged = f.read()

    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "parser")
        build = subprocess.run(
            ["/usr/bin/gcc", "-std=c11", parser_path, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert build.returncode == 0, "parser.c failed to compile:\n" + build.stderr.decode("utf-8", "replace")

        try:
            with open(merged_path, "wb") as f:
                f.write(dynamic_binary)

            run = subprocess.run(
                [executable],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert run.returncode == 0, "Compiled parser exited unsuccessfully:\n" + run.stderr.decode("utf-8", "replace")
            assert run.stdout == expected_output, "Compiled parser did not correctly decode the dynamically generated length-prefixed records."
        finally:
            with open(merged_path, "wb") as f:
                f.write(original_merged)


def test_critical_logs_correct():
    logs_path = "/home/user/critical_logs.txt"
    assert os.path.isfile(logs_path), f"{logs_path} does not exist."

    with open(logs_path, "r") as f:
        content = f.read()

    parts = [p.strip() for p in content.split("---")]
    parts = [p for p in parts if p]

    expected_1 = "Log Entry 2\nStatus: CRITICAL\nDatabase connection lost.\nRetrying..."
    expected_2 = "Log Entry 4\nStatus: CRITICAL\nDisk failure detected on /dev/sda1.\nImmediate action required."

    assert len(parts) == 2, f"Expected exactly 2 CRITICAL log entries separated by '---', found {len(parts)}."

    found_1 = any(expected_1 in p for p in parts)
    found_2 = any(expected_2 in p for p in parts)

    assert found_1, "The first expected CRITICAL log entry (Log Entry 2) was not found or is incomplete."
    assert found_2, "The second expected CRITICAL log entry (Log Entry 4) was not found or is incomplete."

    expected_exact = expected_1 + "\n---\n" + expected_2 + "\n"
    assert content == expected_exact, "critical_logs.txt must contain only the two complete matching records, separated by a single line containing exactly '---'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
