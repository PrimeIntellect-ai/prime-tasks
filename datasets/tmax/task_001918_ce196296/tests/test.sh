#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_malicious_ips_file_exists():
    """Verify that the output file was created at the correct location."""
    file_path = "/home/user/malicious_ips.txt"
    assert os.path.isfile(file_path), f"The required output file is missing: {file_path}"

def test_malicious_ips_content():
    """Verify that the output file contains the correct sorted list of malicious IPs."""
    file_path = "/home/user/malicious_ips.txt"

    # These are the expected IPs based on the setup data where the payload 
    # contains the signature '[C2_EXFIL_START]'.
    expected_ips = [
        "10.0.5.55",
        "172.16.0.4"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip()

    # Extract non-empty lines
    actual_ips = [line.strip() for line in content.split('\n') if line.strip()]

    assert actual_ips == expected_ips, (
        f"The contents of {file_path} are incorrect. "
        f"Expected strictly ascending sorted IPs: {expected_ips}, but got: {actual_ips}. "
        "Ensure you are correctly extracting the key, decrypting the payload, matching the signature, and sorting the results."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
