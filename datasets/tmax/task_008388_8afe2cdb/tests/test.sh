#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_script_exists_and_executable():
    script_path = '/home/user/resolve_deps.sh'
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_install_plan_matches_expected():
    install_plan_path = '/home/user/install_plan.txt'
    assert os.path.isfile(install_plan_path), f"The output file {install_plan_path} was not created."

    with open(install_plan_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "curl,7.84.0,1950,repo_alt",
        "jq,1.6.0,800,repo_main",
        "tar,1.34.1,2500,repo_alt",
        "wget,1.20.1,1500,repo_main",
        "TOTAL_SIZE,6750"
    ]

    assert actual_lines == expected_lines, (
        f"The content of {install_plan_path} does not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
