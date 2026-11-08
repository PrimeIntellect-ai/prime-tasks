#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def read_null_terminated(filepath):
    with open(filepath, 'rb') as f:
        content = f.read()
    return [p for p in content.split(b'\x00') if p]

def test_reconstructed_bin():
    """Test that the chunks were properly merged into reconstructed.bin."""
    recon_file = "/home/user/reconstructed.bin"
    assert os.path.exists(recon_file), f"File {recon_file} does not exist."

    with open(recon_file, 'rb') as f:
        content = f.read()

    assert content.startswith(b"ZSLIP_ARCHIVE_v1\n"), "reconstructed.bin does not start with the correct MAGIC_SIG."
    assert b"../../etc/passwd\0" in content, "reconstructed.bin is missing expected original paths."
    assert b"../../../../var/log/syslog\0" in content, "reconstructed.bin is missing expected original paths."

def test_sanitizer_exists():
    """Test that the C sanitizer source and binary exist."""
    assert os.path.exists("/home/user/sanitizer.c"), "/home/user/sanitizer.c does not exist."
    assert os.path.exists("/home/user/sanitizer"), "/home/user/sanitizer binary does not exist."
    assert os.access("/home/user/sanitizer", os.X_OK), "/home/user/sanitizer is not executable."

def test_clean_paths_accuracy():
    """Test that clean_paths.bin matches the ground truth with >= 1.0 accuracy."""
    agent_file = "/home/user/clean_paths.bin"
    truth_file = "/tests/ground_truth.bin"

    assert os.path.exists(agent_file), f"File {agent_file} does not exist."
    assert os.path.exists(truth_file), f"File {truth_file} does not exist."

    agent_paths = read_null_terminated(agent_file)
    truth_paths = read_null_terminated(truth_file)

    assert len(truth_paths) > 0, "Truth paths are empty."

    matches = sum(1 for a, t in zip(agent_paths, truth_paths) if a == t)
    accuracy = matches / len(truth_paths)

    assert accuracy >= 1.0, f"Accuracy {accuracy} is below threshold 1.0. Expected {len(truth_paths)} matches, got {matches}."

def test_rename_map():
    """Test that rename_map.txt contains the correct mappings."""
    map_file = "/home/user/rename_map.txt"
    assert os.path.exists(map_file), f"File {map_file} does not exist."

    with open(map_file, 'r') as f:
        content = f.read().strip()

    original_paths = [
        "../../etc/passwd",
        "valid_dir/../hidden/file.txt",
        "../../../../var/log/syslog",
        "normal_file.bin"
    ]

    truth_paths = [
        "etc/passwd",
        "valid_dir/hidden/file.txt",
        "var/log/syslog",
        "normal_file.bin"
    ]

    expected_lines = [f"{o} -> {c}" for o, c in zip(original_paths, truth_paths)]
    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    for expected in expected_lines:
        assert expected in actual_lines, f"Expected mapping '{expected}' not found in {map_file}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
