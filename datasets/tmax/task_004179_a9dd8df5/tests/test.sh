#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import tarfile

LOG_ROOT = "/home/user/server_logs"
OUTPUT_PATH = "/home/user/fatal_errors.jsonl"
TAR_PATH = "/home/user/fatal_backup.tar.gz"


def expected_records_from_logs():
    records = []
    for root, _, files in os.walk(LOG_ROOT):
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".log.gz"):
                opener = gzip.open
            elif name.endswith(".log"):
                opener = open
            else:
                continue

            with opener(path, "rt", encoding="utf-8") as f:
                for line in f:
                    try:
                        record = json.loads(line)
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        continue
                    if isinstance(record, dict) and record.get("level") == "FATAL":
                        records.append(record)

    records.sort(key=lambda record: record["id"])
    return records


def parse_and_validate_jsonl(content, source):
    assert content, f"{source} is empty"
    assert content.endswith("\n"), f"{source} must end after its final JSON line"

    raw_lines = content.splitlines()
    assert all(line for line in raw_lines), f"{source} contains blank lines"

    records = []
    for line in raw_lines:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Invalid JSON found in {source}: {line}"
        assert line == json.dumps(record, separators=(",", ":"), ensure_ascii=False), \
            f"JSON line in {source} contains extra whitespace or is not compact: {line}"
        records.append(record)
    return records


def test_fatal_errors_jsonl():
    filepath = OUTPUT_PATH
    assert os.path.exists(filepath), f"{filepath} is missing"
    assert os.path.isfile(filepath), f"{filepath} is not a regular file"

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    records = parse_and_validate_jsonl(content, filepath)

    expected_ids = [2, 8, 12, 18]
    actual_ids = [r["id"] for r in records if "id" in r]

    assert actual_ids == expected_ids, f"Expected IDs {expected_ids}, but got {actual_ids}. Ensure records are filtered by FATAL and sorted by id."
    assert all(r.get("level") == "FATAL" for r in records), "Found non-FATAL records in the output."

    expected_records = expected_records_from_logs()
    assert records == expected_records, \
        f"Output records do not exactly match the FATAL records from the source logs. Expected {expected_records}, got {records}"


def test_fatal_backup_tar_gz():
    tar_path = TAR_PATH
    assert os.path.exists(tar_path), f"{tar_path} is missing"

    assert tarfile.is_tarfile(tar_path), f"{tar_path} is not a valid tar archive"

    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            members = tar.getnames()
            assert "fatal_errors.jsonl" in members, "Archive does not contain 'fatal_errors.jsonl' at the root"
            assert members == ["fatal_errors.jsonl"], \
                f"Archive must contain exactly fatal_errors.jsonl at its root, but contains: {members}"

            member = tar.getmember("fatal_errors.jsonl")
            assert member.isfile(), "Archived fatal_errors.jsonl is not a regular file"

            f = tar.extractfile("fatal_errors.jsonl")
            assert f is not None, "Could not extract 'fatal_errors.jsonl' from the archive"

            archived_bytes = f.read()
            try:
                content = archived_bytes.decode("utf-8")
            except UnicodeDecodeError as exc:
                assert False, f"Archived fatal_errors.jsonl is not valid UTF-8: {exc}"
            records = parse_and_validate_jsonl(content, "archived fatal_errors.jsonl")

            expected_ids = [2, 8, 12, 18]
            actual_ids = [r["id"] for r in records if "id" in r]

            assert actual_ids == expected_ids, f"Archived file has incorrect IDs. Expected {expected_ids}, got {actual_ids}"
            assert all(r.get("level") == "FATAL" for r in records), "Archived file contains non-FATAL records"

            expected_records = expected_records_from_logs()
            assert records == expected_records, \
                f"Archived records do not exactly match the FATAL records from the source logs. Expected {expected_records}, got {records}"

            with open(OUTPUT_PATH, "rb") as output_file:
                assert archived_bytes == output_file.read(), \
                    "Archived fatal_errors.jsonl does not exactly match /home/user/fatal_errors.jsonl"
    except tarfile.ReadError:
        assert False, f"{tar_path} is not a valid gzip-compressed tar archive"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
