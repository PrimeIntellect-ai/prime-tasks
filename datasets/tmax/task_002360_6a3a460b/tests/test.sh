#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import tarfile

RAW_ARCHIVE = "/home/user/backups/raw_logs.tar.gz"
CLEAN_ARCHIVE = "/home/user/backups/clean_logs.tar.gz"
PROCESSING = "/home/user/processing"
SUMMARY = "/home/user/backups/summary.txt"


def log_members(archive_path):
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        logs = [m for m in members if m.name.endswith(".log")]
        assert logs, f"No .log files found in {archive_path}"
        assert all(m.isfile() for m in logs), "Every .log archive member must be a regular file"
        assert len({m.name for m in logs}) == len(logs), "Duplicate .log archive members found"
        result = {}
        for member in logs:
            assert not os.path.isabs(member.name), f"Absolute archive path: {member.name}"
            normalized = os.path.normpath(member.name)
            assert normalized == member.name and normalized != ".." and not normalized.startswith("../"), \
                f"Unsafe or non-canonical archive path: {member.name}"
            extracted = tar.extractfile(member)
            assert extracted is not None
            result[member.name] = extracted.read()
        return members, result


def transform(data, name):
    lines = data.splitlines(keepends=True)
    output = []
    record = None
    record_count = 0

    for line in lines:
        logical = line.rstrip(b"\r\n")
        if record is None:
            assert logical == b"[START_RECORD]", \
                f"Unexpected content outside a record in {name}: {logical!r}"
            record = [line]
            continue

        assert logical != b"[START_RECORD]", f"Nested START_RECORD in {name}"
        record.append(line)
        if logical == b"[END_RECORD]":
            body = [item.rstrip(b"\r\n") for item in record]
            deprecated = b"Server: DEPRECATED_SRV" in body
            if not deprecated:
                if not any(item.startswith(b"ErrorCode: ") for item in body):
                    record.insert(-1, b"ErrorCode: 0000\n")
                output.extend(record)
                record_count += 1
            record = None

    assert record is None, f"Unterminated record in {name}"
    return b"".join(output), record_count


def processing_logs():
    result = {}
    for root, _, files in os.walk(PROCESSING):
        for filename in files:
            full_path = os.path.join(root, filename)
            rel_path = os.path.relpath(full_path, PROCESSING)
            assert not filename.endswith(".tmp"), f"Temporary file was not atomically moved away: {full_path}"
            if filename.endswith(".log"):
                assert os.path.isfile(full_path) and not os.path.islink(full_path), \
                    f"Processed log is not a regular file: {full_path}"
                with open(full_path, "rb") as handle:
                    result[rel_path] = handle.read()
    return result


def test_complete_final_state():
    assert os.path.isfile(RAW_ARCHIVE), f"File missing: {RAW_ARCHIVE}"
    raw_members, raw_logs = log_members(RAW_ARCHIVE)
    raw_names = set(raw_logs)
    assert raw_names == {"app1.log", "app2.log"}

    expected = {}
    expected_count = 0
    for name, data in raw_logs.items():
        expected[name], count = transform(data, name)
        expected_count += count

    # Preserve the original verifier's fixed-data assertion.
    assert expected_count == 3

    assert os.path.isfile(SUMMARY), f"File missing: {SUMMARY}"
    with open(SUMMARY, "rb") as handle:
        summary = handle.read()
    assert re.fullmatch(rb"3\n?", summary), \
        f"Expected summary.txt to contain only '3', but got {summary!r}"

    processed = processing_logs()
    assert set(processed) == raw_names, \
        f"Processed .log paths differ from original: {set(processed)!r}"
    assert processed == expected, "Processed logs do not exactly match the required transformation"

    actual_count = sum(data.count(b"[START_RECORD]") for data in processed.values())
    assert actual_count == expected_count
    assert int(summary.strip()) == actual_count

    assert os.path.isfile(CLEAN_ARCHIVE), f"File missing: {CLEAN_ARCHIVE}"
    clean_members, archived = log_members(CLEAN_ARCHIVE)
    assert collections.Counter(m.name for m in clean_members) == collections.Counter(raw_logs), \
        "clean_logs.tar.gz must contain exactly the original .log paths, once each"
    assert archived == expected, "Archived logs do not exactly match the required transformation"
    assert archived == processed, "Archive contents differ from the final processing directory"

    # Preserve and strengthen the original content assertions.
    app1_content = archived["app1.log"]
    app2_content = archived["app2.log"]
    assert b"DEPRECATED_SRV" not in app1_content
    assert b"DEPRECATED_SRV" not in app2_content
    assert b"ErrorCode: 401" in app1_content
    assert b"ErrorCode: 0000\n[END_RECORD]" in app1_content
    assert b"ErrorCode: 0000\n[END_RECORD]" in app2_content

    for name, data in archived.items():
        _, count = transform(data, name)
        assert count == data.count(b"[START_RECORD]") == data.count(b"[END_RECORD]")

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
