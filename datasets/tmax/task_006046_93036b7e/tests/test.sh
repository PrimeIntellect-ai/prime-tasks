#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import struct
import subprocess
import pytest


def test_c_file_exists():
    """Test that the C source file exists."""
    assert os.path.isfile("/home/user/sanitize.c"), "/home/user/sanitize.c does not exist."


def test_clean_index_exists():
    """Test that the cleaned binary index exists."""
    assert os.path.isfile("/home/user/artifacts/index_clean.bin"), "/home/user/artifacts/index_clean.bin does not exist."


def test_temp_file_removed():
    """Test that the temporary file was successfully renamed/removed."""
    assert not os.path.exists("/home/user/artifacts/index_clean.bin.tmp"), "/home/user/artifacts/index_clean.bin.tmp still exists; atomic rename was likely not used."


def test_clean_index_size():
    """Test that the cleaned index size perfectly matches the original index size."""
    orig_path = "/home/user/artifacts/index.bin"
    clean_path = "/home/user/artifacts/index_clean.bin"

    assert os.path.isfile(orig_path), "Original index.bin is missing."
    orig_size = os.path.getsize(orig_path)
    clean_size = os.path.getsize(clean_path)

    assert orig_size == clean_size, f"Size mismatch: original index is {orig_size} bytes, clean index is {clean_size} bytes."


def test_clean_index_content():
    """Test that the content of the clean index has correctly sanitized paths."""
    with open("/home/user/artifacts/index_clean.bin", "rb") as f:
        data = f.read()

    assert data.startswith(b"ARTIFACT_v1\0"), "Header is incorrect in the clean index."

    assert b"bin/______etc/passwd" in data, "Sanitized path 'bin/______etc/passwd' not found in clean index."
    assert b"___config/system.yml" in data, "Sanitized path '___config/system.yml' not found in clean index."
    assert b"safe/___path/file" in data, "Sanitized path 'safe/___path/file' not found in clean index."

    assert b"docs/readme.txt" in data, "Untouched path 'docs/readme.txt' not found in clean index."
    assert b"scripts/install.sh" in data, "Untouched path 'scripts/install.sh' not found in clean index."

    assert b"../" not in data, "Found unsanitized '../' sequence in the clean index."


def test_sanitized_log_content():
    """Test that the sanitized.log file exists and contains the correct entries."""
    log_path = "/home/user/artifacts/sanitized.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        log_content = [line.strip() for line in f.readlines() if line.strip()]

    expected_logs = [
        "bin/../../etc/passwd -> bin/______etc/passwd",
        "../config/system.yml -> ___config/system.yml",
        "safe/../path/file -> safe/___path/file"
    ]

    for expected in expected_logs:
        assert expected in log_content, f"Missing expected log entry: '{expected}' in {log_path}"


def encode_index(records):
    result = bytearray(b"ARTIFACT_v1\0")
    for name, offset, size in records:
        result += struct.pack("<H", len(name))
        result += name
        result += struct.pack("<II", offset, size)
    return bytes(result)


def parse_index(data):
    assert data[:12] == b"ARTIFACT_v1\0", "Generated clean index has an invalid header"
    pos = 12
    records = []
    while pos < len(data):
        assert len(data) - pos >= 2, "Truncated name_len in clean index"
        name_len = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        assert len(data) - pos >= name_len + 8, "Truncated record in clean index"
        name = data[pos:pos + name_len]
        pos += name_len
        offset, size = struct.unpack_from("<II", data, pos)
        pos += 8
        records.append((name, offset, size))
    assert pos == len(data), "Clean index contains trailing malformed bytes"
    return records


def test_compile_and_execute_sanitizer_on_derived_inputs():
    """Compile and execute the submitted C implementation on non-fixed records."""
    executable = "/tmp/submitted_sanitize"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", "/home/user/sanitize.c", "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, "sanitize.c did not compile:\n" + compile_result.stderr

    rng = random.SystemRandom()
    alphabet = string.ascii_lowercase + string.digits
    token = "".join(rng.choice(alphabet) for _ in range(14)).encode("ascii")

    cases = [
        [
            (b"plain/" + token + b".dat", rng.randrange(0, 2**32), rng.randrange(0, 2**32)),
            (b"../" + token + b"/first", rng.randrange(0, 2**32), rng.randrange(0, 2**32)),
            (token + b"/../../double", rng.randrange(0, 2**32), rng.randrange(0, 2**32)),
            (b"middle../part../tail", rng.randrange(0, 2**32), rng.randrange(0, 2**32)),
            (b"..x/not-traversal", 0, 0xffffffff),
        ],
        [
            (b"../", 0xffffffff, 0),
            (b"alpha/beta", 17, 29),
            (b"x/../y/../z/../end", rng.randrange(0, 2**32), rng.randrange(0, 2**32)),
            (b"dots/.../remain", rng.randrange(0, 2**32), rng.randrange(0, 2**32)),
        ],
    ]

    base = "/home/user/artifacts"
    input_path = os.path.join(base, "index.bin")
    clean_path = os.path.join(base, "index_clean.bin")
    temp_path = os.path.join(base, "index_clean.bin.tmp")
    log_path = os.path.join(base, "sanitized.log")

    for case_number, records in enumerate(cases):
        original = encode_index(records)
        expected_records = [(name.replace(b"../", b"___"), offset, size)
                            for name, offset, size in records]
        expected_binary = encode_index(expected_records)
        sentinel = f"preexisting-log-line-{case_number}-{token.decode('ascii')}"
        expected_changes = [
            name.decode("ascii") + " -> " + name.replace(b"../", b"___").decode("ascii")
            for name, _, _ in records if b"../" in name
        ]

        with open(input_path, "wb") as f:
            f.write(original)
        for path in (clean_path, temp_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        with open(log_path, "w", encoding="ascii") as f:
            f.write(sentinel + "\n")

        run_result = subprocess.run(
            [executable],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert run_result.returncode == 0, (
            f"sanitizer failed on generated case {case_number}:\n{run_result.stderr}"
        )
        assert os.path.isfile(clean_path), "Executed sanitizer did not create index_clean.bin"
        assert not os.path.exists(temp_path), "Executed sanitizer left index_clean.bin.tmp behind"

        with open(clean_path, "rb") as f:
            actual_binary = f.read()
        actual_records = parse_index(actual_binary)
        assert actual_records == expected_records, (
            "Record names, offsets, sizes, or ordering were not preserved correctly"
        )
        assert actual_binary == expected_binary, "Clean index is not the exact required binary rewrite"
        assert len(actual_binary) == len(original), "Clean index size changed"

        assert os.path.isfile(log_path), "Executed sanitizer did not create sanitized.log"
        with open(log_path, "r", encoding="ascii") as f:
            actual_log = f.read().splitlines()
        assert actual_log == [sentinel] + expected_changes, (
            "sanitized.log was not appended with exactly one entry per modified filename"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
