#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_build_plan_exists_and_correct():
    build_plan_path = "/home/user/build_plan.txt"
    assert os.path.exists(build_plan_path), f"The file {build_plan_path} does not exist. Did you generate the build plan?"
    assert os.path.isfile(build_plan_path), f"The path {build_plan_path} is not a valid file."

    expected_lines = [
        "LibCore@1.2.0",
        "LibData@1.5.0",
        "LibNet@2.1.0",
        "AppX@1.0.0"
    ]

    with open(build_plan_path, "r") as f:
        # Read lines, stripping trailing whitespaces and ignoring empty lines
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The content of {build_plan_path} does not match the expected build plan.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
