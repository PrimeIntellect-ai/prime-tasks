#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_recovered_clean_exists():
    """Check if the recovered_clean.txt file was created."""
    file_path = "/home/user/evidence/recovered_clean.txt"
    assert os.path.isfile(file_path), f"The file {file_path} is missing. The script did not generate the output."


def test_recovered_clean_content():
    """Validate that recovered_clean.txt matches the expected redacted text."""
    actual_path = "/home/user/evidence/recovered_clean.txt"
    expected_path = "/tests/.expected_clean.txt"

    assert os.path.isfile(actual_path), f"{actual_path} must exist to check its content."
    assert os.path.isfile(expected_path), f"{expected_path} is missing from the verification environment."

    with open(actual_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    with open(expected_path, "r", encoding="utf-8") as f:
        expected_content = f.read()

    assert actual_content == expected_content, (
        "The content of recovered_clean.txt does not exactly match the expected redacted text. "
        "Check your decryption steps, regex patterns for IP/email redaction, and ensure no extra "
        "newlines or trailing spaces were added."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
