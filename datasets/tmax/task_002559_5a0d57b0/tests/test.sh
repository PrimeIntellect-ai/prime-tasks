#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

DIFF_FILE = "/home/user/endpoint_changes.diff"

EXPECTED_DIFF_LINES = [
    "--- second_highest",
    "+++ highest",
    "@@ -1,5 +1,4 @@",
    " /ast",
    "+/build",
    " /compile",
    " /format",
    " /lint",
    "-/macro-expand"
]

def test_diff_file_exists():
    assert os.path.isfile(DIFF_FILE), f"The output file {DIFF_FILE} does not exist."

def test_diff_file_content():
    with open(DIFF_FILE, "r") as f:
        content = f.read().strip().splitlines()

    # Sometimes diff output might have trailing spaces or slightly different context lines,
    # but with the given simple inputs, the unified diff should exactly match EXPECTED_DIFF_LINES.
    # We will strip trailing whitespaces for robust comparison.
    cleaned_content = [line.rstrip() for line in content]

    assert cleaned_content == EXPECTED_DIFF_LINES, (
        f"The content of {DIFF_FILE} does not match the expected unified diff.\n"
        f"Expected:\n{chr(10).join(EXPECTED_DIFF_LINES)}\n\n"
        f"Got:\n{chr(10).join(cleaned_content)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
