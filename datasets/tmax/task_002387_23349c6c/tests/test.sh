#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_report_txt_exists_and_correct():
    report_path = "/home/user/report.txt"

    assert os.path.exists(report_path), f"The file {report_path} does not exist. Did you write the decrypted payload to the correct location?"
    assert os.path.isfile(report_path), f"The path {report_path} is not a file."

    with open(report_path, "r") as f:
        content = f.read()

    expected_plaintext = "FLAG{G0_F0r3ns1cs_M4st3r_2024}"
    assert content.strip() == expected_plaintext, f"The content of {report_path} is incorrect. Expected '{expected_plaintext}', but got '{content.strip()}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
