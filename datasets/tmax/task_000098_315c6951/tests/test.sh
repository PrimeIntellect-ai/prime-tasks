#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_summary_log():
    log_path = '/home/user/curation_summary.log'
    assert os.path.exists(log_path), f"Summary log not found at {log_path}"
    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected_lines = [
        "Total files extracted: 3",
        "Total .cfg files modified: 2"
    ]
    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in summary log. Content was:\n{content}"

def test_app_config():
    path = '/home/user/extracted_artifacts/app_config.cfg'
    assert os.path.exists(path), f"File not found: {path}"
    with open(path, 'r') as f:
        content = f.read()

    assert "auth_protocol=v3" in content, "auth_protocol was not updated to v3 in app_config.cfg."
    assert "mirror=https://new.repo.global" in content, "mirror was not updated to new URL in app_config.cfg."
    assert "deprecated_flag" not in content, "deprecated_flag lines were not removed from app_config.cfg."
    assert "setting=42" in content, "Original content 'setting=42' missing from app_config.cfg."
    assert "auth_protocol=v1" not in content, "Old auth_protocol=v1 still present in app_config.cfg."
    assert "mirror=http://old.repo.local" not in content, "Old mirror URL still present in app_config.cfg."

def test_db_config():
    path = '/home/user/extracted_artifacts/db_config.cfg'
    assert os.path.exists(path), f"File not found: {path}"
    with open(path, 'r') as f:
        content = f.read()

    assert "auth_protocol=v3" in content, "auth_protocol was not updated to v3 in db_config.cfg."
    assert "mirror=https://new.repo.global" in content, "mirror was not updated to new URL in db_config.cfg."
    assert "deprecated_flag" not in content, "deprecated_flag lines were not removed from db_config.cfg."
    assert "host=localhost" in content, "Original content 'host=localhost' missing from db_config.cfg."
    assert "auth_protocol=v1" not in content, "Old auth_protocol=v1 still present in db_config.cfg."

def test_binary_blob():
    path = '/home/user/extracted_artifacts/binary_blob.dat'
    assert os.path.exists(path), f"File not found: {path}"
    with open(path, 'rb') as f:
        content = f.read()

    expected_blob = b"\x00\x00\x00\xFF\xFF\xFF\x00\x00\x00"
    assert content == expected_blob, f"Binary blob content mismatch. Expected {expected_blob}, got {content}"

def test_index_json():
    path = '/home/user/extracted_artifacts/index.json'
    assert os.path.exists(path), f"File not found: {path}"
    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not a valid JSON.")

    expected_data = {
      "app_config.cfg": {
        "checksum": 391203,
        "timestamp": 1690000000
      },
      "db_config.cfg": {
        "checksum": 849201,
        "timestamp": 1690000100
      },
      "binary_blob.dat": {
        "checksum": 112233,
        "timestamp": 1690000200
      }
    }

    assert data == expected_data, f"JSON content mismatch. Expected {expected_data}, got {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
