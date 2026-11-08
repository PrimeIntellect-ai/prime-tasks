#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import struct
import subprocess
import tempfile

BASE_DIR = "/home/user/malware_analysis"
DECODER_BIN = os.path.join(BASE_DIR, "decoder")
CRASH_BIN = os.path.join(BASE_DIR, "crash.bin")
REPORT_FILE = os.path.join(BASE_DIR, "report.txt")
SOURCE_FILE = os.path.join(BASE_DIR, "decoder.cpp")
UTILS_FILE = os.path.join(BASE_DIR, "utils.cpp")
AUDIT_BIN = os.path.join(tempfile.gettempdir(), "decoder_source_audit")


def run_decoder(binary, data):
    fd, path = tempfile.mkstemp(prefix="payload_", suffix=".bin")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        return subprocess.run(
            [binary, path], cwd=BASE_DIR, capture_output=True, timeout=5
        )
    finally:
        os.unlink(path)


def assert_elf_with_decoder_symbol(path):
    assert os.path.isfile(path), f"Missing executable: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary"
    symbols = subprocess.run(
        ["nm", "-C", path], capture_output=True, text=True, timeout=5
    )
    assert symbols.returncode == 0, f"Could not inspect symbols in {path}: {symbols.stderr}"
    assert "decode_payload(char const*, int)" in symbols.stdout, (
        f"{path} does not contain the required decode_payload implementation"
    )


def test_makefile_compilation():
    subprocess.run(["make", "clean"], cwd=BASE_DIR, capture_output=True)
    result = subprocess.run(["make"], cwd=BASE_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"make failed. stderr: {result.stderr}"
    assert not re.search(r"\bwarning:", result.stdout + result.stderr, re.IGNORECASE), (
        f"make produced compiler warnings:\n{result.stdout}{result.stderr}"
    )
    assert_elf_with_decoder_symbol(DECODER_BIN)


def test_sources_compile_cleanly_and_link_required_implementation():
    result = subprocess.run(
        ["g++", "-std=c++17", "-g", "-Wall", "-Werror", "-o", AUDIT_BIN,
         SOURCE_FILE, UTILS_FILE],
        cwd=BASE_DIR, capture_output=True, text=True
    )
    assert result.returncode == 0, (
        "decoder.cpp and utils.cpp do not compile and link cleanly with warnings treated "
        f"as errors. stdout: {result.stdout} stderr: {result.stderr}"
    )
    assert_elf_with_decoder_symbol(AUDIT_BIN)


def expected_cases():
    rng = random.SystemRandom()
    cases = []

    # Inputs shorter than the three-byte header are invalid.
    cases.extend([(b"", 255), (b"A", 255), (b"AB", 255)])

    # Negative signed-short lengths must be rejected before conversion to size_t.
    for length in (-1, -2, -127, -32768):
        cases.append((bytes([rng.randrange(256)]) + struct.pack("<h", length) + os.urandom(rng.randrange(0, 24)), 255))

    # Valid payloads, including both buffer boundaries.
    for length in [0, 1, 2, 31, 255, 1023, 1024]:
        cases.append((bytes([rng.randrange(256)]) + struct.pack("<h", length) + os.urandom(length), 0))
    for _ in range(12):
        length = rng.randrange(0, 1025)
        trailing = rng.randrange(0, 12)
        cases.append((bytes([rng.randrange(256)]) + struct.pack("<h", length) + os.urandom(length + trailing), 0))

    # Declared lengths beyond the available input are invalid.
    for _ in range(12):
        available = rng.randrange(0, 700)
        length = rng.randrange(available + 1, min(1024, available + 250) + 1)
        cases.append((bytes([rng.randrange(256)]) + struct.pack("<h", length) + os.urandom(available), 255))

    # Even with enough input bytes, lengths exceeding the local 1024-byte buffer are invalid.
    for length in [1025, 1026, 1500, 4096, 32767]:
        cases.append((bytes([rng.randrange(256)]) + struct.pack("<h", length) + os.urandom(length), 255))

    rng.shuffle(cases)
    return cases


def test_decoder_behavior_from_make_and_sources():
    assert os.path.isfile(CRASH_BIN), "crash.bin is missing"
    with open(CRASH_BIN, "rb") as f:
        assert f.read() == b"\x01\xff\xffA", "crash.bin was modified"

    for binary in (DECODER_BIN, AUDIT_BIN):
        crash = subprocess.run([binary, CRASH_BIN], cwd=BASE_DIR, capture_output=True, timeout=5)
        assert crash.returncode != 139, "The decoder still segfaults on crash.bin"
        assert crash.returncode == 255, f"Expected 255 for crash.bin, got {crash.returncode}"
        assert crash.stdout == b"" and crash.stderr == b"", (
            "decoder must not print crash output for crash.bin"
        )

        for data, expected in expected_cases():
            result = run_decoder(binary, data)
            assert result.returncode == expected, (
                f"Wrong result for generated payload of size {len(data)}: "
                f"expected {expected}, got {result.returncode}"
            )


def test_report_content():
    assert os.path.isfile(REPORT_FILE), f"Missing report file: {REPORT_FILE}"
    with open(REPORT_FILE, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 2, "report.txt must contain exactly two lines"
    assert lines[0].strip() == "20", f"Expected crash line 20, got {lines[0]!r}"
    line2 = lines[1].strip().lower()
    valid_keywords = ["sign", "integer", "negative"]
    assert any(keyword in line2 for keyword in valid_keywords), (
        f"Report does not identify the underlying data type issue: {lines[1]!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
