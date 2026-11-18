#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import zlib
import base64
import subprocess
import pytest

SCRIPT_PATH = "/home/user/custom_compress.py"


def test_custom_compress_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_custom_compress_script_behavior():
    test_inputs = [
        b"",
        b"Hello, Artifact Manager. This is a test.",
        bytes(range(256)) + b"\x00\xff\n\r" * 31,
        os.urandom(4097),
    ]

    for data in test_inputs:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            input=data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        expected = base64.b64encode(zlib.compress(data, level=9)) + b"\n"
        assert result.returncode == 0, (
            f"The compressor exited with status {result.returncode}: "
            f"{result.stderr.decode('utf-8', errors='replace')}"
        )
        assert result.stdout == expected, (
            "custom_compress.py did not produce the required zlib level-9 "
            "compressed, standard Base64-encoded output with one trailing newline."
        )
        assert result.stderr == b"", "custom_compress.py wrote unexpected output to stderr."


def test_archive_vault_contents():
    vault_path = "/home/user/archive_vault.txt"
    assert os.path.isfile(vault_path), f"The output file {vault_path} does not exist."

    # Dynamically compute the expected contents
    repo_dir = "/home/user/binary_repo"
    dat_files = []
    for root, dirs, files in os.walk(repo_dir):
        for file in files:
            if file.endswith(".dat"):
                dat_files.append(os.path.join(root, file))

    dat_files.sort()

    expected_lines = []
    for filepath in dat_files:
        expected_lines.append(filepath.encode('utf-8'))
        with open(filepath, 'rb') as f:
            data = f.read()
        compressed = zlib.compress(data, level=9)
        encoded = base64.b64encode(compressed)
        expected_lines.append(encoded)

    expected_content = b"\n".join(expected_lines) + b"\n" if expected_lines else b""

    with open(vault_path, 'rb') as f:
        actual_content = f.read()

    assert actual_content == expected_content, "The contents of archive_vault.txt do not match the expected output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
