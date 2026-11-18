#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import subprocess
import pytest

def test_venv_exists():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"Virtual environment directory not found at {venv_path}"
    python_bin = os.path.join(venv_path, "bin", "python")
    assert os.path.isfile(python_bin), f"Python executable not found in virtual environment at {python_bin}"

def test_tiktoken_installed():
    venv_python = "/home/user/venv/bin/python"
    try:
        result = subprocess.run(
            [venv_python, "-c", "import tiktoken"],
            capture_output=True,
            text=True,
            check=True
        )
    except subprocess.CalledProcessError:
        pytest.fail("The 'tiktoken' package is not installed in the virtual environment /home/user/venv")

def test_longest_tokens_csv():
    csv_path = "/home/user/longest_tokens.csv"
    assert os.path.isfile(csv_path), f"Output CSV file not found at {csv_path}"

    expected_rows = [
        ["id", "token_count"],
        ["doc4", "29"],
        ["doc7", "21"],
        ["doc2", "20"],
        ["doc8", "18"],
        ["doc10", "16"]
    ]

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = list(csv.reader(f))

    assert reader == expected_rows, f"CSV content does not match expected output. Expected {expected_rows}, got {reader}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
