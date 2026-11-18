#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_backup_manifest_exists_and_correct():
    manifest_path = "/home/user/backup_manifest.json"
    assert os.path.isfile(manifest_path), f"Expected manifest file {manifest_path} does not exist."

    with open(manifest_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Manifest file {manifest_path} does not contain valid JSON: {e}")

    assert isinstance(data, list), "Manifest JSON should be a list of objects."
    assert len(data) == 2, f"Expected exactly 2 entries in the manifest, found {len(data)}."

    expected_0 = {
        "file": "/home/user/db_data/partition1/001.wal",
        "tx_id": 1042,
        "log_snippet": "Error: Checkpoint timeout\nRetrying flush..."
    }

    expected_1 = {
        "file": "/home/user/db_data/partition2/002.wal",
        "tx_id": 1045,
        "log_snippet": "Warning: disk space low\nArchiving forced"
    }

    assert data[0] == expected_0, f"First entry in manifest does not match expected. Got: {data[0]}"
    assert data[1] == expected_1, f"Second entry in manifest does not match expected. Got: {data[1]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
