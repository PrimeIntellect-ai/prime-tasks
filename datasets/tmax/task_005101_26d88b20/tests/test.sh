#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hmac
import hashlib

def test_cwe_file():
    cwe_path = "/home/user/cwe.txt"
    assert os.path.exists(cwe_path), f"File {cwe_path} does not exist."
    assert os.path.isfile(cwe_path), f"{cwe_path} is not a regular file."

    with open(cwe_path, "r") as f:
        content = f.read().strip()

    assert content == "CWE-601", f"Expected CWE-601 in {cwe_path}, but got '{content}'"

def test_exploit_file():
    exploit_path = "/home/user/exploit.txt"
    assert os.path.exists(exploit_path), f"File {exploit_path} does not exist."
    assert os.path.isfile(exploit_path), f"{exploit_path} is not a regular file."

    with open(exploit_path, "r") as f:
        content = f.read().strip()

    # Calculate the expected signature dynamically
    secret_key = b"sup3r_s3cr3t_k3y"
    url = "//evil.com"
    expected_sig = hmac.new(secret_key, url.encode('utf-8'), hashlib.md5).hexdigest()
    expected_exploit = f"redirect_url={url}&signature={expected_sig}"

    assert content == expected_exploit, f"Expected '{expected_exploit}' in {exploit_path}, but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
