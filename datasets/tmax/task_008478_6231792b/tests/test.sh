#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_edges_tsv_exists_and_content():
    file_path = "/home/user/edges.tsv"
    assert os.path.isfile(file_path), f"{file_path} is missing."

    expected_edges = [
        "AI\tgpt",
        "AI\tnetworks",
        "AI\tneural",
        "AI\tpython",
        "AI\ttransformers",
        "AI\tzero-trust",
        "Cloud\taws",
        "Cloud\tazure",
        "Cloud\tcloud",
        "Cloud\tdocker",
        "Cloud\tfirewall",
        "Cloud\tnetworks",
        "Cloud\tserverless",
        "Cybersecurity\tbotnet",
        "Cybersecurity\tcloud",
        "Cybersecurity\tencryption",
        "Cybersecurity\tfirewall",
        "Cybersecurity\tmalware",
        "Cybersecurity\tnetworks",
        "Cybersecurity\trsa",
        "Cybersecurity\tzero-trust",
        "DataOps\tcloud",
        "DataOps\tetl",
        "DataOps\tpipeline",
        "DataOps\tpython",
        "DataOps\tsql",
        "DevOps\tagile",
        "DevOps\tcicd",
        "DevOps\tdocker",
        "DevOps\tgit",
        "DevOps\tkubernetes",
        "DevOps\tpython"
    ]

    with open(file_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == len(expected_edges), f"Expected {len(expected_edges)} edges, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_edges)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."

def test_top_match_txt_exists_and_content():
    file_path = "/home/user/top_match.txt"
    assert os.path.isfile(file_path), f"{file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "Cloud", f"Expected 'Cloud' in {file_path}, but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
