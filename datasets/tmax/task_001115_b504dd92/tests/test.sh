#!/bin/bash
mkdir -p /logs/verifier

build_ok=1
cd /home/user/packet_parser || build_ok=0
if [ "$build_ok" -eq 1 ]; then
    rm -f parser
    make parser || build_ok=0
fi
if [ "$build_ok" -eq 1 ] && [ ! -x /home/user/packet_parser/parser ]; then
    build_ok=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

import pytest

ROOT = "/home/user/packet_parser"
PARSER = os.path.join(ROOT, "parser")
SOURCE = os.path.join(ROOT, "parser.c")
CAPTURE = os.path.join(ROOT, "data", "capture.bin")
EXPECTED_KEY = "A1B2C3D4E5F67890"
SANITIZED = "/tmp/parser_sanitized"


def run_parser(binary, packet, key=EXPECTED_KEY, timeout=2):
    fd, path = tempfile.mkstemp(prefix="tlv_", suffix=".bin")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(packet)
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        env["UBSAN_OPTIONS"] = "halt_on_error=1"
        return subprocess.run(
            [binary, path, key],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env=env,
        )
    finally:
        os.unlink(path)


@pytest.fixture(scope="session", autouse=True)
def compile_and_validate_artifacts():
    assert os.path.isfile(SOURCE), f"Parser source not found at {SOURCE}"
    assert os.path.isfile(PARSER), f"Compiled parser not found at {PARSER}"
    assert os.access(PARSER, os.X_OK), "Compiled parser is not executable"
    with open(PARSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Makefile did not produce an ELF parser binary"

    result = subprocess.run(
        [
            "gcc", "-O0", "-g", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", "-o", SANITIZED, SOURCE,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"parser.c does not compile with sanitizers:\n{result.stderr}"


def test_secret_key_recovered():
    key_file = "/home/user/secret_key.txt"
    assert os.path.isfile(key_file), f"Secret key file not found at {key_file}"

    with open(key_file, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_KEY, f"Secret key file contains incorrect key: {content}"


def test_final_output_exists_and_correct():
    output_file = "/home/user/final_output.txt"
    assert os.path.isfile(output_file), f"Final output file not found at {output_file}"

    with open(output_file, "r") as f:
        content = f.read()

    assert "DEADBEEF" in content, "Final output does not contain the decrypted payload for Chunk 1 (DEADBEEF)"
    assert "1122" in content, "Final output does not contain the decrypted payload for Chunk 3 (1122)"

    idx1 = content.find("DEADBEEF")
    idx2 = content.find("1122")
    assert idx1 < idx2, "Decrypted payloads are not in the expected order in the output file"

    result = subprocess.run(
        [PARSER, CAPTURE, EXPECTED_KEY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=2,
    )
    assert result.returncode == 0, f"Compiled parser failed on capture.bin: {result.stderr}"
    assert result.stdout == content, "final_output.txt is not the actual output of the rebuilt parser on capture.bin"


def test_zero_length_record_does_not_hang_and_parsing_continues():
    rng = random.SystemRandom()
    key = EXPECTED_KEY.encode("ascii")
    packet = bytearray()
    expected_lines = []

    for index in range(5):
        if index == 2:
            packet.extend((0xFF, 0x00))

        record_type = rng.randrange(1, 0xF0)
        length = rng.randrange(1, 17)
        plaintext = bytes(rng.randrange(0, 256) for _ in range(length))
        encrypted = bytes(value ^ key[i % 16] for i, value in enumerate(plaintext))
        packet.extend((record_type, length))
        packet.extend(encrypted)
        expected_lines.append(f"Type: {record_type:02X}, Data: {plaintext.hex().upper()}")

    for binary in (PARSER, SANITIZED):
        result = run_parser(binary, bytes(packet))
        assert result.returncode == 0, f"{binary} failed on generated TLV input: {result.stderr}"
        position = -1
        for line in expected_lines:
            next_position = result.stdout.find(line, position + 1)
            assert next_position >= 0, f"{binary} did not parse records after malformed zero-length TLV"
            position = next_position


def test_truncated_headers_and_values_are_safely_rejected():
    malformed_packets = (
        b"\x44",
        b"\x01\x08\xAA\xBB",
        b"\xFF\x00",
    )
    for packet in malformed_packets:
        result = run_parser(SANITIZED, packet)
        assert result.returncode >= 0, "Parser crashed from a signal on malformed TLV input"
        combined = result.stdout + result.stderr
        assert "AddressSanitizer" not in combined, combined
        assert "runtime error:" not in combined, combined
TEST_EOF

if [ "$build_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
