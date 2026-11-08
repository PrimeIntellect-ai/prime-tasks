#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import zlib
import json
import csv

def test_config_summary_csv():
    csv_path = '/home/user/config_summary.csv'
    assert os.path.exists(csv_path), f"Expected output file {csv_path} is missing."
    assert os.path.isfile(csv_path), f"Expected {csv_path} to be a file, but it is not."

    base_dir = '/home/user/sys_configs'
    expected_records = []

    # Recompute the expected state directly from the source files
    for root, _, files in os.walk(base_dir):
        for file in files:
            if file.endswith('.ccb'):
                full_path = os.path.join(root, file)
                with open(full_path, 'rb') as f:
                    magic = f.read(4)
                    if magic != b'CCB\x01':
                        continue

                    timestamp_bytes = f.read(4)
                    length_bytes = f.read(4)

                    if len(timestamp_bytes) < 4 or len(length_bytes) < 4:
                        continue

                    timestamp = struct.unpack('<I', timestamp_bytes)[0]
                    length = struct.unpack('<I', length_bytes)[0]
                    payload = f.read(length)

                    decompressed = zlib.decompress(payload)
                    data = json.loads(decompressed.decode('utf-8'))

                    service = data.get('service', '')
                    version = data.get('version', '')
                    param_count = len(data.get('parameters', {}))

                    expected_records.append((timestamp, service, version, param_count))

    # Sort primarily by timestamp (asc), secondarily by service (asc)
    expected_records.sort(key=lambda x: (x[0], x[1]))

    # Read the generated CSV
    with open(csv_path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The CSV file is empty; it should contain a header and data rows."

    header = rows[0]
    expected_header = ['timestamp', 'service', 'version', 'param_count']
    assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_records), f"Expected {len(expected_records)} data rows, but found {len(data_rows)}."

    # Compare row by row
    for i, (actual, expected) in enumerate(zip(data_rows, expected_records)):
        expected_str = [str(expected[0]), expected[1], expected[2], str(expected[3])]
        assert actual == expected_str, f"Mismatch at data row {i+1} (excluding header). Expected {expected_str}, got {actual}."

    # Check for trailing spaces or incorrect formatting in the raw file
    with open(csv_path, 'r', encoding='utf-8') as f:
        raw_lines = f.readlines()
        for i, line in enumerate(raw_lines):
            assert ", " not in line, f"Line {i+1} contains spaces after commas, which is not allowed."
            assert " ," not in line, f"Line {i+1} contains spaces before commas, which is not allowed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
