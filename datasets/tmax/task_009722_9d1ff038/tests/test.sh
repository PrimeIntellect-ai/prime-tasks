#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import re
import pytest

def compute_expected_summary(csv_path):
    if not os.path.exists(csv_path):
        pytest.fail(f"Input CSV missing: {csv_path}")

    stats = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            review_id = row.get('review_id', '')
            # Constraint: review_id exactly 10 alphanumeric characters
            if len(review_id) != 10 or not review_id.isalnum():
                continue

            # Constraint: rating is integer between 1 and 5
            try:
                rating = int(row.get('rating', 0))
                if not (1 <= rating <= 5):
                    continue
            except ValueError:
                continue

            metadata_str = row.get('metadata', '')

            # Bug fix: clean malformed unicode escape sequences
            def repl(match):
                chars = match.group(1)
                # Check if any of the 4 characters is NOT a valid hex digit
                if not all(c in '0123456789abcdefABCDEF' for c in chars):
                    return '[REDACTED]'
                return match.group(0)

            cleaned_metadata = re.sub(r'\\u(.{4})', repl, metadata_str)

            device = "unknown"
            try:
                parsed = json.loads(cleaned_metadata)
                if isinstance(parsed, dict) and 'device' in parsed:
                    device = parsed['device']
            except Exception:
                pass

            text_length = len(row.get('review_text', ''))

            if device not in stats:
                stats[device] = {'count': 0, 'sum_rating': 0, 'sum_text_length': 0}

            stats[device]['count'] += 1
            stats[device]['sum_rating'] += rating
            stats[device]['sum_text_length'] += text_length

    result = {}
    for dev, data in stats.items():
        result[dev] = {
            "count": data['count'],
            "avg_rating": round(data['sum_rating'] / data['count'], 2),
            "avg_text_length": round(data['sum_text_length'] / data['count'], 2)
        }
    return result

def test_summary_json_exists_and_correct():
    output_path = "/home/user/output/summary.json"
    assert os.path.isfile(output_path), f"Output file not found: {output_path}"

    with open(output_path, 'r', encoding='utf-8') as f:
        try:
            student_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} is not valid JSON.")

    expected_output = compute_expected_summary("/home/user/data/raw_reviews.csv")

    assert isinstance(student_output, dict), "The output JSON must be a dictionary."

    # Check that the keys match
    expected_keys = set(expected_output.keys())
    student_keys = set(student_output.keys())
    assert expected_keys == student_keys, f"Expected device types {expected_keys}, but got {student_keys}."

    # Check each device's statistics
    for device, expected_stats in expected_output.items():
        student_stats = student_output[device]
        assert isinstance(student_stats, dict), f"Statistics for '{device}' must be a dictionary."

        for stat_key, expected_val in expected_stats.items():
            assert stat_key in student_stats, f"Missing key '{stat_key}' in statistics for '{device}'."
            student_val = student_stats[stat_key]

            # Use pytest.approx for floating point comparisons
            if isinstance(expected_val, float):
                assert student_val == pytest.approx(expected_val, abs=1e-2), \
                    f"For '{device}', expected {stat_key} to be {expected_val}, got {student_val}."
            else:
                assert student_val == expected_val, \
                    f"For '{device}', expected {stat_key} to be {expected_val}, got {student_val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
