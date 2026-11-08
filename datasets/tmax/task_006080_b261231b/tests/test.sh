#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import string
import subprocess
import tempfile
import pytest

def test_processor_exists():
    assert os.path.isfile('/home/user/processor.c'), "C source code /home/user/processor.c is missing."
    assert os.path.isfile('/home/user/processor'), "Compiled executable /home/user/processor is missing."
    assert os.access('/home/user/processor', os.X_OK), "Compiled executable /home/user/processor is not executable."
    with open('/home/user/processor', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/processor is not a compiled ELF executable."

def test_processor_and_source_on_dynamic_input():
    alphabet = string.ascii_lowercase
    rows = []
    expected = []

    for index in range(12):
        user_id = str(secrets.randbelow(800000000) + 100000000)
        token_count = secrets.randbelow(7) + 1
        tokens = []
        for _ in range(token_count):
            length = secrets.randbelow(18) + 1
            tokens.append(''.join(secrets.choice(alphabet) for _ in range(length)))

        # Exercise literal-space tokenization, including repeated, leading,
        # and trailing spaces. Empty fields between delimiters are not words.
        separators = [' ' * (secrets.randbelow(4) + 1) for _ in range(token_count - 1)]
        query = (' ' * (index % 3))
        for token_index, token in enumerate(tokens):
            if token_index:
                query += separators[token_index - 1]
            query += token
        query += ' ' * ((index + 1) % 4)

        rows.append(f"{user_id},{query}")
        expected.append(f"{user_id},{len(tokens)},{max(map(len, tokens))}")

    input_data = 'user_id,query_text\n' + '\n'.join(rows) + '\n'

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, 'processor_from_source')
        compile_result = subprocess.run(
            ['gcc', '/home/user/processor.c', '-o', rebuilt],
            text=True, capture_output=True, timeout=20
        )
        assert compile_result.returncode == 0, (
            "processor.c could not be compiled by gcc:\n" + compile_result.stderr
        )

        for executable in ('/home/user/processor', rebuilt):
            result = subprocess.run(
                [executable], input=input_data, text=True,
                capture_output=True, timeout=10
            )
            assert result.returncode == 0, (
                f"{executable} failed on dynamically generated CSV input: "
                f"{result.stderr}"
            )
            actual = result.stdout.splitlines()
            assert actual == expected, (
                f"{executable} did not correctly tokenize dynamically generated "
                f"queries. Expected {expected!r}, got {actual!r}."
            )

def test_features_csv():
    file_path = '/home/user/features.csv'
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_lines = {
        "101,6,11",
        "102,6,9",
        "103,5,12",
        "104,4,7",
        "105,6,8",
        "106,4,11",
        "107,3,6"
    }

    with open(file_path, 'r') as f:
        lines = set(line.strip() for line in f if line.strip())

    assert lines == expected_lines, f"Contents of {file_path} do not match the expected feature extraction."

def test_joined_features_csv():
    file_path = '/home/user/joined_features.csv'
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_lines = {
        "101,25,US,6,11",
        "102,35,UK,6,9",
        "103,40,CA,5,12",
        "104,22,US,4,7",
        "105,30,AU,6,8",
        "106,45,IN,4,11",
        "107,29,US,3,6"
    }

    with open(file_path, 'r') as f:
        lines = set(line.strip() for line in f if line.strip())

    assert lines == expected_lines, f"Contents of {file_path} do not match the expected joined outputs."

def test_final_sample_csv():
    file_path = '/home/user/final_sample.csv'
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    expected_lines = {
        "102,35,UK,6,9",
        "103,40,CA,5,12",
        "105,30,AU,6,8",
        "106,45,IN,4,11"
    }

    with open(file_path, 'r') as f:
        lines = set(line.strip() for line in f if line.strip())

    assert lines == expected_lines, f"Contents of {file_path} do not match the expected filtered outputs (age >= 30)."

def test_experiment_log():
    file_path = '/home/user/experiment_log.txt'
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == "FINAL_ROWS: 4", f"Contents of {file_path} do not match the expected log output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
