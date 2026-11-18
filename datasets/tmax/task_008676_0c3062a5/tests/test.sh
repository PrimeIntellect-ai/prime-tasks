#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_organized_docs_directory_exists():
    assert os.path.isdir('/home/user/organized_docs'), "The output directory /home/user/organized_docs/ was not created."

def test_file_alpha_processed_correctly():
    target_path = '/home/user/organized_docs/print_docs/file_alpha.pdf'
    assert os.path.isfile(target_path), f"Expected file {target_path} is missing."

    with open(target_path, 'rb') as f:
        content = f.read()

    expected_content = b"\x25\x50\x44\x46\x01\x02\x03\x04\x05"
    assert content == expected_content, f"The contents of {target_path} do not match the expected copied bytes."

def test_file_beta_processed_correctly():
    target_path = '/home/user/organized_docs/assets/file_beta.png'
    assert os.path.isfile(target_path), f"Expected file {target_path} is missing."

    with open(target_path, 'rb') as f:
        content = f.read()

    expected_content = b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00"
    assert content == expected_content, f"The contents of {target_path} do not match the expected copied bytes."

def test_file_gamma_processed_correctly():
    target_path = '/home/user/organized_docs/metadata/file_gamma.json'
    assert os.path.isfile(target_path), f"Expected file {target_path} is missing."

    with open(target_path, 'rb') as f:
        content = f.read()

    expected_content = b"\x7B\x22\x74\x69\x74\x6C\x65\x22\x3A"
    assert content == expected_content, f"The contents of {target_path} do not match the expected copied bytes."

def test_file_delta_processed_correctly():
    target_path = '/home/user/organized_docs/drafts/file_delta.txt'
    assert os.path.isfile(target_path), f"Expected file {target_path} is missing."

    with open(target_path, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_content = "API Documentation v2"
    assert content == expected_content, f"The decoded text in {target_path} is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
