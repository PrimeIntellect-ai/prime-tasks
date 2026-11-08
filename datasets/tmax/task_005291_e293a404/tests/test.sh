#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import io
import json
import os
import re
import subprocess
import tarfile
import uuid
import zipfile

import pytest

TRANSFORM = "/home/user/transform.py"
FINAL_ARCHIVE = "/home/user/final_logs.tar.gz"
CONSOLIDATED = "/home/user/consolidated.jsonl"
EXTRACTED = "/home/user/extracted"
BACKUP_PARTS = [
    "/home/user/backups/archive.zip.001",
    "/home/user/backups/archive.zip.002",
]
LOG_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (\S+) (.+)$")


def source_artifacts():
    """Derive valid archives, raw logs, and expected records from the supplied backup."""
    combined = b"".join(open(path, "rb").read() for path in BACKUP_PARTS)
    with zipfile.ZipFile(io.BytesIO(combined), "r") as archive_zip:
        assert "nested.tar" in archive_zip.namelist(), "nested.tar is absent from the multipart zip"
        nested_data = archive_zip.read("nested.tar")

    valid_archives = {}
    raw_logs = {}
    with tarfile.open(fileobj=io.BytesIO(nested_data), mode="r:") as nested:
        for member in nested.getmembers():
            if not member.isfile() or not member.name.endswith(".tar.gz"):
                continue
            archive_data = nested.extractfile(member).read()
            try:
                with tarfile.open(fileobj=io.BytesIO(archive_data), mode="r:gz") as inner:
                    inner_logs = {}
                    for log_member in inner.getmembers():
                        if log_member.isfile() and log_member.name.endswith(".log"):
                            inner_logs[os.path.basename(log_member.name)] = inner.extractfile(log_member).read()
            except (tarfile.TarError, EOFError, OSError):
                continue
            valid_archives[os.path.basename(member.name)] = archive_data
            raw_logs.update(inner_logs)

    expected = []
    for data in raw_logs.values():
        for line in data.decode("utf-8").splitlines():
            match = LOG_RE.fullmatch(line)
            if match:
                expected.append({
                    "timestamp": match.group(1),
                    "severity": match.group(2),
                    "message": match.group(3),
                })
    return valid_archives, raw_logs, expected


def record_counter(records):
    return collections.Counter(
        (record.get("timestamp"), record.get("severity"), record.get("message"))
        for record in records
    )


def test_transform_script_exists():
    """Check if the transform script was created."""
    assert os.path.isfile(TRANSFORM), "/home/user/transform.py is missing."


def test_transform_script_behavior():
    """Execute the submitted transformer on fresh valid and invalid input."""
    token = uuid.uuid4().hex
    input_lines = [
        f"[2041-02-03 04:05:06] ERROR Dynamic message {token}",
        "not a log line",
        f"[2042-11-12 13:14:15] WARN Punctuation: {token}!",
        "[2042-11-12 13:14:15] INFO",
        "2042-11-12 13:14:15 INFO missing brackets",
        f"[2043-06-07 08:09:10] DEBUG Final {token}",
    ]
    expected = [
        {"timestamp": "2041-02-03 04:05:06", "severity": "ERROR", "message": f"Dynamic message {token}"},
        {"timestamp": "2042-11-12 13:14:15", "severity": "WARN", "message": f"Punctuation: {token}!"},
        {"timestamp": "2043-06-07 08:09:10", "severity": "DEBUG", "message": f"Final {token}"},
    ]
    result = subprocess.run(
        ["python3", TRANSFORM],
        input="\n".join(input_lines) + "\n",
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, f"transform.py failed: {result.stderr}"
    assert result.stderr == "", f"transform.py wrote unexpected stderr: {result.stderr}"
    assert result.stdout.splitlines() == [json.dumps(item) for item in expected], \
        "transform.py did not emit the required JSONL or did not ignore malformed lines"


def test_extraction_workflow_outputs():
    """Check that the valid nested archives and their logs were actually extracted."""
    assert os.path.isdir(EXTRACTED), "/home/user/extracted/ is missing."
    valid_archives, raw_logs, _ = source_artifacts()

    files_by_name = collections.defaultdict(list)
    for root, _, files in os.walk(EXTRACTED):
        for name in files:
            path = os.path.join(root, name)
            with open(path, "rb") as stream:
                files_by_name[name].append(stream.read())

    for name, expected_data in valid_archives.items():
        assert expected_data in files_by_name[name], f"Valid archive {name} was not extracted from nested.tar"
    for name, expected_data in raw_logs.items():
        assert expected_data in files_by_name[name], f"Log file {name} was not extracted from its valid archive"


def test_final_logs_archive_exists():
    """Check if the final tar.gz archive exists."""
    assert os.path.isfile(FINAL_ARCHIVE), "/home/user/final_logs.tar.gz is missing."


def test_final_logs_contents():
    """Check the contents of the final tar.gz archive."""
    archive_path = FINAL_ARCHIVE
    assert os.path.isfile(archive_path), "Archive missing"

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        # It must contain exactly one regular file at the archive root.
        assert len(members) == 1, f"Archive must contain exactly one member, found {len(members)}"
        assert members[0].name == "consolidated.jsonl", "Archive member must be consolidated.jsonl at the root"
        assert members[0].isfile(), "consolidated.jsonl must be a regular file"

        file_names = [m.name for m in members if m.isfile()]
        assert "consolidated.jsonl" in file_names, "consolidated.jsonl not found in the archive."

        f = tar.extractfile("consolidated.jsonl")
        assert f is not None, "Could not extract consolidated.jsonl from archive."
        archived_data = f.read()

    assert os.path.isfile(CONSOLIDATED), "/home/user/consolidated.jsonl is missing."
    with open(CONSOLIDATED, "rb") as stream:
        assert stream.read() == archived_data, "Archived data differs from /home/user/consolidated.jsonl"

    lines = archived_data.decode("utf-8").strip().split("\n")
    parsed_lines = []
    for line in lines:
        if not line.strip():
            continue
        try:
            parsed_lines.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON line found: {line}")

    expected_logs = [
        {"timestamp": "2023-10-01 12:00:00", "severity": "ERROR", "message": "Disk full"},
        {"timestamp": "2023-10-01 12:05:00", "severity": "INFO", "message": "Cleanup started"},
        {"timestamp": "2023-10-01 12:10:00", "severity": "WARN", "message": "High memory usage"},
        {"timestamp": "2023-10-01 12:15:00", "severity": "INFO", "message": "Process killed"},
    ]

    assert len(parsed_lines) == len(expected_logs), \
        f"Expected {len(expected_logs)} log entries, found {len(parsed_lines)}."
    for expected in expected_logs:
        assert expected in parsed_lines, f"Expected log entry not found in output: {expected}"

    _, _, source_expected = source_artifacts()
    assert record_counter(parsed_lines) == record_counter(source_expected), \
        "Consolidated output does not match the valid logs derived from the supplied backup"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
