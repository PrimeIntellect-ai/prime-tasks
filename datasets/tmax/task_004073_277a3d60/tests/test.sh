#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_leak_func_txt():
    file_path = "/home/user/report/leak_func.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_func = "process_metrics_unfreed_alloc"
    assert content == expected_func, f"Expected '{expected_func}' in {file_path}, but got '{content}'"

def test_query_out_csv():
    file_path = "/home/user/report/query_out.csv"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip().replace("\r\n", "\n")

    expected_csv = "7,0.99\n6,0.88\n4,0.95\n3,0.85\n2,0.9"
    assert content == expected_csv, f"CSV content does not match expected output. Got:\n{content}"

def test_wal_checkpointed():
    wal_path = "/home/user/app/data.db-wal"
    # If the WAL file exists, it should be 0 bytes after a full checkpoint, 
    # or it might be removed entirely depending on the checkpoint mode.
    if os.path.exists(wal_path):
        size = os.path.getsize(wal_path)
        assert size == 0, f"WAL file {wal_path} is not fully checkpointed (size is {size} bytes)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
