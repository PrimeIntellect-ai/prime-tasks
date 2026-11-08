#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import hashlib
import os
import pytest


def test_migration_targets_file_exists():
    assert os.path.isfile('/home/user/migration_targets.txt'), "The output file /home/user/migration_targets.txt was not created."


def test_migration_targets_contents():
    with open('/home/user/migration_targets.txt', 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        'src/app.py',
        'src/config.py'
    ]

    assert lines == expected_lines, f"The contents of /home/user/migration_targets.txt do not match the expected output. Got: {lines}"


def test_original_files_unmodified():
    expected_contents = {
        '/home/user/legacy_project/src/app.py': b'def main():\n    print "Hello World"\n',
        '/home/user/legacy_project/src/utils.py': b'def log(msg):\n    print("Log: " + msg)\n',
        '/home/user/legacy_project/src/helper.py': b"def help():\n    print 'Help info'\n",
        '/home/user/legacy_project/src/config.py': b"    print 'Config loaded'\n",
        '/home/user/legacy_project/src/math.py': b'x = 5 + 2\n',
    }

    expected_files = list(expected_contents) + [
        '/home/user/legacy_project/checksums.md5'
    ]
    for file_path in expected_files:
        assert os.path.isfile(file_path), f"The original file {file_path} is missing. It should not have been modified or deleted."

    for file_path, expected in expected_contents.items():
        with open(file_path, 'rb') as f:
            actual = f.read()
        assert actual == expected, f"The original file {file_path} was modified."

    checksum_order = ['app.py', 'utils.py', 'config.py', 'math.py']
    expected_checksum_file = ''.join(
        f"{hashlib.md5(expected_contents['/home/user/legacy_project/src/' + name]).hexdigest()}  src/{name}\n"
        for name in checksum_order
    )
    expected_checksum_file += "00000000000000000000000000000000  src/helper.py\n"

    with open('/home/user/legacy_project/checksums.md5', 'r', newline='') as f:
        actual_checksum_file = f.read()
    assert actual_checksum_file == expected_checksum_file, "The original checksum file was modified."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
