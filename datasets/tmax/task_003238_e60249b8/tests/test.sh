#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
from collections import Counter
from functools import lru_cache
import importlib.metadata
import pytest


def expected_cleaned_chunks():
    """Reproduce the immutable setup corpus without trusting agent-mutable files."""
    rng = random.Random(42)
    chunks = []

    for _ in range(100):
        is_2021 = rng.choice([True, False])
        rng.uniform(0, 1)  # The setup's mtime selection consumes one PRNG value.
        rng.choice(['utf-8', 'utf-16le', 'iso-8859-1'])

        cleaned = []
        for _ in range(500):
            if rng.random() < 0.4:
                rng.randint(0, 100000)
            else:
                cleaned.append(f"[INFO] Regular operation tick {rng.randint(0, 10000)}\n")

        if is_2021:
            chunks.append("".join(cleaned).encode("utf-8"))

    return chunks


def is_concatenation_in_any_order(data, chunks):
    """Accept any file ordering while requiring each cleaned file exactly once."""
    grouped = Counter(chunk for chunk in chunks if chunk)
    unique_chunks = sorted(grouped, key=len, reverse=True)
    initial_counts = tuple(grouped[chunk] for chunk in unique_chunks)

    @lru_cache(maxsize=None)
    def match(position, counts):
        if position == len(data):
            return all(count == 0 for count in counts)
        if position > len(data):
            return False

        for index, chunk in enumerate(unique_chunks):
            if counts[index] and data.startswith(chunk, position):
                next_counts = list(counts)
                next_counts[index] -= 1
                if match(position + len(chunk), tuple(next_counts)):
                    return True
        return False

    return match(0, initial_counts)


def test_archive_size_metric():
    target_file = "/home/user/archive.zst"

    assert os.path.exists(target_file), f"The target output file {target_file} does not exist."
    assert os.path.isfile(target_file), f"The target {target_file} is not a file."

    size = os.path.getsize(target_file)

    assert size <= 3000, f"Metric failed: file size {size} bytes exceeds the maximum threshold of 3000 bytes. Compression level too low, debug lines not stripped, or 2022 files included."
    assert size >= 100, f"Metric failed: file size {size} bytes is below the minimum threshold of 100 bytes. File is suspiciously small, likely empty or invalid data."


def test_archive_is_valid_and_has_exact_cleaned_contents():
    target_file = "/home/user/archive.zst"
    assert os.path.isfile(target_file), f"The target {target_file} is not a file."

    try:
        assert importlib.metadata.version("pyzstd") == "0.15.9"
        import pyzstd
    except Exception as exc:
        pytest.fail(f"pyzstd 0.15.9 is not successfully installed: {exc}")

    with open(target_file, "rb") as archive:
        compressed = archive.read()

    try:
        decompressed = pyzstd.decompress(compressed)
    except Exception as exc:
        pytest.fail(f"archive.zst is not a valid pyzstd-decompressible stream: {exc}")

    try:
        decompressed.decode("utf-8")
    except UnicodeDecodeError as exc:
        pytest.fail(f"Decompressed archive is not valid UTF-8: {exc}")

    chunks = expected_cleaned_chunks()
    assert is_concatenation_in_any_order(decompressed, chunks), (
        "Decompressed archive does not contain exactly the cleaned UTF-8 contents "
        "of every 2021 log file, concatenated once each."
    )


def test_pyzstd_bad_flag_removed():
    setup_path = "/app/pyzstd-0.15.9/setup.py"
    if os.path.exists(setup_path):
        with open(setup_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        assert "-fbreak-my-build-123" not in content, "The bad compiler flag '-fbreak-my-build-123' was not removed from setup.py."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
