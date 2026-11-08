#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import pytest

def test_solution_script_exists_and_executable():
    path = "/home/user/solution.sh"
    assert os.path.isfile(path), f"Solution script missing: {path}"

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH), \
        f"Solution script is not executable: {path}"

def test_solution_script_logic():
    path = "/home/user/solution.sh"
    # Test the script's addition logic
    try:
        result = subprocess.run([path, "10", "20"], capture_output=True, text=True, check=True)
        output = result.stdout.strip()
        assert output == "30", f"Solution script did not output the correct sum. Expected '30', got '{output}'"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {path} failed: {e.stderr}")

def test_final_answer_file():
    path = "/home/user/final_answer.txt"
    assert os.path.isfile(path), f"Final answer file missing: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_answer = str(83724 + 40404)
    assert content == expected_answer, f"Final answer is incorrect. Expected '{expected_answer}', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
