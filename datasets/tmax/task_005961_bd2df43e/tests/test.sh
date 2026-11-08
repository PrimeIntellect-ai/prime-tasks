#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cn_txt_exists():
    output_path = "/home/user/cn.txt"
    assert os.path.isfile(output_path), f"Output file is missing at {output_path}. Did you save the Common Name?"

def test_cn_txt_content():
    output_path = "/home/user/cn.txt"
    assert os.path.isfile(output_path), f"Output file is missing at {output_path}."

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected_cn = "evil.corp.local"
    assert content == expected_cn, f"The content of {output_path} is incorrect. Expected '{expected_cn}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
