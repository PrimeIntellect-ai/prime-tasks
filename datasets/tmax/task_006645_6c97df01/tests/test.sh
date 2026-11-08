#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

SOURCE = "/home/user/compress_logs.c"
BINARY = "/home/user/compress_logs"
ARCHIVE = "/home/user/archive.rle.gz"
CHECKSUM = "/home/user/archive_checksum.txt"
EXPECTED_STREAM = "/home/user/active_logs/a.log\n4a4b2c\n/home/user/active_logs/b/c.log\n9x2x\n2y\n"


def test_compress_logs_c_exists():
    path = SOURCE
    assert os.path.isfile(path), f"Source file {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "#include" in content, f"{path} does not appear to be a valid C source file."


def test_archive_rle_gz_exists_and_valid():
    path = ARCHIVE
    assert os.path.isfile(path), f"Archive {path} is missing."

    try:
        with gzip.open(path, "rt", encoding="utf-8") as f:
            content = f.read()
    except Exception as e:
        pytest.fail(f"Failed to read {path} as a gzip file: {e}")

    assert content == EXPECTED_STREAM, f"Decompressed content of {path} does not match the expected RLE output."


def test_archive_checksum_txt():
    path = CHECKSUM
    assert os.path.isfile(path), f"Checksum file {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_md5 = hashlib.md5(EXPECTED_STREAM.encode("utf-8")).hexdigest()
    assert content.startswith(expected_md5), f"Checksum in {path} is incorrect. Expected {expected_md5}, got {content}"
    assert content == expected_md5, f"{path} must contain only the MD5 hash string."


def rle(data):
    output = bytearray()
    i = 0
    while i < len(data):
        if data[i] == 10:
            output.append(10)
            i += 1
            continue
        value = data[i]
        count = 1
        while i + count < len(data) and data[i + count] == value and count < 9:
            count += 1
        output.extend(str(count).encode("ascii"))
        output.append(value)
        i += count
    return bytes(output)


def expected_for(root, files):
    result = bytearray()
    selected = []
    for relative, data in files.items():
        if relative.endswith(".log"):
            selected.append((str(root / relative), data))
    for absolute, data in sorted(selected, key=lambda item: item[0]):
        result.extend(absolute.encode())
        result.extend(b"\n")
        result.extend(rle(data))
    return bytes(result)


def test_source_compiles_and_programs_work_on_dynamic_tree():
    assert os.path.isfile(BINARY), f"Compiled program {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Compiled program {BINARY} is not executable."

    with tempfile.TemporaryDirectory(prefix="compress_logs_verify_") as work:
        work_path = Path(work)
        rebuilt = work_path / "compress_logs_from_source"
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", str(rebuilt)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            "compress_logs.c failed to compile:\n"
            + compile_result.stderr.decode(errors="replace")
        )

        root = work_path / ("logs_" + secrets.token_hex(6))
        marker1 = secrets.choice(b"ABCDEFGHJKLMNPQRSTUVWXYZ")
        marker2 = secrets.choice(b"abcdefghjkmnpqrstuvwxyz")
        while marker2 == marker1:
            marker2 = secrets.choice(b"abcdefghjkmnpqrstuvwxyz")

        files = {
            "z/long.log": bytes([marker1]) * 19 + b"\n\n" + bytes([marker2]) * 10,
            "aa/deep/mixed.log": b"1122333\n" + bytes([marker2]) * 3 + b"!",
            "middle.log": bytes([marker1, marker1, marker2, marker2, marker1]) + b"\n",
            "aa/empty.log": b"",
            "z/ignored.txt": bytes([marker1]) * 30,
            "almost.log.bak": b"must not be included",
        }
        for relative, data in files.items():
            destination = root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)

        expected = expected_for(root, files)
        for program in (str(rebuilt), BINARY):
            result = subprocess.run(
                [program, str(root)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            assert result.returncode == 0, (
                f"{program} exited with status {result.returncode}: "
                + result.stderr.decode(errors="replace")
            )
            assert result.stdout == expected, (
                f"{program} did not recursively archive, sort, and RLE-encode "
                "the dynamic log tree as required."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
