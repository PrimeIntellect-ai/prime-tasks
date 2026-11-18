#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

OUTPUT_PATH = "/home/user/optimal_path.txt"
EXPECTED_PATH = "WebFrontend,Cache,LogServer,ColdStorage"

def test_optimal_path_file_exists():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."

def test_optimal_path_content():
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == EXPECTED_PATH, (
        f"The content of {OUTPUT_PATH} is incorrect.\n"
        f"Expected: '{EXPECTED_PATH}'\n"
        f"Found: '{content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
