#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_summary_json_exists():
    file_path = '/home/user/summary.json'
    assert os.path.exists(file_path), f"The output file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_summary_json_content():
    file_path = '/home/user/summary.json'
    assert os.path.exists(file_path), f"The output file {file_path} is missing."

    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} is not a valid JSON.")

    expected = {
        "Electronics": {"mean_score": 0.6, "valid_count": 2},
        "Home": {"mean_score": 0.4, "valid_count": 2},
        "Toys": {"mean_score": 0.5, "valid_count": 2},
        "Kitchen": {"mean_score": 0.85, "valid_count": 2}
    }

    assert isinstance(data, dict), "The top-level JSON structure must be a dictionary."

    for cat, stats in expected.items():
        assert cat in data, f"Missing category '{cat}' in the output JSON."
        cat_data = data[cat]
        assert "mean_score" in cat_data, f"Missing 'mean_score' for category '{cat}'."
        assert "valid_count" in cat_data, f"Missing 'valid_count' for category '{cat}'."

        assert abs(cat_data["mean_score"] - stats["mean_score"]) < 1e-4, \
            f"Wrong mean_score for category '{cat}'. Expected ~{stats['mean_score']}, got {cat_data['mean_score']}."
        assert cat_data["valid_count"] == stats["valid_count"], \
            f"Wrong valid_count for category '{cat}'. Expected {stats['valid_count']}, got {cat_data['valid_count']}."

    # Ensure no extra unexpected categories are present
    for cat in data:
        assert cat in expected, f"Unexpected category '{cat}' found in the output JSON."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
