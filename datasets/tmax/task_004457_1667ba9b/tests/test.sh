#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cpp_source_and_executable_exist():
    source_path = "/home/user/config_processor.cpp"
    exe_path = "/home/user/config_processor"
    assert os.path.isfile(source_path), f"Source file {source_path} is missing."
    assert os.path.isfile(exe_path), f"Executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."

def test_config_report_content():
    report_path = "/home/user/config_report.md"
    assert os.path.isfile(report_path), f"Output file {report_path} is missing."

    expected_content = """## Role: cache
Latest Timestamp: 300
Server ID: 5
Configuration:
eviction=LRU
memlimit=4G

## Role: db
Latest Timestamp: 200
Server ID: 2
Configuration:
maxconnections=200
port=5432
timeout=30

## Role: web
Latest Timestamp: 150
Server ID: 3
Configuration:
port=8080
workers=4"""

    with open(report_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content.strip(), f"Content of {report_path} does not match the expected report."

def test_pipeline_log_content():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    expected_log = """[INFO] Processed server_5_cache_300.conf: 2 valid keys found.
[INFO] Processed server_2_db_200.conf: 3 valid keys found.
[INFO] Processed server_3_web_150.conf: 2 valid keys found."""

    with open(log_path, "r") as f:
        actual_log = f.read().strip()

    assert actual_log == expected_log.strip(), f"Content of {log_path} does not match the expected log."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
