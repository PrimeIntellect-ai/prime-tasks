#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_anomalies_json_exists():
    """Test that the output JSON file exists."""
    file_path = "/home/user/anomalies.json"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

def test_anomalies_json_content():
    """Test that the output JSON file has the correct content."""
    file_path = "/home/user/anomalies.json"
    with open(file_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} is not valid JSON."

    assert isinstance(data, list), f"JSON root must be a list, got {type(data)}."
    assert len(data) == 2, f"Expected 2 anomalies, got {len(data)}."

    # Expected anomalies
    expected_anomalies = [
        {
            "timestamp": "2023-10-01 13:00:00",
            "value": 88.5,
            "non_ascii_count": 4
        },
        {
            "timestamp": "2023-10-01 16:00:00",
            "value": 92.0,
            "non_ascii_count": 1
        }
    ]

    for i, expected in enumerate(expected_anomalies):
        actual = data[i]
        assert "timestamp" in actual, f"Anomaly {i} missing 'timestamp' key."
        assert "value" in actual, f"Anomaly {i} missing 'value' key."
        assert "non_ascii_count" in actual, f"Anomaly {i} missing 'non_ascii_count' key."

        assert actual["timestamp"] == expected["timestamp"], f"Anomaly {i} timestamp mismatch: expected {expected['timestamp']}, got {actual['timestamp']}."

        # Check value with float tolerance
        assert isinstance(actual["value"], (int, float)), f"Anomaly {i} value must be a number."
        assert abs(actual["value"] - expected["value"]) < 1e-5, f"Anomaly {i} value mismatch: expected {expected['value']}, got {actual['value']}."

        assert actual["non_ascii_count"] == expected["non_ascii_count"], f"Anomaly {i} non_ascii_count mismatch: expected {expected['non_ascii_count']}, got {actual['non_ascii_count']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
