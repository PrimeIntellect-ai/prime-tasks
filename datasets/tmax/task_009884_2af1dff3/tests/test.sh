#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

CONVERTED_DIR = "/home/user/converted_configs"
MANIFEST_PATH = "/home/user/manifest.json"

# Truth data based on the setup intent
VALID_FILES = [
    {
        "filename": "main_db.cfg",
        "payload": "host=192.168.1.100\nport=5432\nuser=admin\n"
    },
    {
        "filename": "core_switch.bin",
        "payload": "vlan=10,20\nmtu=1500\nspanning_tree=rstp\n"
    },
    {
        "filename": "system_global.dat",
        "payload": "debug_mode=false\nlog_level=WARN\n"
    }
]

def get_expected_state():
    expected_state = {}
    for f in VALID_FILES:
        utf8_content = f["payload"].encode('utf-8')
        sha256_hash = hashlib.sha256(utf8_content).hexdigest()
        expected_state[f["filename"]] = {
            "content": utf8_content,
            "hash": sha256_hash,
            "converted_path": os.path.join(CONVERTED_DIR, f"{f['filename']}.utf8")
        }
    return expected_state

EXPECTED_STATE = get_expected_state()

def test_converted_directory_exists():
    assert os.path.exists(CONVERTED_DIR), f"Directory {CONVERTED_DIR} does not exist."
    assert os.path.isdir(CONVERTED_DIR), f"{CONVERTED_DIR} is not a directory."

def test_converted_files_content_and_hash():
    for filename, info in EXPECTED_STATE.items():
        converted_path = info["converted_path"]
        assert os.path.exists(converted_path), f"Converted file missing: {converted_path}"
        assert os.path.isfile(converted_path), f"Expected a file at {converted_path}"

        with open(converted_path, 'rb') as f:
            content = f.read()

        assert content == info["content"], f"Content of {converted_path} does not match the expected UTF-8 payload."

        actual_hash = hashlib.sha256(content).hexdigest()
        assert actual_hash == info["hash"], f"SHA-256 hash mismatch for {converted_path}"

def test_decoy_files_not_converted():
    decoy_filenames = ["backup_db.cfg.utf8", "readme.txt.utf8"]
    for decoy in decoy_filenames:
        decoy_path = os.path.join(CONVERTED_DIR, decoy)
        assert not os.path.exists(decoy_path), f"Decoy file was incorrectly converted: {decoy_path}"

def test_manifest_exists_and_valid_json():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file missing: {MANIFEST_PATH}"
    assert os.path.isfile(MANIFEST_PATH), f"Expected a file at {MANIFEST_PATH}"

    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        try:
            manifest_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file {MANIFEST_PATH} is not valid JSON.")

    expected_manifest = {filename: info["hash"] for filename, info in EXPECTED_STATE.items()}

    assert manifest_data == expected_manifest, (
        f"Manifest content does not match expected mapping.\n"
        f"Expected: {expected_manifest}\n"
        f"Actual: {manifest_data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
