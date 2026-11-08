#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

def get_entry_point(bin_path):
    result = subprocess.run(["readelf", "-h", bin_path], capture_output=True, text=True)
    for line in result.stdout.split('\n'):
        if "Entry point address:" in line:
            return line.split()[-1]
    return "0x0"

@pytest.fixture
def expected_csv_content():
    ep_alpha = get_entry_point("/bin/ls")
    ep_beta = get_entry_point("/bin/cat")
    ep_gamma = get_entry_point("/bin/echo")

    return (
        "build_id,entry_point,error_count\n"
        f"build_alpha,{ep_alpha},2\n"
        f"build_beta,{ep_beta},0\n"
        f"build_gamma,{ep_gamma},1\n"
    )

def test_report_csv_exists_and_correct(expected_csv_content):
    report_path = "/home/user/report.csv"
    assert os.path.isfile(report_path), f"The report file {report_path} does not exist."

    with open(report_path, 'r') as f:
        actual_csv = f.read()

    assert actual_csv.strip() == expected_csv_content.strip(), "CSV content does not match expected output."

def test_chunks_directory_and_files(expected_csv_content):
    chunks_dir = "/home/user/chunks"
    assert os.path.isdir(chunks_dir), f"The directory {chunks_dir} does not exist."

    chunks = sorted([f for f in os.listdir(chunks_dir) if f.startswith('part_')])
    assert len(chunks) > 0, "No chunks with prefix 'part_' found in /home/user/chunks."

    # Check that all chunks except the last one are exactly 40 bytes
    for chunk in chunks[:-1]:
        chunk_path = os.path.join(chunks_dir, chunk)
        assert os.path.getsize(chunk_path) == 40, f"Chunk {chunk} is not exactly 40 bytes."

    # split may produce a shorter final chunk, but it must never exceed 40 bytes.
    last_chunk_path = os.path.join(chunks_dir, chunks[-1])
    last_chunk_size = os.path.getsize(last_chunk_path)
    assert 0 < last_chunk_size <= 40, "The final chunk must contain between 1 and 40 bytes."

    # Reassemble and verify
    reassembled = ""
    for chunk in chunks:
        with open(os.path.join(chunks_dir, chunk), 'r') as f:
            reassembled += f.read()

    assert reassembled.strip() == expected_csv_content.strip(), "Reassembled chunks do not match the expected CSV."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
