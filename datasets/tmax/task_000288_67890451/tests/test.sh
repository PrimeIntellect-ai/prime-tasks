#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cleaned_texts_exists_and_content():
    """Test that cleaned_texts.txt exists and contains the correct filtered sentences."""
    file_path = "/home/user/cleaned_texts.txt"
    assert os.path.exists(file_path), f"File not found: {file_path}"
    assert os.path.isfile(file_path), f"Path is not a file: {file_path}"

    expected_lines = [
        "The quick brown fox jumps over the lazy dog.",
        "Data science involves extracting insights from data.",
        "I enjoy reading books about history.",
        "Artificial intelligence will change the way we work.",
        "This is an entirely unique sentence."
    ]

    with open(file_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_lines, f"The content of {file_path} does not match the expected filtered sentences."

def test_vocab_exists_and_content():
    """Test that vocab.txt exists and contains the correct sorted vocabulary."""
    file_path = "/home/user/vocab.txt"
    assert os.path.exists(file_path), f"File not found: {file_path}"
    assert os.path.isfile(file_path), f"Path is not a file: {file_path}"

    expected_vocab = [
        "about", "an", "artificial", "books", "brown", "change", "data", "dog",
        "enjoy", "entirely", "extracting", "fox", "from", "history", "i",
        "insights", "intelligence", "involves", "is", "jumps", "lazy", "over",
        "quick", "reading", "science", "sentence", "the", "this", "unique",
        "way", "we", "will", "work"
    ]

    with open(file_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_vocab, f"The content of {file_path} does not match the expected vocabulary."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
