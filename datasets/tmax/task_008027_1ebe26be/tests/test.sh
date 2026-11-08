#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib

def get_expected_master_log_lines():
    lines = []
    for i in range(1, 61):
        lines.append(f"Sensor_A_1 reading {i}\n")
    for i in range(1, 61):
        lines.append(f"Sensor_A_2 reading {i}\n")
    for i in range(1, 61):
        lines.append(f"Sensor_B_1 reading {i}\n")
    for i in range(1, 61):
        lines.append(f"Sensor_B_2 reading {i}\n")
    return lines

def test_temp_extract_cleaned_up():
    temp_dir = "/home/user/temp_extract"
    assert not os.path.exists(temp_dir), f"Directory {temp_dir} should have been deleted."

def test_master_log_content():
    master_log_path = "/home/user/processed_data/master.log"
    assert os.path.isfile(master_log_path), f"File {master_log_path} does not exist."

    with open(master_log_path, "r") as f:
        actual_lines = f.readlines()

    expected_lines = get_expected_master_log_lines()
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in master.log, found {len(actual_lines)}."
    assert actual_lines == expected_lines, "The content of master.log does not match the expected concatenated order."

def test_checksum_file():
    checksum_path = "/home/user/processed_data/checksum.txt"
    assert os.path.isfile(checksum_path), f"File {checksum_path} does not exist."

    expected_lines = get_expected_master_log_lines()
    expected_content = "".join(expected_lines).encode('utf-8')
    expected_hash = hashlib.sha256(expected_content).hexdigest()

    with open(checksum_path, "r") as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Expected checksum {expected_hash}, but found '{actual_hash}'."

def test_chunks():
    processed_dir = "/home/user/processed_data"
    expected_chunks = {
        "chunk_aa": 50,
        "chunk_ab": 50,
        "chunk_ac": 50,
        "chunk_ad": 50,
        "chunk_ae": 40,
    }
    expected_master_lines = get_expected_master_log_lines()
    offset = 0

    for chunk_name, expected_lines_count in expected_chunks.items():
        chunk_path = os.path.join(processed_dir, chunk_name)
        assert os.path.isfile(chunk_path), f"Chunk file {chunk_path} does not exist."

        with open(chunk_path, "r") as f:
            lines = f.readlines()
            assert len(lines) == expected_lines_count, f"Expected {expected_lines_count} lines in {chunk_name}, found {len(lines)}."
            expected_lines = expected_master_lines[offset:offset + expected_lines_count]
            assert lines == expected_lines, f"The content of {chunk_name} does not match the corresponding portion of master.log."
        offset += expected_lines_count
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
