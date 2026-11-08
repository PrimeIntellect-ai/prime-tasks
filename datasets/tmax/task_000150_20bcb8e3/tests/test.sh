#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import struct
import subprocess
import tempfile
import uuid
import zlib

import pytest

EXECUTABLE = "/home/user/sanitiser"
SOURCE = "/home/user/sanitiser.go"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"


def run_tool(executable, *args):
    return subprocess.run(
        [executable, *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


@pytest.fixture(scope="session")
def rebuilt_executable(tmp_path_factory):
    output = tmp_path_factory.mktemp("go-build") / "sanitiser"
    result = subprocess.run(
        ["go", "build", "-o", str(output), SOURCE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Go source failed to compile:\n{result.stderr}"
    assert output.is_file() and os.access(output, os.X_OK)
    return str(output)


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile the Go program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_go_source_exists_and_binary_is_go(rebuilt_executable):
    assert os.path.isfile(SOURCE), f"Go source {SOURCE} does not exist."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Submitted executable is not an ELF binary."
    result = subprocess.run(
        ["go", "version", "-m", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0 and "go1" in result.stdout, "Submitted executable is not a Go binary."


def test_clean_corpus_accepted():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*"))
    assert len(clean_files) > 0, f"No files found in {CLEAN_DIR}."

    failed_files = []
    for filepath in clean_files:
        result = run_tool(EXECUTABLE, filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (non-zero exit code). Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*"))
    assert len(evil_files) > 0, f"No files found in {EVIL_DIR}."

    failed_files = []
    for filepath in evil_files:
        result = run_tool(EXECUTABLE, filepath)
        if result.returncode == 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files incorrectly bypassed the sanitiser (zero exit code). Offending files: {', '.join(failed_files)}")


def raw_deflate(data):
    compressor = zlib.compressobj(level=6, wbits=-zlib.MAX_WBITS)
    return compressor.compress(data) + compressor.flush()


def archive(data, magic=b"KAZOO", crc=None, compressed=None):
    if compressed is None:
        compressed = raw_deflate(data)
    if crc is None:
        crc = zlib.crc32(data) & 0xffffffff
    return magic + compressed + struct.pack(">I", crc)


def make_dynamic_cases(directory):
    nonce = os.urandom(32).hex().encode()
    valid_payloads = [
        b"",
        b"a",
        b"ordinary log line\n" + nonce,
        (b"line with spaces and numbers 12345\n" + nonce + b"\n") * 30,
        b"drop_table is not the exact blacklist token\n" + nonce,
        "Unicode log: café 世界\n".encode("utf-8") + nonce,
    ]

    cases = []
    for data in valid_payloads:
        cases.append((archive(data), 0))

    base = b"runtime-generated log payload\n" + nonce * 4
    good_compressed = raw_deflate(base)
    good_crc = zlib.crc32(base) & 0xffffffff

    cases.extend([
        (archive(base, magic=b"XAZOO"), 1),
        (archive(base, magic=b"KAZO\x00"), 1),
        (archive(base, crc=(good_crc + 1) & 0xffffffff), 1),
        (b"KAZOO" + good_compressed + struct.pack("<I", good_crc), 1),
        (archive(b"prefix-" + nonce + b"-DROP_TABLE-suffix"), 1),
        (archive(b"DROP_TABLE"), 1),
        (b"KAZOO" + good_compressed[:max(1, len(good_compressed) // 2)] + struct.pack(">I", good_crc), 1),
        (b"KAZOO\xff\xff\xff\xff" + struct.pack(">I", good_crc), 1),
        (b"", 1),
        (b"KAZOO", 1),
        (b"KAZOO\x03\x00\x00\x00", 1),
    ])

    random.SystemRandom().shuffle(cases)
    written = []
    for contents, expected in cases:
        path = os.path.join(directory, uuid.uuid4().hex)
        with open(path, "wb") as f:
            f.write(contents)
        written.append((path, expected))
    return written


def test_runtime_generated_mixed_archives(rebuilt_executable):
    with tempfile.TemporaryDirectory(prefix="archive-check-") as directory:
        cases = make_dynamic_cases(directory)
        for executable in (EXECUTABLE, rebuilt_executable):
            for path, expected in cases:
                result = run_tool(executable, path)
                assert result.returncode == expected, (
                    f"{executable} returned {result.returncode}, expected {expected}, "
                    f"for runtime-generated archive {os.path.basename(path)}. "
                    f"stderr={result.stderr[:500]!r}"
                )


def test_exactly_one_argument_required(rebuilt_executable):
    with tempfile.TemporaryDirectory(prefix="argument-check-") as directory:
        valid_path = os.path.join(directory, uuid.uuid4().hex)
        with open(valid_path, "wb") as f:
            f.write(archive(b"valid argument test " + os.urandom(16).hex().encode()))

        for executable in (EXECUTABLE, rebuilt_executable):
            assert run_tool(executable).returncode == 1, "No-argument invocation must exit with code 1."
            assert run_tool(executable, valid_path, valid_path).returncode == 1, "Two-argument invocation must exit with code 1."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
