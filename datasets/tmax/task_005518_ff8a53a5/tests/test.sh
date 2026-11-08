#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_headers_log_exists():
    log_path = '/home/user/workspace/headers.log'
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

def test_headers_log_contents():
    log_path = '/home/user/workspace/headers.log'
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        'archive_alpha.zip:image_asset.png:89504e47',
        'archive_beta.zip:core_module.so:7f454c46'
    }

    assert len(lines) == 2, f"Expected exactly 2 lines in headers.log, found {len(lines)}."

    actual_lines = set(lines)
    assert actual_lines == expected_lines, f"Expected lines {expected_lines}, but got {actual_lines}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
