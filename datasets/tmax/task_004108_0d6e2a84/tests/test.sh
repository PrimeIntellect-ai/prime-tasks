#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_c2_domain_file_exists():
    """Test that the output file /home/user/c2_domain.txt exists."""
    path = "/home/user/c2_domain.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you save the decoded URL?"

def test_c2_domain_content():
    """Test that the output file contains the correctly decoded C2 URL without precision loss."""
    path = "/home/user/c2_domain.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_url = "http://evil-c2-server.internal/api/v1/beacon"

    assert content == expected_url, (
        f"The decoded URL is incorrect.\n"
        f"Expected: {expected_url}\n"
        f"Got:      {content}\n"
        f"Make sure you fixed the precision loss issue in decode.py!"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
