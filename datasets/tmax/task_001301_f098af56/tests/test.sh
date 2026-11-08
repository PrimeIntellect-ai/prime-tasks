#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_virtual_environment_created():
    venv_dir = "/home/user/venv"
    assert os.path.isdir(venv_dir), f"Virtual environment directory {venv_dir} does not exist."

    python_bin = os.path.join(venv_dir, "bin", "python")
    assert os.path.isfile(python_bin) and os.access(python_bin, os.X_OK), f"Python executable not found or not executable at {python_bin}."

def test_packages_installed_in_venv():
    pip_bin = "/home/user/venv/bin/pip"
    assert os.path.isfile(pip_bin) and os.access(pip_bin, os.X_OK), f"pip executable not found at {pip_bin}."

    result = subprocess.run([pip_bin, "list"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run pip list in the virtual environment."

    # Check for pandas and numpy as requested in the task
    assert "pandas" in result.stdout.lower(), "pandas is not installed in the virtual environment."
    assert "numpy" in result.stdout.lower(), "numpy is not installed in the virtual environment."

def test_top_matches_csv_exists_and_correct():
    output_file = "/home/user/top_matches.csv"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    expected_content = (
        "user_id,item_id,score\n"
        "1,104,0.8700\n"
        "2,102,0.7500\n"
        "3,103,0.8400\n"
        "4,101,0.6500"
    )

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content == expected_content, (
        f"Content of {output_file} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
