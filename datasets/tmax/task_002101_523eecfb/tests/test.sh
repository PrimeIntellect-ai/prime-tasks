#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import tarfile

def test_json_output_file():
    json_path = "/home/user/filtered_logs.json"
    assert os.path.isfile(json_path), f"Output file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not a valid JSON."

    assert isinstance(data, list), f"JSON output in {json_path} must be a list of objects."
    assert len(data) == 2, f"Expected exactly 2 log entries in JSON, found {len(data)}."

    expected_entries = [
        {
            "timestamp": "2023-10-15 08:35:00",
            "level": "CRITICAL",
            "message": "Database connection timeout.\nRetries exhausted.\nCheck the network partition."
        },
        {
            "timestamp": "2023-10-16 11:25:05",
            "level": "CRITICAL",
            "message": "Out of memory exception.\nProcess killed by OOM killer."
        }
    ]

    # Sort both lists by timestamp to ensure order doesn't fail the test
    data_sorted = sorted(data, key=lambda x: x.get("timestamp", ""))
    expected_sorted = sorted(expected_entries, key=lambda x: x["timestamp"])

    for i, (actual, expected) in enumerate(zip(data_sorted, expected_sorted)):
        assert actual.get("timestamp") == expected["timestamp"], f"Entry {i}: Incorrect timestamp. Expected {expected['timestamp']}, got {actual.get('timestamp')}."
        assert actual.get("level") == expected["level"], f"Entry {i}: Incorrect level. Expected {expected['level']}, got {actual.get('level')}."
        # Strip trailing newlines just in case, but standard requires exact match
        actual_message = actual.get("message", "").strip()
        expected_message = expected["message"].strip()
        assert actual_message == expected_message, f"Entry {i}: Incorrect message text. Expected {repr(expected_message)}, got {repr(actual_message)}."

def test_tar_archive():
    archive_path = "/home/user/critical_backup.tar.gz"
    json_path = "/home/user/filtered_logs.json"
    assert os.path.isfile(archive_path), f"Archive file {archive_path} does not exist."

    assert tarfile.is_tarfile(archive_path), f"File {archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getnames()
        assert len(members) == 1, f"Archive should contain exactly 1 file, found {len(members)}: {members}."
        assert members[0] == "filtered_logs.json", f"Archive should contain exactly 'filtered_logs.json' with no leading directories, found '{members[0]}'."

        member = tar.getmember("filtered_logs.json")
        assert member.isfile(), "Archive member 'filtered_logs.json' must be a regular file."
        archived_file = tar.extractfile(member)
        assert archived_file is not None, "Could not read 'filtered_logs.json' from the archive."
        archived_contents = archived_file.read()

    with open(json_path, "rb") as f:
        output_contents = f.read()

    assert archived_contents == output_contents, "Archived 'filtered_logs.json' does not match /home/user/filtered_logs.json."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
