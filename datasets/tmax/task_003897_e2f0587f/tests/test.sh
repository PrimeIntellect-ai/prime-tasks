#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_attacker_txt():
    path = "/home/user/attacker.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "172.16.50.100", f"Expected attacker IP '172.16.50.100', but got '{content}'."

def test_cert_expiry_txt():
    path = "/home/user/cert_expiry.txt"
    pem_path = "/home/user/service.pem"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.path.isfile(pem_path), f"File {pem_path} does not exist."

    # Get the true expiration date
    cmd = ["openssl", "x509", "-in", pem_path, "-noout", "-enddate"]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    # Output is like "notAfter=Oct 10 23:59:59 2024 GMT"
    expected_date = result.stdout.strip().split("=", 1)[1]

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == expected_date, f"Expected certificate expiration '{expected_date}', but got '{content}'."

def test_payload_txt_no_spaces_and_works():
    path = "/home/user/payload.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    assert " " not in content, "The payload contains space characters, which is not allowed."
    assert content.strip() != "", "The payload file is empty."

    # Execute the payload
    # The payload is expected to output the contents of /home/user/secret.key
    cmd = ["bash", "-c", content]
    result = subprocess.run(cmd, capture_output=True, text=True)

    output = result.stdout.strip()
    expected_output = "FLAG{b4sh_1nj3ct10n_m4st3r}"

    assert output == expected_output, f"Executing payload did not yield the correct secret. Got: '{output}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
