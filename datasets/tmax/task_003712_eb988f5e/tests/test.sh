#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_missing_fr_tsv_exists():
    file_path = "/home/user/missing_fr.tsv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a regular file."

def test_missing_fr_tsv_content():
    file_path = "/home/user/missing_fr.tsv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    expected_lines = [
        "id\ten\tfr",
        "btn_ok\tOK\tD'accord",
        "btn_cancel\tCancel\\u202\t[TODO] Cancel\\u202",
        "lbl_name\tUser Name\t[TODO] User Name",
        "msg_welcome\tWelcome back\\u002!\tBon retour!",
        "msg_error\tError \\u26A\t[TODO] Error \\u26A"
    ]

    with open(file_path, "r", encoding="utf-8") as f:
        actual_lines = [line.strip("\n") for line in f.readlines()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {repr(expected)}\nActual:   {repr(actual)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
