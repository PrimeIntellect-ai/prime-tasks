#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import resource
import secrets
import shutil
import string
import struct
import subprocess
import tempfile

import pytest

WORKSPACE = "/home/user/ticket_8492"


def expected_recovery_from_wal(data, require_trigger=False):
    offset = 0
    output = bytearray()
    found_trigger = False

    while offset < len(data):
        if offset + 2 >= len(data):
            break
        record_type = data[offset]
        length = data[offset + 1] | (data[offset + 2] << 8)
        if length == 0:
            if record_type == 0:
                found_trigger = True
            break
        if length > len(data) - offset - 3:
            break
        payload = data[offset + 3:offset + 3 + length]
        if record_type != 0:
            output.extend(b"Type: " + bytes([record_type]) + b" Payload: " + payload + b"\n")
        offset += 3 + length

    if require_trigger:
        assert found_trigger, "test_corrupt.wal does not contain a reachable type-0, zero-length record that triggers the original bug"
    return bytes(output)


def test_recovered_txt_contents():
    recovered_path = os.path.join(WORKSPACE, "recovered.txt")
    assert os.path.isfile(recovered_path), f"Expected file {recovered_path} does not exist. Did you run the daemon?"

    with open(recovered_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Type: A Payload: TEST",
        "Type: B Payload: OK"
    ]
    assert lines == expected_lines, f"Contents of recovered.txt do not match the expected output. Got: {lines}"


def test_regression_test_script_exists_and_executable():
    script_path = os.path.join(WORKSPACE, "regression_test.sh")
    assert os.path.isfile(script_path), f"Regression test script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Regression test script {script_path} is not executable."


def test_regression_test_script_success_on_fixed_code():
    script_path = os.path.join(WORKSPACE, "regression_test.sh")
    daemon_path = os.path.join(WORKSPACE, "wal_daemon")
    corrupt_path = os.path.join(WORKSPACE, "test_corrupt.wal")
    recovered_path = os.path.join(WORKSPACE, "recovered.txt")

    for path in (daemon_path, corrupt_path, recovered_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run([script_path], cwd=WORKSPACE, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"regression_test.sh failed (exit code {result.returncode}) on the fixed code. Output:\n{result.stdout}\n{result.stderr}"

    assert os.path.isfile(daemon_path) and os.access(daemon_path, os.X_OK), "regression_test.sh did not compile an executable wal_daemon"
    with open(daemon_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "wal_daemon produced by regression_test.sh is not a compiled ELF executable"
    assert os.path.isfile(corrupt_path), "regression_test.sh did not create test_corrupt.wal"
    with open(corrupt_path, "rb") as f:
        corrupt_data = f.read()
    expected = expected_recovery_from_wal(corrupt_data, require_trigger=True)
    assert os.path.isfile(recovered_path), "The regression daemon run did not produce recovered.txt"
    with open(recovered_path, "rb") as f:
        actual = f.read()
    assert actual == expected, "The regression script's daemon run did not recover exactly the records before its corruption marker"


def test_regression_test_script_fails_on_buggy_code():
    script_path = os.path.join(WORKSPACE, "regression_test.sh")
    cpp_path = os.path.join(WORKSPACE, "wal_parser.cpp")
    original = open(cpp_path, "rb").read()
    nonce = secrets.token_hex(12)

    buggy_code = f'''#include "wal_parser.h"
#include <fstream>
#include <iterator>

// randomized verifier fixture: {nonce}
std::vector<Record> WalParser::parse(const std::string& path) {{
    std::ifstream input(path, std::ios::binary);
    std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    std::vector<Record> result;
    if (bytes.size() != 0) parse_record(bytes, 0, result);
    return result;
}}

void WalParser::parse_record(const std::vector<unsigned char>& bytes, size_t pos, std::vector<Record>& out) {{
    if (pos >= bytes.size() || pos + 2 >= bytes.size()) return;
    char kind = static_cast<char>(bytes[pos]);
    unsigned int count = static_cast<unsigned int>(bytes[pos + 1]) |
                         (static_cast<unsigned int>(bytes[pos + 2]) << 8);
    if (count > bytes.size() - pos - 3) return;
    if (kind != '\\0') {{
        out.push_back({{kind, std::string(bytes.begin() + pos + 3, bytes.begin() + pos + 3 + count)}});
    }}
    if (count == 0 && kind == '\\0') {{
        parse_record(bytes, pos, out);
        return;
    }}
    parse_record(bytes, pos + 3 + count, out);
}}
'''

    try:
        with open(cpp_path, "w") as f:
            f.write(buggy_code)

        def limit_child():
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
            resource.setrlimit(resource.RLIMIT_STACK, (1024 * 1024, 1024 * 1024))

        try:
            result = subprocess.run(
                [script_path], cwd=WORKSPACE, capture_output=True, text=True,
                timeout=5, preexec_fn=limit_child
            )
            assert result.returncode != 0, "regression_test.sh should return a non-zero exit code when the daemon crashes, but it returned 0."
        except subprocess.TimeoutExpired:
            pytest.fail("regression_test.sh timed out. It should run the daemon and return a non-zero exit code upon failure, but it hung.")
    finally:
        with open(cpp_path, "wb") as f:
            f.write(original)
        subprocess.run(["make"], cwd=WORKSPACE, capture_output=True)


def test_submitted_parser_on_hidden_wals():
    for name in ("main.cpp", "wal_parser.cpp", "wal_parser.h"):
        path = os.path.join(WORKSPACE, name)
        assert os.path.isfile(path), f"Missing required source file: {path}"

    with tempfile.TemporaryDirectory(prefix="ticket8492_verify_") as tempdir:
        daemon = os.path.join(tempdir, "wal_daemon")
        build = subprocess.run(
            ["g++", "-std=c++17", "-g", "-O0", "-o", daemon,
             os.path.join(WORKSPACE, "main.cpp"), os.path.join(WORKSPACE, "wal_parser.cpp")],
            cwd=WORKSPACE, capture_output=True, text=True, timeout=20
        )
        assert build.returncode == 0, f"Submitted daemon source does not compile:\n{build.stdout}\n{build.stderr}"

        rng = random.SystemRandom()
        alphabet = string.ascii_letters + string.digits
        for case_number in range(5):
            wal = bytearray()
            expected = bytearray()
            valid_count = 0 if case_number == 0 else rng.randint(1, 5)
            for _ in range(valid_count):
                record_type = rng.choice(string.ascii_uppercase).encode("ascii")
                payload = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 24))).encode("ascii")
                wal.extend(record_type + struct.pack("<H", len(payload)) + payload)
                expected.extend(b"Type: " + record_type + b" Payload: " + payload + b"\n")

            # A zero length is invalid regardless of whether its type byte is zero.
            corrupt_type = 0 if case_number % 2 == 0 else ord(rng.choice(string.ascii_uppercase))
            wal.extend(bytes([corrupt_type, 0, 0]))

            # These valid-looking records occur after corruption and must be skipped.
            trailing_payload = secrets.token_hex(8).encode("ascii")
            wal.extend(b"Z" + struct.pack("<H", len(trailing_payload)) + trailing_payload)

            wal_path = os.path.join(tempdir, f"hidden_{case_number}_{secrets.token_hex(4)}.wal")
            with open(wal_path, "wb") as f:
                f.write(wal)
            recovered = os.path.join(tempdir, "recovered.txt")
            try:
                os.remove(recovered)
            except FileNotFoundError:
                pass

            try:
                run = subprocess.run([daemon, wal_path], cwd=tempdir, capture_output=True, timeout=4)
            except subprocess.TimeoutExpired:
                pytest.fail("wal_daemon hung on a hidden WAL containing a zero-length record")
            assert run.returncode == 0, f"wal_daemon failed on hidden corrupted WAL with exit code {run.returncode}"
            assert os.path.isfile(recovered), "wal_daemon did not produce recovered.txt for a hidden WAL"
            with open(recovered, "rb") as f:
                actual = f.read()
            assert actual == bytes(expected), "Parser did not stop at the zero-length record while preserving exactly the preceding records"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
