#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import subprocess
import pytest

def test_venv_and_packages():
    """Test that the virtual environment exists and required packages are installed."""
    venv_python = '/home/user/venv/bin/python'
    assert os.path.exists(venv_python), f"Virtual environment Python not found at {venv_python}"

    # Check if numpy and tokenizers are installed in the venv
    cmd = [venv_python, '-c', 'import numpy; import tokenizers']
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to import numpy or tokenizers in venv. Stderr: {result.stderr}"

def test_tokenizer_file():
    """Test that the tokenizer was saved and is a valid JSON file."""
    tokenizer_path = '/home/user/bpe_tokenizer.json'
    assert os.path.exists(tokenizer_path), f"Tokenizer file not found at {tokenizer_path}"

    with open(tokenizer_path, 'r', encoding='utf-8') as f:
        try:
            json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Tokenizer file at {tokenizer_path} is not valid JSON")

def test_csv_format_and_sorting():
    """Test that the output CSV exists, has the correct headers, and is sorted by id."""
    csv_path = '/home/user/filtered_dataset.csv'
    assert os.path.exists(csv_path), f"Filtered dataset CSV not found at {csv_path}"

    with open(csv_path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['id', 'token_length'], f"Expected header ['id', 'token_length'], got {header}"

        last_id = -1
        for i, row in enumerate(reader, start=2):
            assert len(row) == 2, f"Row {i} does not have exactly 2 columns"
            try:
                current_id = int(row[0])
                int(row[1]) # check token_length is int
            except ValueError:
                pytest.fail(f"Row {i} contains non-integer values: {row}")

            assert current_id > last_id, f"CSV is not sorted by id in ascending order. Row {i} has id {current_id} after {last_id}"
            last_id = current_id

def test_csv_correctness_via_venv():
    """
    Use the user's virtual environment to compute the expected tokenizer lengths
    and threshold, and verify the CSV matches the exact expected output.
    """
    venv_python = '/home/user/venv/bin/python'
    assert os.path.exists(venv_python), "Cannot verify correctness without the venv Python."

    verification_script = """
import json
import csv
import sys
from tokenizers import Tokenizer
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer
from tokenizers.pre_tokenizers import Whitespace
import numpy as np

texts = []
ids = []
with open('/home/user/raw_data.jsonl', 'r', encoding='utf-8') as f:
    for line in f:
        data = json.loads(line)
        texts.append(data['text'])
        ids.append(data['id'])

# Train tokenizer strictly according to task specs
tokenizer = Tokenizer(BPE(unk_token="[UNK]"))
tokenizer.pre_tokenizer = Whitespace()
trainer = BpeTrainer(special_tokens=["[UNK]"], vocab_size=500)
tokenizer.train_from_iterator(texts, trainer)

lengths = []
for text in texts:
    lengths.append(len(tokenizer.encode(text).ids))

threshold = np.percentile(lengths, 85)

expected_data = []
for i, length in zip(ids, lengths):
    if length < threshold:
        expected_data.append({"id": i, "token_length": length})

expected_data.sort(key=lambda x: x['id'])

actual_data = []
try:
    with open('/home/user/filtered_dataset.csv', 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            actual_data.append({"id": int(row['id']), "token_length": int(row['token_length'])})
except Exception as e:
    print(f"Error reading CSV: {e}")
    sys.exit(1)

if len(actual_data) != len(expected_data):
    print(f"Expected {len(expected_data)} rows, got {len(actual_data)}")
    sys.exit(1)

for act, exp in zip(actual_data, expected_data):
    if act['id'] != exp['id'] or act['token_length'] != exp['token_length']:
        print(f"Data mismatch: expected {exp}, got {act}")
        sys.exit(1)
"""
    result = subprocess.run([venv_python, '-c', verification_script], capture_output=True, text=True)
    assert result.returncode == 0, f"CSV correctness verification failed.\nStdout: {result.stdout}\nStderr: {result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
