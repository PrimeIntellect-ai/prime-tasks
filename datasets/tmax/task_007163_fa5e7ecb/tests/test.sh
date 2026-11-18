#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import struct
import subprocess
import tempfile
import pytest

MINIMAL_CRASH_BIN = "/home/user/data_parser/minimal_crash.bin"
FIXED_PARSER_C = "/home/user/data_parser/fixed_parser.c"
FIXED_PARSER_BIN = "/home/user/data_parser/fixed_parser"
TELEMETRY_BIN = "/home/user/data_parser/telemetry.bin"

VULNERABLE_SOURCE = r'''
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

void parse_telemetry(const uint8_t *data, size_t size) {
    size_t i = 0;
    while (i < size) {
        if (data[i] == 0xAA) {
            if (i + 4 >= size) {
                break;
            }
            uint32_t length = data[i+1] | (data[i+2] << 8) | (data[i+3] << 16) | (data[i+4] << 24);
            uint32_t checksum = 0;
            for (uint32_t j = 0; j < length; j++) {
                checksum += data[i + 5 + j];
            }
            printf("Block checksum: %u\n", checksum);
            i += 5 + length;
        } else {
            i++;
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buffer = malloc(size);
    fread(buffer, 1, size, f);
    fclose(f);
    parse_telemetry(buffer, size);
    free(buffer);
    return 0;
}
'''


def run_parser(executable, input_path, timeout=5):
    return subprocess.run(
        [executable, input_path],
        capture_output=True,
        timeout=timeout
    )


@pytest.fixture(scope="session")
def verifier_builds(tmp_path_factory):
    build_dir = tmp_path_factory.mktemp("builds")

    vulnerable_c = build_dir / "original_parser.c"
    vulnerable_bin = build_dir / "original_parser"
    vulnerable_c.write_text(VULNERABLE_SOURCE)
    subprocess.run(
        ["/usr/bin/gcc", "-O0", "-g", str(vulnerable_c), "-o", str(vulnerable_bin)],
        check=True,
        capture_output=True,
        text=True,
    )

    assert os.path.isfile(FIXED_PARSER_C), f"{FIXED_PARSER_C} does not exist."
    rebuilt_fixed = build_dir / "fixed_parser"
    subprocess.run(
        ["/usr/bin/gcc", "-O0", "-g", FIXED_PARSER_C, "-o", str(rebuilt_fixed)],
        check=True,
        capture_output=True,
        text=True,
    )
    return str(vulnerable_bin), str(rebuilt_fixed)


def test_minimal_crash_bin(verifier_builds, tmp_path):
    assert os.path.exists(MINIMAL_CRASH_BIN), f"{MINIMAL_CRASH_BIN} does not exist."
    with open(MINIMAL_CRASH_BIN, "rb") as f:
        content = f.read()

    expected_content = b"\xAA\xFF\xFF\xFF\xFF"
    assert content == expected_content, (
        f"minimal_crash.bin content is incorrect. "
        f"Expected {expected_content}, got {content}."
    )
    assert 0 < len(content) <= 5

    vulnerable_bin, _ = verifier_builds
    result = run_parser(vulnerable_bin, MINIMAL_CRASH_BIN)
    assert result.returncode == -signal.SIGSEGV, (
        f"minimal_crash.bin did not reproduce the original parser's segmentation fault; "
        f"return code was {result.returncode}."
    )

    # Delta-minimality: deleting any one byte must stop reproducing the crash.
    for index in range(len(content)):
        candidate = tmp_path / f"delete_{index}.bin"
        candidate.write_bytes(content[:index] + content[index + 1:])
        reduced_result = run_parser(vulnerable_bin, str(candidate))
        assert reduced_result.returncode != -signal.SIGSEGV, (
            f"Deleting byte {index} still reproduces the segmentation fault."
        )


def test_fixed_parser_exists():
    assert os.path.exists(FIXED_PARSER_C), f"{FIXED_PARSER_C} does not exist."
    assert os.path.isfile(FIXED_PARSER_C), f"{FIXED_PARSER_C} is not a regular file."
    assert os.path.exists(FIXED_PARSER_BIN), f"{FIXED_PARSER_BIN} does not exist."
    assert os.path.isfile(FIXED_PARSER_BIN), f"{FIXED_PARSER_BIN} is not a regular file."
    assert os.access(FIXED_PARSER_BIN, os.X_OK), f"{FIXED_PARSER_BIN} is not executable."
    with open(FIXED_PARSER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fixed_parser is not a compiled ELF executable."


def assert_corruption_result(executable, input_path):
    result = run_parser(executable, input_path)
    assert result.returncode == 2, f"Expected exit code 2, got {result.returncode}."
    assert result.stderr.decode(errors="replace").strip() == "ERROR: CORRUPTED INPUT", (
        "Expected stderr 'ERROR: CORRUPTED INPUT', "
        f"got '{result.stderr.decode(errors='replace')}'."
    )


def test_fixed_parser_minimal_crash():
    assert os.path.exists(FIXED_PARSER_BIN), "fixed_parser executable missing."
    assert os.path.exists(MINIMAL_CRASH_BIN), "minimal_crash.bin missing."
    assert_corruption_result(FIXED_PARSER_BIN, MINIMAL_CRASH_BIN)


def test_fixed_parser_telemetry_bin():
    assert os.path.exists(FIXED_PARSER_BIN), "fixed_parser executable missing."
    assert os.path.exists(TELEMETRY_BIN), "telemetry.bin missing."
    assert_corruption_result(FIXED_PARSER_BIN, TELEMETRY_BIN)


def test_rebuilt_source_handles_required_inputs(verifier_builds):
    _, rebuilt_fixed = verifier_builds
    assert_corruption_result(rebuilt_fixed, MINIMAL_CRASH_BIN)
    assert_corruption_result(rebuilt_fixed, TELEMETRY_BIN)


def test_submitted_and_rebuilt_parsers_on_derived_cases(verifier_builds, tmp_path):
    _, rebuilt_fixed = verifier_builds
    executables = [FIXED_PARSER_BIN, rebuilt_fixed]

    # Valid cases verify that the repaired program still implements the parser,
    # rather than merely returning the corruption error for every input.
    for case_index in range(6):
        data = bytearray()
        expected_lines = []
        data.extend(bytes((b if b != 0xAA else 0xAB) for b in secrets.token_bytes(case_index + 1)))
        for _ in range(1 + case_index % 3):
            payload = secrets.token_bytes(secrets.randbelow(24))
            data.append(0xAA)
            data.extend(struct.pack("<I", len(payload)))
            data.extend(payload)
            expected_lines.append(f"Block checksum: {sum(payload) & 0xffffffff}\n".encode())
            data.extend(b"\x01\x02")

        path = tmp_path / f"valid_{case_index}.bin"
        path.write_bytes(data)
        expected_stdout = b"".join(expected_lines)
        for executable in executables:
            result = run_parser(executable, str(path))
            assert result.returncode == 0, (
                f"{executable} rejected valid input with code {result.returncode}."
            )
            assert result.stderr == b"", f"{executable} wrote stderr for valid input."
            assert result.stdout == expected_stdout, (
                f"{executable} produced incorrect checksums for valid input."
            )

    # Generate corruption cases at verification time and derive their status from
    # the encoded length versus the actual payload size.
    for case_index in range(8):
        prefix = bytes((b if b != 0xAA else 0x55) for b in secrets.token_bytes(case_index))
        payload = secrets.token_bytes(secrets.randbelow(12))
        claimed_length = len(payload) + 1 + secrets.randbelow(10000)
        data = prefix + b"\xAA" + struct.pack("<I", claimed_length) + payload
        path = tmp_path / f"corrupt_{case_index}.bin"
        path.write_bytes(data)
        for executable in executables:
            assert_corruption_result(executable, str(path))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
