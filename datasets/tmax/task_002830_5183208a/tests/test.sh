#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import subprocess
import pytest

def test_venv_exists_and_packages_installed():
    """Test that the virtual environment exists and numpy/scipy are installed."""
    venv_python = "/home/user/venv/bin/python"
    assert os.path.isfile(venv_python), f"Virtual environment python executable not found at {venv_python}"

    # Check if numpy is installed
    result_numpy = subprocess.run([venv_python, "-c", "import numpy"], capture_output=True)
    assert result_numpy.returncode == 0, "numpy is not installed in the virtual environment."

    # Check if scipy is installed
    result_scipy = subprocess.run([venv_python, "-c", "import scipy"], capture_output=True)
    assert result_scipy.returncode == 0, "scipy is not installed in the virtual environment."

def test_result_log_content():
    """Test that the result.log file contains the correct output format and values."""
    log_file = "/home/user/result.log"
    assert os.path.isfile(log_file), f"Result log file not found at {log_file}"

    with open(log_file, "r") as f:
        content = f.read().strip()

    expected_content = (
        "Highest: graph_B.csv\n"
        "Lowest: graph_A.csv\n"
        "T-stat: -2.55\n"
        "P-value: 0.0344"
    )

    # Check exact match or very close match
    assert content == expected_content, f"Content of {log_file} does not match the expected output.\nExpected:\n{expected_content}\nGot:\n{content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
