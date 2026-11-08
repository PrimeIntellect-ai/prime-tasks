#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_magic_summary_exists():
    assert os.path.isfile("/home/user/magic_summary.txt"), "The file /home/user/magic_summary.txt was not created."

def test_magic_summary_content():
    expected_lines = [
        "sample1.tar.gz:alpha.bin:deadbeef",
        "sample1.tar.gz:beta.bin:11223344",
        "sample2.tar.gz:gamma.bin:cafebabe"
    ]

    with open("/home/user/magic_summary.txt", "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in summary, found {len(lines)}."

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{lines[i]}'."

def test_no_permanent_extraction():
    # Check that the bin files weren't permanently extracted to /home/user/datasets
    assert not os.path.exists("/home/user/datasets/alpha.bin"), "alpha.bin was permanently extracted."
    assert not os.path.exists("/home/user/datasets/beta.bin"), "beta.bin was permanently extracted."
    assert not os.path.exists("/home/user/datasets/gamma.bin"), "gamma.bin was permanently extracted."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
