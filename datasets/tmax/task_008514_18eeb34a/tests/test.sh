#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import tarfile
import hashlib
import pytest


def get_expected_data():
    experiments = ["EXP_ALPHA", "EXP_BETA", "EXP_GAMMA"]
    random.seed(42)

    expected_records = {exp: [] for exp in experiments}
    corrupted = []

    for i in range(1000):
        if i % 100 == 0:
            corrupted.append(f"CORRUPTED_LINE_{i}{{missing_brackets}}\n")
        else:
            exp = random.choice(experiments)
            record = {
                "experiment_id": exp,
                "read_id": f"READ_{i}",
                "sequence_data": "".join(random.choices(["A", "C", "G", "T"], k=50)),
            }
            expected_records[exp].append((json.dumps(record) + "\n").encode("utf-8"))

    counts = {exp: len(records) for exp, records in expected_records.items()}
    return counts, corrupted, expected_records


def test_corrupted_reads_log():
    """Verify that the corrupted reads log contains exactly the expected corrupted lines."""
    log_path = "/home/user/corrupted_reads.log"
    assert os.path.isfile(log_path), f"File not found: {log_path}"

    _, expected_corrupted, _ = get_expected_data()

    with open(log_path, "r") as f:
        actual_lines = f.readlines()

    assert len(actual_lines) == len(expected_corrupted), f"Expected {len(expected_corrupted)} corrupted lines, found {len(actual_lines)}"
    for expected, actual in zip(expected_corrupted, actual_lines):
        assert expected == actual, f"Mismatch in corrupted log. Expected: {expected.strip()}, Actual: {actual.strip()}"


def test_archives_exist_and_contents():
    """Verify each archive contains every original JSON line for its experiment, in stream order."""
    expected_counts, _, expected_records = get_expected_data()
    archives_dir = "/home/user/archives"

    for exp, expected_count in expected_counts.items():
        archive_path = os.path.join(archives_dir, f"{exp}_archive.tar.gz")
        assert os.path.isfile(archive_path), f"Archive not found: {archive_path}"

        with tarfile.open(archive_path, "r:gz") as tar:
            members = tar.getmembers()
            reads_member = None
            for member in members:
                if member.name.endswith("reads.jsonl"):
                    reads_member = member
                    break

            assert reads_member is not None, f"reads.jsonl not found in archive {archive_path}"
            assert not reads_member.name.startswith("/home/"), f"Archive {archive_path} contains absolute paths: {reads_member.name}"

            with tar.extractfile(reads_member) as f:
                lines = f.readlines()
                assert len(lines) == expected_count, f"Expected {expected_count} lines in {exp} archive, found {len(lines)}"

                # Preserve the original validity and experiment-ID assertions.
                for line in lines:
                    record = json.loads(line.decode("utf-8"))
                    assert record["experiment_id"] == exp, f"Found wrong experiment ID in {exp} archive."

                # Every archived line must be the exact original generator output,
                # including read_id, sequence_data, serialization, and stream order.
                assert lines == expected_records[exp], f"Archived records for {exp} do not exactly match the generated stream"


def test_final_checksums_txt():
    """Verify checksums are correct and listed alphabetically by archive filename."""
    checksums_path = "/home/user/final_checksums.txt"
    assert os.path.isfile(checksums_path), f"File not found: {checksums_path}"

    expected_counts, _, _ = get_expected_data()
    archives_dir = "/home/user/archives"

    actual_checksums = {}
    for exp in expected_counts.keys():
        archive_path = os.path.join(archives_dir, f"{exp}_archive.tar.gz")
        if os.path.isfile(archive_path):
            hasher = hashlib.sha256()
            with open(archive_path, "rb") as f:
                hasher.update(f.read())
            actual_checksums[f"{exp}_archive.tar.gz"] = hasher.hexdigest()

    with open(checksums_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 3, f"Expected 3 lines in {checksums_path}, found {len(lines)}"

    parsed_checksums = {}
    listed_filenames = []
    for line in lines:
        parts = line.split()
        assert len(parts) >= 2, f"Invalid format in checksums file: {line}"
        chksm = parts[0]
        fname = parts[1].lstrip("*./")
        basename = os.path.basename(fname)
        listed_filenames.append(basename)
        parsed_checksums[basename] = chksm

    expected_filenames = sorted(f"{exp}_archive.tar.gz" for exp in expected_counts.keys())
    assert listed_filenames == expected_filenames, f"Checksums are not listed alphabetically by filename: {listed_filenames}"

    for exp in expected_counts.keys():
        fname = f"{exp}_archive.tar.gz"
        assert fname in parsed_checksums, f"{fname} missing from {checksums_path}"
        assert parsed_checksums[fname] == actual_checksums.get(fname, ""), f"Checksum mismatch for {fname}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
