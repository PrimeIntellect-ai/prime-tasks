#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import struct
import tarfile
import zipfile
import pytest

ARCHIVE_PATH = "/home/user/config_backups.zip"
OUTPUT_PATH = "/home/user/network_changes.json"


def parse_wal(payload, member_name):
    assert len(payload) >= 5, f"WAL file {member_name} is too short for its header."
    assert payload[:4] == b"CWAL", f"WAL file {member_name} has an invalid magic number."
    assert payload[4] == 1, f"WAL file {member_name} has unsupported version {payload[4]}."

    records = []
    offset = 5

    def take(length, field):
        nonlocal offset
        end = offset + length
        assert end <= len(payload), f"WAL file {member_name} is truncated while reading {field}."
        value = payload[offset:end]
        offset = end
        return value

    while offset < len(payload):
        timestamp = struct.unpack("<I", take(4, "timestamp"))[0]
        action = take(1, "action type")[0]
        key_length = struct.unpack("<H", take(2, "key length"))[0]
        key_bytes = take(key_length, "key")
        value_length = struct.unpack("<H", take(2, "value length"))[0]
        value_bytes = take(value_length, "value")

        try:
            key = key_bytes.decode("utf-8")
            value = value_bytes.decode("utf-8")
        except UnicodeDecodeError as exc:
            pytest.fail(f"WAL file {member_name} contains invalid UTF-8: {exc}")

        records.append((timestamp, action, key, value))

    return records


def derive_expected_data():
    assert os.path.isfile(ARCHIVE_PATH), f"Input archive {ARCHIVE_PATH} is missing."

    try:
        with zipfile.ZipFile(ARCHIVE_PATH, "r") as outer_zip:
            names = outer_zip.namelist()
            assert "logs_2024.tar.gz" in names, "logs_2024.tar.gz is missing from the backup zip."
            archive_2024 = outer_zip.read("logs_2024.tar.gz")
    except (zipfile.BadZipFile, OSError) as exc:
        pytest.fail(f"Could not read {ARCHIVE_PATH}: {exc}")

    records = []
    try:
        with tarfile.open(fileobj=io.BytesIO(archive_2024), mode="r:gz") as archive:
            wal_members = [
                member for member in archive.getmembers()
                if member.isfile() and member.name.endswith(".wal")
            ]
            assert wal_members, "The 2024 archive contains no .wal files."

            for member in wal_members:
                extracted = archive.extractfile(member)
                assert extracted is not None, f"Could not read WAL member {member.name}."
                records.extend(parse_wal(extracted.read(), member.name))
    except (tarfile.TarError, OSError) as exc:
        pytest.fail(f"Could not read logs_2024.tar.gz: {exc}")

    expected = [
        {"timestamp": timestamp, "key": key, "value": value}
        for timestamp, action, key, value in records
        if action == 2 and "network" in key
    ]
    expected.sort(key=lambda record: (record["timestamp"], record["key"]))
    return expected


def test_network_changes_json_exists():
    """Test that the output JSON file exists."""
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."


def test_network_changes_json_content():
    """Test that output contains the records derived from every 2024 WAL file."""
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    with open(OUTPUT_PATH, "r", encoding="utf-8") as output_file:
        try:
            data = json.load(output_file)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Failed to parse {OUTPUT_PATH} as JSON: {exc}")

    expected_data = derive_expected_data()

    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    assert len(data) == len(expected_data), \
        f"Expected {len(expected_data)} records, found {len(data)}."

    for index, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), \
            f"Expected record {index} to be a dictionary, got {type(actual).__name__}."

        for key in ["timestamp", "key", "value"]:
            assert key in actual, f"Record {index} is missing required key '{key}'."
            assert actual[key] == expected[key], \
                f"Record {index} '{key}' mismatch: expected {expected[key]}, got {actual[key]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
