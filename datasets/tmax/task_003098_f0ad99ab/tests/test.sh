#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import base64
import pytest

WAL_PATH = "/home/user/sys_updates.wal"
VERSIONS_DIR = "/home/user/configs/versions"
ACTIVE_DIR = "/home/user/configs/active"

@pytest.fixture(scope="module")
def expected_state():
    assert os.path.isfile(WAL_PATH), f"WAL file {WAL_PATH} is missing."

    modules = {}
    with open(WAL_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) != 3:
                continue
            timestamp_str, module, payload_b64 = parts
            timestamp = int(timestamp_str)

            if module not in modules or timestamp > modules[module]["timestamp"]:
                modules[module] = {
                    "timestamp": timestamp,
                    "payload": base64.b64decode(payload_b64).decode("utf-8")
                }

    assert modules, "Failed to parse any modules from the WAL file."
    return modules

def test_directories_exist():
    assert os.path.isdir(VERSIONS_DIR), f"Directory {VERSIONS_DIR} does not exist."
    assert os.path.isdir(ACTIVE_DIR), f"Directory {ACTIVE_DIR} does not exist."

def test_versioned_files_exist_and_content(expected_state):
    for module, data in expected_state.items():
        expected_filename = f"{module}_{data['timestamp']}.conf"
        expected_filepath = os.path.join(VERSIONS_DIR, expected_filename)

        assert os.path.isfile(expected_filepath), f"Expected versioned file {expected_filepath} does not exist."

        with open(expected_filepath, "r") as f:
            content = f.read()

        assert content == data["payload"], f"Content of {expected_filepath} does not match the expected decoded payload."

def test_active_symlinks_exist_and_correct(expected_state):
    for module, data in expected_state.items():
        symlink_path = os.path.join(ACTIVE_DIR, f"{module}.conf")
        expected_target_filename = f"{module}_{data['timestamp']}.conf"
        expected_target_filepath = os.path.join(VERSIONS_DIR, expected_target_filename)

        assert os.path.islink(symlink_path), f"Expected symlink {symlink_path} does not exist or is not a symlink."

        target = os.readlink(symlink_path)

        # Resolve to absolute path to compare safely
        if not os.path.isabs(target):
            target = os.path.normpath(os.path.join(ACTIVE_DIR, target))

        assert target == expected_target_filepath, f"Symlink {symlink_path} points to {target}, expected {expected_target_filepath}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
