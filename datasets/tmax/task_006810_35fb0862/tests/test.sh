#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import secrets
import shutil
import struct
import subprocess
import pytest

SCRIPT_PATH = "/home/user/archive_logs.py"
ARCHIVE_PATH = "/home/user/archive.json.gz"
LOGS_PATH = "/home/user/logs"


def read_archive(path):
    try:
        with gzip.open(path, "rt", encoding="utf-8") as f:
            lines = f.read().strip().split("\n")
    except Exception as e:
        pytest.fail(f"Failed to read or decompress {path}: {e}")
    return [line for line in lines if line.strip()]


def test_archive_json_gz_exists_and_correct():
    # Preserve the original final-artifact assertions.
    assert os.path.exists(ARCHIVE_PATH), f"File {ARCHIVE_PATH} does not exist."
    assert os.path.isfile(ARCHIVE_PATH), f"{ARCHIVE_PATH} is not a file."

    lines = read_archive(ARCHIVE_PATH)
    assert len(lines) == 6, f"Expected exactly 6 lines in the archive, found {len(lines)}."

    expected_data = [
        {"timestamp": "2023-10-01T10:00:00Z", "level": "INFO", "message": "Backup service started"},
        {"timestamp": "2023-10-01T10:05:00Z", "level": "DEBUG", "message": "Scanning directories"},
        {"timestamp": "2023-10-01T10:10:00Z", "level": "WARN", "message": "File locked by another process"},
        {"timestamp": "2023-10-01T10:15:00Z", "level": "INFO", "message": "Retrying locked file"},
        {"timestamp": "2023-10-01T10:20:00Z", "level": "ERROR", "message": "Failed to backup file"},
        {"timestamp": "2023-10-01T10:25:00Z", "level": "INFO", "message": "Backup service shutting down"},
    ]

    for idx, (line, expected) in enumerate(zip(lines, expected_data)):
        try:
            parsed_json = json.loads(line)
        except json.JSONDecodeError as e:
            pytest.fail(f"Line {idx + 1} is not valid JSON: {e}\nLine content: {line}")
        assert parsed_json == expected, (
            f"Mismatch at line {idx + 1}.\nExpected: {expected}\nGot:      {parsed_json}"
        )


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def test_script_parses_framed_logs_and_regenerates_archive():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."

    token = secrets.token_hex(12)
    records_by_file = {
        # Created deliberately out of chronological order.
        "log.12": [
            ("2099-04-12T12:00:00Z", "ERROR", f"late-{token}"),
            ("2099-04-12T12:01:00Z", "INFO", "UTF-8 café ☃"),
        ],
        "active.log": [
            ("2099-04-12T13:00:00Z", "INFO", f"active-one-{token}"),
            ("2099-04-12T13:01:00Z", "WARN", f"active-two-{token}"),
        ],
        "log.3": [
            ("2099-04-12T03:00:00Z", "DEBUG", f"middle-one-{token}"),
            ("2099-04-12T03:01:00Z", "INFO", f"middle-two-{token}"),
            ("2099-04-12T03:02:00Z", "WARN", f"middle-three-{token}"),
        ],
        "log.0": [
            ("2099-04-12T00:00:00Z", "INFO", f"first-{token}"),
        ],
    }
    expected_order = ["log.0", "log.3", "log.12", "active.log"]
    expected = [
        {"timestamp": timestamp, "level": level, "message": message}
        for filename in expected_order
        for timestamp, level, message in records_by_file[filename]
    ]

    backup_suffix = secrets.token_hex(8)
    logs_backup = f"{LOGS_PATH}.verifier-backup-{backup_suffix}"
    archive_backup = f"{ARCHIVE_PATH}.verifier-backup-{backup_suffix}"

    os.rename(LOGS_PATH, logs_backup)
    os.rename(ARCHIVE_PATH, archive_backup)
    os.makedirs(LOGS_PATH)

    try:
        for filename, records in records_by_file.items():
            with open(os.path.join(LOGS_PATH, filename), "wb") as f:
                for timestamp, level, message in records:
                    payload = f"{timestamp},{level},{message}".encode("utf-8")
                    f.write(struct.pack(">I", len(payload)))
                    f.write(payload)

        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(ARCHIVE_PATH), "The script did not create archive.json.gz."

        lines = read_archive(ARCHIVE_PATH)
        assert len(lines) == len(expected), (
            f"Expected {len(expected)} generated JSONL records, found {len(lines)}."
        )
        actual = []
        for idx, line in enumerate(lines):
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError as e:
                pytest.fail(f"Generated line {idx + 1} is not valid JSON: {e}")
        assert actual == expected, (
            "Executing the script on newly generated framed logs did not produce "
            "the expected records in numeric rotation order followed by active.log."
        )
    finally:
        remove_path(LOGS_PATH)
        remove_path(ARCHIVE_PATH)
        os.rename(logs_backup, LOGS_PATH)
        os.rename(archive_backup, ARCHIVE_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
