#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_FILE = "/home/user/hourly_summary.json"

def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Expected output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

def test_output_format_and_sort_order():
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Output file is not valid JSON: {e}")

    assert isinstance(data, list), "Output JSON must be a list of objects."

    # Check chronological sort order
    hour_buckets = [item.get("hour_bucket") for item in data]
    assert all(hour_buckets[i] <= hour_buckets[i+1] for i in range(len(hour_buckets)-1)), \
        "The JSON list is not sorted chronologically by 'hour_bucket'."

def test_output_data_correctness():
    with open(OUTPUT_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    expected_data = [
        {
            "hour_bucket": "2023-10-15T14:00:00Z",
            "transaction_count": 4,
            "unique_users": 3,
            "avg_response_time_ms": 156.25,
            "error_counts": {
                "ERR-500": 2,
                "ERR-400": 1
            }
        },
        {
            "hour_bucket": "2023-10-15T15:00:00Z",
            "transaction_count": 3,
            "unique_users": 2,
            "avg_response_time_ms": 300.0,
            "error_counts": {
                "ERR-504": 2
            }
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} hour buckets, but got {len(data)}."

    for i, expected_item in enumerate(expected_data):
        actual_item = data[i]

        assert actual_item.get("hour_bucket") == expected_item["hour_bucket"], \
            f"Expected hour_bucket '{expected_item['hour_bucket']}', got '{actual_item.get('hour_bucket')}'"

        assert actual_item.get("transaction_count") == expected_item["transaction_count"], \
            f"Hour {expected_item['hour_bucket']}: Expected transaction_count {expected_item['transaction_count']}, got {actual_item.get('transaction_count')}"

        assert actual_item.get("unique_users") == expected_item["unique_users"], \
            f"Hour {expected_item['hour_bucket']}: Expected unique_users {expected_item['unique_users']}, got {actual_item.get('unique_users')}"

        assert actual_item.get("avg_response_time_ms") == expected_item["avg_response_time_ms"], \
            f"Hour {expected_item['hour_bucket']}: Expected avg_response_time_ms {expected_item['avg_response_time_ms']}, got {actual_item.get('avg_response_time_ms')}"

        assert actual_item.get("error_counts") == expected_item["error_counts"], \
            f"Hour {expected_item['hour_bucket']}: Expected error_counts {expected_item['error_counts']}, got {actual_item.get('error_counts')}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
