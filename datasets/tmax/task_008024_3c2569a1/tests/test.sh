#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess

import pytest

PARSER = "/home/user/parser.go"
RESULT = "/home/user/result.log"
BINARY = "/tmp/parser_submission"


def test_result_log_exists_and_correct():
    path = "/home/user/result.log"
    assert os.path.isfile(path), f"File {path} does not exist. The Go program might not have been run or did not write to the correct file."

    with open(path, "r") as f:
        content = f.read()

    assert content == "CRITICAL", f"Expected content 'CRITICAL' in {path}, but got '{content}'."


def test_parser_go_fixes():
    path = "/home/user/parser.go"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert "os.Readfile" not in content, "The compiler bug (os.Readfile) is still present in parser.go."
    assert "os.ReadFile" in content, "The compiler bug was not correctly fixed to os.ReadFile."

    assert "6+length+1" not in content.replace(" ", ""), "The off-by-one bug (6+length+1) is still present in parser.go."


def run_and_check(input_path, expected):
    if os.path.lexists(RESULT):
        os.remove(RESULT)

    completed = subprocess.run(
        [BINARY, input_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"Compiled parser failed for {input_path} with exit code "
        f"{completed.returncode}. stderr: {completed.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(RESULT), "The parser did not create /home/user/result.log."
    with open(RESULT, "rb") as f:
        actual = f.read()
    assert actual == expected, f"Expected result bytes {expected!r}, got {actual!r}."


def test_parser_compiles_and_parses_payloads():
    build = subprocess.run(
        ["go", "build", "-o", BINARY, PARSER],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert build.returncode == 0, (
        "parser.go does not compile: " + build.stderr.decode(errors="replace")
    )

    run_and_check("/home/user/payload.bin", b"CRITICAL")

    for index, size in enumerate((1, 7, 19, 64)):
        payload = secrets.token_bytes(size)
        # Extra bytes ensure extraction is governed by the encoded length rather
        # than simply taking the remainder of the file.
        trailer = secrets.token_bytes(index + 1)
        encoded = b"GO" + struct.pack(">I", len(payload)) + payload + trailer
        path = f"/tmp/parser_case_{index}_{secrets.token_hex(8)}.bin"
        with open(path, "wb") as f:
            f.write(encoded)
        try:
            run_and_check(path, payload)
        finally:
            os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
