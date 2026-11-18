#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import py_compile
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest

SCRIPT = '/home/user/organize.py'
INCOMING = '/home/user/incoming'
ORGANIZED = '/home/user/organized'


def test_organized_directory_exists():
    """Test that the organized directory was created."""
    assert os.path.isdir(ORGANIZED), "The directory /home/user/organized/ was not created."


def test_organized_files_exist():
    """Test that exactly the expected output files exist in the organized directory."""
    expected_files = {'clean_log_000.txt', 'clean_log_001.txt', 'clean_log_002.txt'}
    actual_files = set(os.listdir(ORGANIZED))
    assert actual_files == expected_files, f"Expected files {expected_files} in /home/user/organized/, but found {actual_files}."


def test_file_contents_and_encoding():
    """Test that the files have the correct number of lines, are UTF-8 encoded, and have correct content."""
    expected_lines = [f"Line {i:04d}: Legacy project log entry with special char: € é ñ\n" for i in range(1, 1251)]

    file_info = [
        ('clean_log_000.txt', 500, expected_lines[0:500]),
        ('clean_log_001.txt', 500, expected_lines[500:1000]),
        ('clean_log_002.txt', 250, expected_lines[1000:1250]),
    ]

    for filename, expected_line_count, expected_content in file_info:
        filepath = os.path.join(ORGANIZED, filename)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        except UnicodeDecodeError:
            pytest.fail(f"File {filename} is not valid UTF-8.")

        assert len(lines) == expected_line_count, f"File {filename} should have {expected_line_count} lines, but has {len(lines)}."
        assert lines == expected_content, f"Content of {filename} does not match expected output."


def test_python_script_exists_and_processes_fresh_input():
    """Execute the submitted Python script against fresh, unpredictable input."""
    assert os.path.isfile(SCRIPT), f"Required Python script {SCRIPT} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file."
    try:
        py_compile.compile(SCRIPT, doraise=True)
    except py_compile.PyCompileError as exc:
        pytest.fail(f"{SCRIPT} is not a valid Python script: {exc}")

    backup_root = tempfile.mkdtemp(prefix='organize-verifier-')
    incoming_backup = os.path.join(backup_root, 'incoming')
    organized_backup = os.path.join(backup_root, 'organized')
    shutil.copytree(INCOMING, incoming_backup)
    shutil.copytree(ORGANIZED, organized_backup)

    try:
        total = 751 + secrets.randbelow(700)
        nonce = secrets.token_hex(12)
        expected_lines = [
            f"Fresh {nonce} {i:04d}: cp1252 symbols € é ñ — “quoted”\n"
            for i in range(1, total + 1)
        ]
        compressed = gzip.compress(''.join(expected_lines).encode('cp1252'))
        cut1 = len(compressed) // 3
        cut2 = (2 * len(compressed)) // 3
        chunks = (compressed[:cut1], compressed[cut1:cut2], compressed[cut2:])

        shutil.rmtree(INCOMING)
        os.makedirs(INCOMING)
        for name, data in zip(('chunk_a.gz', 'chunk_b.gz', 'chunk_c.gz'), chunks):
            with open(os.path.join(INCOMING, name), 'wb') as f:
                f.write(data)

        shutil.rmtree(ORGANIZED)
        result = subprocess.run(
            ['python3', SCRIPT],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Running {SCRIPT} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isdir(ORGANIZED), "The script did not create /home/user/organized/."

        expected_files = {
            f"clean_log_{index:03d}.txt"
            for index in range((total + 499) // 500)
        }
        actual_files = set(os.listdir(ORGANIZED))
        assert actual_files == expected_files, (
            f"Fresh run expected files {expected_files}, but found {actual_files}."
        )

        for index, start in enumerate(range(0, total, 500)):
            filename = f"clean_log_{index:03d}.txt"
            path = os.path.join(ORGANIZED, filename)
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    actual_lines = f.readlines()
            except UnicodeDecodeError:
                pytest.fail(f"Fresh output {filename} is not valid UTF-8.")
            assert actual_lines == expected_lines[start:start + 500], (
                f"Fresh output content in {filename} is incorrect."
            )
    finally:
        if os.path.exists(INCOMING):
            shutil.rmtree(INCOMING)
        if os.path.exists(ORGANIZED):
            shutil.rmtree(ORGANIZED)
        shutil.copytree(incoming_backup, INCOMING)
        shutil.copytree(organized_backup, ORGANIZED)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
