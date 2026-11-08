#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import re
import pytest

def test_report_contents():
    frontend_log = '/home/user/logs/frontend.log'
    backend_log = '/home/user/logs/backend.log'
    report_file = '/home/user/report.txt'

    assert os.path.isfile(frontend_log), f"{frontend_log} is missing."
    assert os.path.isfile(backend_log), f"{backend_log} is missing."
    assert os.path.isfile(report_file), f"The report file {report_file} was not created."

    # 1. Find the admin timestamp
    admin_timestamp = None
    with open(frontend_log, 'r') as f:
        for line in f:
            if 'USER: admin' in line:
                match = re.search(r'\[(.*?)\]', line)
                if match:
                    admin_timestamp = match.group(1)
                    break

    assert admin_timestamp is not None, "Could not find 'USER: admin' in frontend.log."

    # 2. Find the TX ID for the admin timestamp
    tx_id = None
    with open(backend_log, 'r') as f:
        for line in f:
            if f'[{admin_timestamp}]' in line:
                match = re.search(r'TX:\s*(\d+)', line)
                if match:
                    tx_id = match.group(1)
                    break

    assert tx_id is not None, f"Could not find TX ID for timestamp {admin_timestamp} in backend.log."

    # 3. Read the payload and calculate corrupted query ID
    payload_file = f'/home/user/payloads/payload_{tx_id}.bin'
    assert os.path.isfile(payload_file), f"Payload file {payload_file} is missing."

    with open(payload_file, 'rb') as f:
        payload_data = f.read(4)

    assert len(payload_data) == 4, f"Payload file {payload_file} does not have at least 4 bytes."

    # Unpack as little-endian unsigned 32-bit integer
    corrupted_query_id = struct.unpack('<I', payload_data)[0]

    # 4. Verify the report file
    with open(report_file, 'r') as f:
        report_lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(report_lines) == 3, f"Expected exactly 3 lines in {report_file}, found {len(report_lines)}."

    assert report_lines[0] == admin_timestamp, f"Line 1 of report.txt is incorrect. Expected '{admin_timestamp}', got '{report_lines[0]}'."
    assert report_lines[1] == tx_id, f"Line 2 of report.txt is incorrect. Expected '{tx_id}', got '{report_lines[1]}'."
    assert report_lines[2] == str(corrupted_query_id), f"Line 3 of report.txt is incorrect. Expected '{corrupted_query_id}', got '{report_lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
