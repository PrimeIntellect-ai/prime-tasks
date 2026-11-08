#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sys
import subprocess
import pytest


def test_00_script_exists_and_executes():
    """Ensure the requested script exists and actually regenerates both outputs."""
    script_path = '/home/user/process_logs.py'
    assert os.path.isfile(script_path), f"Python script not found at {script_path}"

    for output_path in ('/home/user/summary.json', '/home/user/word_counts.parquet'):
        if os.path.exists(output_path):
            os.remove(output_path)

    result = subprocess.run(
        [sys.executable, script_path],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"Script execution failed with exit code {result.returncode}:\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )


def test_summary_json():
    """Test that summary.json exists and contains the correct aggregated data."""
    json_path = '/home/user/summary.json'
    assert os.path.exists(json_path), f"JSON summary file not found at {json_path}"

    with open(json_path, 'r') as f:
        try:
            summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    expected_summary = [
        {"server_id": "srv-01", "total_errors": 3, "top_word": "connection", "top_word_count": 3},
        {"server_id": "srv-02", "total_errors": 2, "top_word": "for", "top_word_count": 2},
        {"server_id": "srv-03", "total_errors": 1, "top_word": "crash", "top_word_count": 1}
    ]

    assert isinstance(summary, list), "JSON root should be a list."
    assert len(summary) == len(expected_summary), f"Expected {len(expected_summary)} servers in summary, got {len(summary)}."
    assert summary == expected_summary, f"JSON summary content mismatch. Expected {expected_summary}, got {summary}"


def test_parquet_file():
    """Test the complete Parquet schema, contents, frequencies, and ordering."""
    parquet_path = '/home/user/word_counts.parquet'
    assert os.path.exists(parquet_path), f"Parquet file not found at {parquet_path}"

    with open(parquet_path, 'rb') as f:
        magic = f.read(4)
        assert magic == b'PAR1', f"File {parquet_path} does not appear to be a valid Parquet file (missing PAR1 magic bytes)."

    verify_script = r'''
import csv
import re
import sys
from collections import Counter, defaultdict

try:
    import pandas as pd
    import pyarrow as pa
    import pyarrow.parquet as pq
except ImportError as e:
    print(f"Required parquet dependency not installed: {e}")
    sys.exit(1)

parquet_path = '/home/user/word_counts.parquet'
try:
    table = pq.read_table(parquet_path)
    df = pd.read_parquet(parquet_path)
except Exception as e:
    print(f"Failed to read parquet: {e}")
    sys.exit(1)

schema = table.schema
if schema.names != ['server_id', 'word', 'count']:
    print(f"Schema columns mismatch. Expected ['server_id', 'word', 'count'], got {schema.names}")
    sys.exit(1)
if not pa.types.is_string(schema.field('server_id').type):
    print(f"server_id must have string type, got {schema.field('server_id').type}")
    sys.exit(1)
if not pa.types.is_string(schema.field('word').type):
    print(f"word must have string type, got {schema.field('word').type}")
    sys.exit(1)
if not pa.types.is_integer(schema.field('count').type):
    print(f"count must have integer type, got {schema.field('count').type}")
    sys.exit(1)

if len(df) != 19:
    print(f"Expected 19 rows, got {len(df)}")
    sys.exit(1)

# Preserve the original specific row assertions.
row0 = df.iloc[0]
if row0['server_id'] != 'srv-01' or row0['word'] != 'connection' or row0['count'] != 3:
    print(f"First row mismatch. Got: {row0.to_dict()}")
    sys.exit(1)

row1 = df.iloc[1]
if row1['server_id'] != 'srv-01' or row1['word'] != 'database' or row1['count'] != 2:
    print(f"Second row mismatch. Got: {row1.to_dict()}")
    sys.exit(1)

# Independently derive every expected frequency from the supplied raw CSV.
counts = defaultdict(Counter)
with open('/home/user/raw_logs.csv', newline='', encoding='utf-8') as f:
    for row in csv.DictReader(f):
        message = row['log_message']
        if 'ERROR:' not in message:
            continue
        marker = 'ERROR: '
        if marker not in message:
            continue
        text = message.split(marker, 1)[1]
        for token in text.split():
            word = re.sub(r'[^a-z0-9]', '', token.lower())
            if word:
                counts[row['server_id']][word] += 1

expected_rows = []
for server_id in sorted(counts):
    for word, count in sorted(counts[server_id].items(), key=lambda item: (-item[1], item[0])):
        expected_rows.append({'server_id': server_id, 'word': word, 'count': count})

actual_rows = table.to_pylist()
if actual_rows != expected_rows:
    print(f"Complete Parquet content or ordering mismatch.\nExpected: {expected_rows}\nGot: {actual_rows}")
    sys.exit(1)

print('SUCCESS')
'''

    result = subprocess.run([sys.executable, '-c', verify_script], capture_output=True, text=True)
    assert result.returncode == 0, f"Parquet content verification failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert "SUCCESS" in result.stdout, "Parquet verification script did not output SUCCESS."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
