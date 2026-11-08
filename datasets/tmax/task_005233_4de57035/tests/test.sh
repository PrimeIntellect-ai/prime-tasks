#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import gzip
import re
from functools import lru_cache

ARCHIVE_DIR = "/home/user/archive"
RAW_LOGS_DIR = "/home/user/raw_logs"
CHUNK_RE = re.compile(r"prod_logs\.gz\.part-[a-z]{2}\Z")
IP_PATTERN = re.compile(r"IP:\s*\d+\.\d+\.\d+\.\d+")


def get_chunks():
    return sorted(glob.glob(os.path.join(ARCHIVE_DIR, "prod_logs.gz.part-*")))


def test_archive_directory_and_chunks():
    assert os.path.isdir(ARCHIVE_DIR), f"Directory missing: {ARCHIVE_DIR}"

    entries = list(os.scandir(ARCHIVE_DIR))
    assert entries, "Archive directory is empty"
    for entry in entries:
        assert CHUNK_RE.fullmatch(entry.name), f"Unexpected file or invalid chunk name in archive: {entry.name}"
        assert entry.is_file(follow_symlinks=False), f"Archive entry is not a regular chunk file: {entry.name}"

    chunks = get_chunks()
    assert len(chunks) > 0, "No chunked files found in /home/user/archive matching 'prod_logs.gz.part-*'"
    assert len(chunks) == len(entries), "Archive must contain only the chunked files"

    # Check chunk sizes: all but the last must be exactly 51200 bytes.
    for chunk in chunks[:-1]:
        size = os.path.getsize(chunk)
        assert size == 51200, f"Chunk {chunk} has size {size}, expected 51200 (50KB)"

    last_size = os.path.getsize(chunks[-1])
    assert 0 < last_size <= 51200, f"Last chunk has size {last_size}, expected between 1 and 51200 bytes"


def expected_file_outputs():
    outputs = []
    for root, dirs, files in os.walk(RAW_LOGS_DIR):
        relative_parts = os.path.relpath(root, RAW_LOGS_DIR).split(os.sep)
        if "prod" not in relative_parts:
            continue
        for filename in files:
            if not filename.endswith(".log.gz"):
                continue
            path = os.path.join(root, filename)
            transformed = []
            with gzip.open(path, "rt", encoding="utf-8", newline="") as source:
                for line in source:
                    if "DEBUG" in line:
                        continue
                    transformed.append(IP_PATTERN.sub("IP: REDACTED", line))
            outputs.append("".join(transformed).splitlines())
    assert outputs, "Test setup contains no prod .log.gz files"
    return outputs


def is_concatenation_in_some_file_order(actual_lines, expected_outputs):
    # File order is unrestricted, but content and line order within each file are exact.
    expected = [tuple(lines) for lines in expected_outputs]
    total = sum(len(lines) for lines in expected)
    if len(actual_lines) != total:
        return False

    @lru_cache(maxsize=None)
    def match(mask, position):
        if mask == (1 << len(expected)) - 1:
            return position == len(actual_lines)
        for index, lines in enumerate(expected):
            if mask & (1 << index):
                continue
            end = position + len(lines)
            if tuple(actual_lines[position:end]) == lines and match(mask | (1 << index), end):
                return True
        return False

    return match(0, 0)


def test_reconstructed_content():
    chunks = get_chunks()
    assert len(chunks) > 0, "No chunked files found to test content"

    compressed_data = bytearray()
    for chunk in chunks:
        with open(chunk, "rb") as handle:
            compressed_data.extend(handle.read())

    try:
        decompressed_data = gzip.decompress(compressed_data).decode("utf-8")
    except Exception as exc:
        assert False, f"Failed to decompress concatenated chunks: {exc}"

    lines = decompressed_data.splitlines()
    assert len(lines) > 0, "Decompressed log data is empty"

    # Preserve the original content assertions.
    assert not any("Dev user" in line for line in lines), "Dev logs were incorrectly included in the output"
    assert not any("DEBUG" in line for line in lines), "DEBUG lines were not removed from the output"
    for line in lines:
        assert not IP_PATTERN.search(line), f"Unredacted IP found in line: {line}"
    assert any("IP: REDACTED" in line for line in lines), "Expected 'IP: REDACTED' not found in logs (redaction failed)"
    assert any("INFO Normal operation" in line for line in lines), "Expected prod log content ('INFO Normal operation') missing"
    assert any("Failed to load module" in line for line in lines), "Expected prod log content ('Failed to load module') missing"

    expected_outputs = expected_file_outputs()
    assert is_concatenation_in_some_file_order(lines, expected_outputs), (
        "Decompressed archive is not the complete, exactly transformed content "
        "of all prod log files in any permitted file order"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
