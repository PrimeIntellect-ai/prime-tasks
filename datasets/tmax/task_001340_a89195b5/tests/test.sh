#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import unicodedata
import re
import pytest

EXPECTED_INPUT = """log_id,timestamp,message
1,2023-10-01T10:00:00Z,Hello Wörld!
2,2023-10-01T10:00:05Z,This is a test.
3,2023-10-01T10:00:10Z,Hello Wörld!
4,2023-10-01T10:00:15Z,Another message here...
5,2023-10-01T10:00:20Z,this is a test.
6,2023-10-01T10:01:00Z,Data engineering is fún!!
7,2023-10-01T10:02:00Z,hello world
8,2023-10-02T10:00:00Z,Final message.
""".encode('utf-8')

def process_logs_expected(input_path):
    if not os.path.exists(input_path):
        return None

    with open(input_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    window_5 = []
    kept_records = []
    kept_token_counts = []
    dropped_count = 0

    output_lines = []

    for row in rows:
        # Normalization
        text = row['message']
        text = text.lower()
        text = unicodedata.normalize('NFKD', text)
        text = text.encode('ascii', 'ignore').decode('utf-8')
        text = re.sub(r'[^a-z0-9 ]', '', text)
        text = re.sub(r' +', ' ', text).strip()

        tokens = text.split(' ') if text else []
        token_count = len(tokens)

        # Deduplication
        is_duplicate = text in window_5

        # Update 5-record window
        window_5.append(text)
        if len(window_5) > 5:
            window_5.pop(0)

        if is_duplicate:
            dropped_count += 1
            continue

        # Rolling stats
        kept_token_counts.append(token_count)
        recent_3 = kept_token_counts[-3:]
        roll_avg = sum(recent_3) / len(recent_3)
        roll_avg_str = f"{roll_avg:.2f}"

        # Formatting
        line = f"[{row['timestamp']}] ID:{row['log_id']} | Tokens:{token_count} | RollAvg:{roll_avg_str} | Text:{text}"
        output_lines.append(line)

    output_lines.append("=== SUMMARY ===")
    output_lines.append(f"Total Kept: {len(kept_token_counts)}")
    output_lines.append(f"Total Dropped: {dropped_count}")

    return "\n".join(output_lines)

def test_processed_logs_exists():
    output_path = '/home/user/processed_logs.txt'
    assert os.path.exists(output_path), f"Expected output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Expected {output_path} to be a file."

def test_input_fixture_unchanged():
    input_path = '/home/user/input_logs.csv'
    assert os.path.exists(input_path), f"Input file {input_path} is missing, cannot verify."
    assert os.path.isfile(input_path), f"Expected {input_path} to be a file."
    with open(input_path, 'rb') as f:
        actual_input = f.read()
    assert actual_input == EXPECTED_INPUT, "The supplied input_logs.csv fixture was modified."

def test_processed_logs_content():
    input_path = '/home/user/input_logs.csv'
    output_path = '/home/user/processed_logs.txt'

    assert os.path.exists(input_path), f"Input file {input_path} is missing, cannot verify."
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    with open(input_path, 'rb') as f:
        actual_input = f.read()
    assert actual_input == EXPECTED_INPUT, "The supplied input_logs.csv fixture was modified."

    expected_content = process_logs_expected(input_path)

    with open(output_path, 'r', encoding='utf-8') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content.strip(), (
        f"The content of {output_path} does not match the expected output.\n"
        f"Expected:\n{expected_content.strip()}\n\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
