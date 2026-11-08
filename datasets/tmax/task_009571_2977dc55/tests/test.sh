#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

def test_extracted_ip_file_exists():
    """Check if the extracted_ip.txt file exists."""
    file_path = "/home/user/forensics/extracted_ip.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The task requires saving the extracted IP to this file."

def test_extracted_ip_content():
    """Check if the extracted_ip.txt file contains exactly the correct IP address."""
    file_path = "/home/user/forensics/extracted_ip.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # The file should contain only the IP address and an optional trailing newline.
    cleaned_content = content.strip()
    expected_ip = "203.0.113.85"

    assert cleaned_content == expected_ip, f"File {file_path} contains '{cleaned_content}' instead of the expected IP address '{expected_ip}'."

    # Ensure there are no extra lines or characters before/after stripping (apart from whitespace/newlines)
    assert len(content.replace('\n', '').replace('\r', '').strip()) == len(expected_ip), f"File {file_path} contains extra characters besides the IP address and newline."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
