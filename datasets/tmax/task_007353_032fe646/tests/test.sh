#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import pytest


def test_sanitize_c_exists():
    """Verify that the C source code file exists."""
    file_path = "/home/user/sanitize.c"
    assert os.path.isfile(file_path), f"C source file {file_path} is missing."


def test_sanitize_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    file_path = "/home/user/sanitize"
    assert os.path.isfile(file_path), f"Compiled executable {file_path} is missing."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {file_path} is not a compiled ELF executable."


def expected_sanitize(data):
    inside_quotes = False
    output = bytearray()
    for byte in data:
        if byte == ord('"'):
            inside_quotes = not inside_quotes
            output.append(byte)
        elif byte == ord('\n') and inside_quotes:
            output.append(ord(' '))
        else:
            output.append(byte)
    return bytes(output)


def make_random_input():
    alphabet = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,{}[]: _-\r\n"

    def random_chunk(length):
        random_bytes = secrets.token_bytes(length)
        return bytes(alphabet[value % len(alphabet)] for value in random_bytes)

    pieces = [random_chunk(97)]
    for _ in range(25):
        pieces.extend((b'"', random_chunk(40 + secrets.randbelow(120)), b'"', random_chunk(20)))
    return b"".join(pieces)


def run_and_check(program, payload):
    result = subprocess.run(
        [program], input=payload, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5, check=False
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}. Stderr: {result.stderr!r}"
    )
    assert result.stdout == expected_sanitize(payload), (
        f"{program} produced incorrect sanitizer output"
    )


def test_sanitizer_behavior_and_source():
    """Compile the submitted source and exercise both it and the submitted binary."""
    rebuilt = "/tmp/sanitize_rebuilt"
    compilation = subprocess.run(
        ["gcc", "/home/user/sanitize.c", "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False
    )
    assert compilation.returncode == 0, (
        "sanitize.c did not compile successfully:\n" +
        compilation.stderr.decode("utf-8", errors="replace")
    )

    payloads = [
        b'plain\ntext\n',
        b'before,"line one\nline two\nline three",after\n',
        b'"\n"\noutside\n"inside\nagain"',
        b'a,"x\r\ny",z\r\n',
        make_random_input(),
        make_random_input(),
    ]
    for program in ("/home/user/sanitize", rebuilt):
        for payload in payloads:
            run_and_check(program, payload)

    with open("/home/user/config_changes.csv", "rb") as f:
        run_and_check("/home/user/sanitize", f.read())


def test_author_stats_csv():
    """Verify the final author_stats.csv has the correct content and formatting."""
    file_path = "/home/user/author_stats.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    expected_content = "asmith,2\nbwayne,1\ncjones,1\njdoe,2\n"

    with open(file_path, "r") as f:
        content = f.read()

    # Normalize line endings just in case, but require exact match
    content_normalized = content.replace("\r\n", "\n")
    if not content_normalized.endswith("\n"):
        content_normalized += "\n"

    assert content_normalized == expected_content, (
        f"Content of {file_path} does not match expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content_normalized}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
