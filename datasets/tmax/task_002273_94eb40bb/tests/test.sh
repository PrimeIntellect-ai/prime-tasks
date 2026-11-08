#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_log_files_deleted():
    log_dir = "/home/user/logs"
    for root, dirs, files in os.walk(log_dir):
        for f in files:
            assert not f.endswith(".log"), f"Original log file {os.path.join(root, f)} was not deleted"

def test_clog_files_exist_and_content_matches():
    expected_files = {
        "/home/user/logs/web/access.clog": (
            "ERROR~3 Connection timeout~3.\n"
            "INFO OK\n"
            "WARN~4 Retrying connection~3!\n"
        ),
        "/home/user/logs/db/query.clog": (
            "DEBUG SELECT * FROM users WHERE age > 20~3;\n"
            "INFO  Query executed in 0.~301s\n"
        ),
        "/home/user/logs/app/system.clog": (
            "FATAL System crash~5out\n"
            "DEBUG Rebooting~9 now\n"
        )
    }

    for filepath, expected_content in expected_files.items():
        assert os.path.isfile(filepath), f"Compressed file {filepath} is missing"
        with open(filepath, "r") as f:
            content = f.read()
        assert content == expected_content, f"Content of {filepath} does not match expected compressed state. Expected:\n{expected_content}\nGot:\n{content}"

def test_final_size_file():
    size_file = "/home/user/final_size.txt"
    assert os.path.isfile(size_file), f"File {size_file} is missing"

    with open(size_file, "r") as f:
        content = f.read().strip()

    assert content == "190", f"Expected final size to be 190, but got {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
