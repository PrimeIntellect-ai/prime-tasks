#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_restored_project_dir_exists():
    dir_path = "/home/user/restored_project"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist. The task requires creating it."

def test_config_yaml_restored():
    file_path = "/home/user/restored_project/config.yaml"
    assert os.path.isfile(file_path), f"File {file_path} was not restored."
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    expected_content = "port: 8080\nhost: localhost"
    assert content == expected_content, f"Content of {file_path} is incorrect. Expected {repr(expected_content)}, got {repr(content)}."

def test_main_py_restored():
    file_path = "/home/user/restored_project/main.py"
    assert os.path.isfile(file_path), f"File {file_path} was not restored."
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    expected_content = "print('Hello Archive')"
    assert content == expected_content, f"Content of {file_path} is incorrect. Expected {repr(expected_content)}, got {repr(content)}."

def test_summary_txt_created_and_sorted():
    file_path = "/home/user/restored_project/summary.txt"
    assert os.path.isfile(file_path), f"File {file_path} was not created."
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["config.yaml", "main.py"]
    assert lines == expected_lines, f"Content of {file_path} is incorrect or not sorted. Expected {expected_lines}, got {lines}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
