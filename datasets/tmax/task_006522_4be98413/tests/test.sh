#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_redacted_evidence_exists():
    path = "/home/user/redacted_evidence.log"
    assert os.path.exists(path), f"The file {path} does not exist. Did you successfully exploit the binary and redact the log?"
    assert os.path.isfile(path), f"The path {path} exists but is not a file."

def test_redacted_evidence_content():
    path = "/home/user/redacted_evidence.log"
    if not os.path.exists(path):
        pytest.fail(f"Cannot check content because {path} is missing.")

    with open(path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "[INFO] Admin login from XXX.XXX.XXX.15",
        "[WARN] Failed attempt from XXX.XXX.XXX.2",
        "[INFO] Data accessed by XXX.XXX.XXX.44"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {path}, but found {len(actual_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Actual: '{actual}'"

def test_original_binary_unmodified():
    # Ensure the user didn't just recompile the binary to bypass the challenge
    source_path = "/home/user/upload_handler.c"
    if os.path.exists(source_path):
        with open(source_path, "r") as f:
            content = f.read()
            assert "0x1337BEEF" in content, "The original source code appears to have been modified."
            assert "0x4B" in content, "The original source code appears to have been modified."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
