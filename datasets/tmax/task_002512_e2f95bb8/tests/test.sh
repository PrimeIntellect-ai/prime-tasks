#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_cleaned_logs_exists_and_valid():
    """Verify that the cleaned_logs.jsonl file exists and has the correct output."""
    output_file = "/home/user/cleaned_logs.jsonl"

    assert os.path.exists(output_file), f"The output file does not exist at {output_file}."
    assert os.path.isfile(output_file), f"The path {output_file} is not a file."

    expected = [
        {"timestamp": "2023-10-27T10:00:00Z", "level": "INFO", "job_id": "JOB_123", "message": "processed record café"},
        {"timestamp": "2023-10-27T10:01:00Z", "level": "ERROR", "job_id": "JOB_124", "message": "データエラー"},
        {"timestamp": "2023-10-27T10:07:00Z", "level": "INFO", "job_id": "JOB_999", "message": "normal operation"},
        {"timestamp": "2023-10-27T10:11:00Z", "level": "WARN", "job_id": "JOB_124", "message": "データエラー"}
    ]

    actual = []
    with open(output_file, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual.append(record)
            except json.JSONDecodeError as e:
                assert False, f"Line {line_num} in {output_file} is not valid JSON: {e}"

    assert len(actual) == len(expected), f"Expected {len(expected)} records, but found {len(actual)} in {output_file}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act == exp, f"Record at line {i+1} mismatch.\nExpected: {exp}\nGot: {act}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
