#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

BASE_DIR = '/home/user/artifact_repo'
LOG_FILE = '/home/user/updated_artifacts.log'

def test_log_file_contents():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} is missing."

    with open(LOG_FILE, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_paths = [
        os.path.join(BASE_DIR, 'build_all.py'),
        os.path.join(BASE_DIR, 'pkg_a', 'src', 'build.py'),
        os.path.join(BASE_DIR, 'pkg_b', 'fetch.py')
    ]

    assert lines == expected_paths, f"Log file contents do not match expected sorted paths. Got: {lines}"

def test_non_python_file_unchanged():
    file_path = os.path.join(BASE_DIR, 'pkg_a', 'info.txt')
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read()

    assert 'http://old-repo.local/v1/docs.zip' in content, f"Non-python file {file_path} was incorrectly modified."
    assert 'curated_by' not in content, f"Non-python file {file_path} should not have 'curated_by' inserted."

def test_already_migrated_python_file_unchanged():
    file_path = os.path.join(BASE_DIR, 'pkg_c', 'build.py')
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read()

    assert 'artifact_url = "https://secure-repo.global/v2/pkg_c.tar.gz"' in content, f"Already migrated file {file_path} was incorrectly modified."
    assert 'curated_by' not in content, f"Already migrated file {file_path} should not have 'curated_by' inserted."

def test_target_file_pkg_a_build_py():
    file_path = os.path.join(BASE_DIR, 'pkg_a', 'src', 'build.py')
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        lines = f.read().splitlines()

    assert lines[0] == 'name = "pkg_a"', f"First line of {file_path} is incorrect."
    assert lines[1] == 'artifact_url = "https://secure-repo.global/v2/pkg_a.tar.gz"', f"Second line of {file_path} is incorrect or not updated."
    assert lines[2] == 'curated_by = "artifact_manager"', f"Third line of {file_path} is incorrect. Missing or misplaced curated_by insertion."
    assert lines[3] == 'version = "1.0"', f"Fourth line of {file_path} is incorrect."

def test_target_file_pkg_b_fetch_py():
    file_path = os.path.join(BASE_DIR, 'pkg_b', 'fetch.py')
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        lines = f.read().splitlines()

    assert lines[0] == 'name = "pkg_b"', f"First line of {file_path} is incorrect."
    assert lines[1] == '# Fetch script', f"Second line of {file_path} is incorrect."
    assert lines[2] == 'artifact_url = "https://secure-repo.global/v2/pkg_b.tar.gz"', f"Third line of {file_path} is incorrect or not updated."
    assert lines[3] == 'curated_by = "artifact_manager"', f"Fourth line of {file_path} is incorrect. Missing or misplaced curated_by insertion."

def test_target_file_build_all_py():
    file_path = os.path.join(BASE_DIR, 'build_all.py')
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        lines = f.read().splitlines()

    assert lines[0] == 'artifact_url = "https://secure-repo.global/v2/master.zip"', f"First line of {file_path} is incorrect or not updated."
    assert lines[1] == 'curated_by = "artifact_manager"', f"Second line of {file_path} is incorrect. Missing or misplaced curated_by insertion."
    assert lines[2] == 'print("Building all")', f"Third line of {file_path} is incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
