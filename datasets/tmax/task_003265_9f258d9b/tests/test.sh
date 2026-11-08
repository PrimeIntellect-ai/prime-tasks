#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_stratified_longest_file_exists():
    """Verify that the output file was created."""
    file_path = "/home/user/stratified_longest.jsonl"
    assert os.path.exists(file_path), f"Output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_stratified_longest_contents():
    """Verify the contents of the output file match the expected cleaned and stratified data."""
    file_path = "/home/user/stratified_longest.jsonl"

    expected_data = [
        {"id": "E6", "lang": "en", "text": "this is the longest english sentence in the dataset, it should be first."},
        {"id": "E4", "lang": "en", "text": "this is a completely normal english sentence."},
        {"id": "E5", "lang": "en", "text": "another sentence that has exact same length!!"},
        {"id": "F4", "lang": "fr", "text": "un autre texte français qui est assez long pour être inclus."},
        {"id": "F3", "lang": "fr", "text": "bonjour tout le monde, comment allez-vous aujourd'hui?"},
        {"id": "F1", "lang": "fr", "text": "c'est la vie! c'est très bien."},
        {"id": "J5", "lang": "ja", "text": "もう一つの長い日本語の文章を作成しています。これで長さが足りますか?"},
        {"id": "J1", "lang": "ja", "text": "ハンカクカタカナ is half-width katakana."},
        {"id": "J4", "lang": "ja", "text": "日本語のテキスト処理は、unicode正規化が非常に重要です。"}
    ]

    actual_data = []
    with open(file_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_data.append(record)
            except json.JSONDecodeError:
                assert False, f"Line {line_num} in {file_path} is not valid JSON."

    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} records, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, \
            f"Record at index {i} does not match expected.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
