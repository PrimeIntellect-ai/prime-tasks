#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import csv
import pytest

def decode_b64url(s: str) -> dict:
    # Add padding if missing
    padding = '=' * (4 - len(s) % 4)
    decoded_bytes = base64.urlsafe_b64decode(s + padding)
    return json.loads(decoded_bytes.decode('utf-8'))

def test_audit_trail_exists_and_correct():
    input_file = "/home/user/api_logs.jsonl"
    output_file = "/home/user/audit_trail.csv"

    assert os.path.exists(output_file), f"Output file {output_file} was not created."
    assert os.path.isfile(output_file), f"Path {output_file} is not a file."

    expected_records = []

    # Recompute the expected results from the input file
    with open(input_file, "r") as f:
        for line_num, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                data = json.loads(line)
                auth_header = data.get("auth_header", "")
                if auth_header.startswith("Bearer "):
                    token = auth_header[7:]
                    parts = token.split(".")
                    if len(parts) >= 2:
                        header_b64 = parts[0]
                        payload_b64 = parts[1]

                        header = decode_b64url(header_b64)
                        alg = header.get("alg", "")

                        if isinstance(alg, str) and alg.lower() == "none":
                            payload = decode_b64url(payload_b64)
                            user_id = payload.get("user_id", "")

                            expected_records.append([
                                data.get("timestamp", ""),
                                data.get("ip_address", ""),
                                user_id
                            ])
            except Exception as e:
                # If a line is malformed, we skip it just as a robust parser might,
                # or it might not be a JWT.
                pass

    # Read the generated CSV
    actual_records = []
    with open(output_file, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"File {output_file} is empty, expected a header and data.")

        assert header == ["timestamp", "ip_address", "user_id"], \
            f"CSV header in {output_file} is incorrect. Expected ['timestamp', 'ip_address', 'user_id'], got {header}."

        for row in reader:
            actual_records.append(row)

    assert len(actual_records) == len(expected_records), \
        f"Expected {len(expected_records)} records in {output_file}, but found {len(actual_records)}."

    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, \
            f"Record at row {i+2} in {output_file} is incorrect. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
