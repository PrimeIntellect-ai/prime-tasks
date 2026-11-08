#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import tempfile
import pytest

def test_directories_deleted():
    assert not os.path.exists("/home/user/app_logs"), "Directory /home/user/app_logs/ should have been deleted."
    assert not os.path.exists("/home/user/condensed_logs"), "Directory /home/user/condensed_logs/ should have been deleted."

def test_archive_exists_and_contents():
    tar_path = "/home/user/failed_logs_archive.tar"
    assert os.path.isfile(tar_path), f"Archive {tar_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(tar_path, "r") as tar:
            tar.extractall(path=tmpdir)

        server1_csv = os.path.join(tmpdir, "condensed_logs", "server1.csv")
        server2_csv = os.path.join(tmpdir, "condensed_logs", "server2.csv")

        assert os.path.isfile(server1_csv), "condensed_logs/server1.csv not found in the archive. Ensure the archive contains the condensed_logs directory."
        assert os.path.isfile(server2_csv), "condensed_logs/server2.csv not found in the archive. Ensure the archive contains the condensed_logs directory."

        with open(server1_csv, "r") as f:
            content1 = f.read().strip()
        expected1 = "2023-10-01T10:00:00Z,E1,OOM\n2023-10-01T10:10:00Z,DBP,CTO"
        assert content1 == expected1, f"Incorrect content in server1.csv. Got:\n{content1}\nExpected:\n{expected1}"

        with open(server2_csv, "r") as f:
            content2 = f.read().strip()
        expected2 = "2023-10-02T11:00:00Z,W2,OOM"
        assert content2 == expected2, f"Incorrect content in server2.csv. Got:\n{content2}\nExpected:\n{expected2}"

def test_space_saved_calculation():
    tar_path = "/home/user/failed_logs_archive.tar"
    txt_path = "/home/user/space_saved.txt"

    assert os.path.isfile(txt_path), f"File {txt_path} does not exist."
    assert os.path.isfile(tar_path), f"Archive {tar_path} does not exist."

    tar_size = os.path.getsize(tar_path)
    expected_original_size = 634
    expected_savings = expected_original_size - tar_size

    with open(txt_path, "r") as f:
        content = f.read().strip()

    try:
        actual_savings = int(content)
    except ValueError:
        pytest.fail(f"Content of {txt_path} is not a valid integer: '{content}'")

    assert actual_savings == expected_savings, f"Expected savings {expected_savings} bytes, but got {actual_savings} bytes in {txt_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
