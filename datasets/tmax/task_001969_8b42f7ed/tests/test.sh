#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import math
from datetime import datetime

def compute_expected_anomalies(strings_path, telemetry_path):
    # Read strings
    strings = {}
    with open(strings_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            strings[row['string_id']] = {
                'language_code': row['language_code'],
                'translated_text': row['translated_text']
            }

    # Read telemetry
    telemetry = []
    with open(telemetry_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            telemetry.append(row)

    # Group by translator_id
    translators = {}
    for row in telemetry:
        t_id = row['translator_id']
        if t_id not in translators:
            translators[t_id] = []
        translators[t_id].append(row)

    anomalies = []

    for t_id, records in translators.items():
        # Sort by timestamp
        records.sort(key=lambda x: x['timestamp'])

        # Forward fill
        last_valid = None
        for r in records:
            if r['edit_distance'] != '':
                last_valid = float(r['edit_distance'])
                r['imputed_ed'] = last_valid
            else:
                r['imputed_ed'] = last_valid

        # Backward fill
        last_valid = None
        for r in reversed(records):
            if r['imputed_ed'] is not None:
                last_valid = r['imputed_ed']
            else:
                r['imputed_ed'] = last_valid

        # Calculate normalized edit distance
        for r in records:
            s_id = r['string_id']
            trans_text = strings[s_id]['translated_text']
            r['norm_ed'] = r['imputed_ed'] / len(trans_text)

        # Calculate rolling average and find anomalies
        for i, r in enumerate(records):
            start_idx = max(0, i - 2)
            window = records[start_idx:i+1]
            rolling_avg = sum(w['norm_ed'] for w in window) / len(window)

            if rolling_avg > 0.50:
                anomalies.append({
                    "string_id": r['string_id'],
                    "translator_id": r['translator_id'],
                    "language_code": strings[r['string_id']]['language_code'],
                    "timestamp": r['timestamp'],
                    "rolling_avg": round(rolling_avg, 3)
                })

    return anomalies

def test_anomalies_json_exists_and_correct():
    strings_path = "/home/user/localization_data/strings.csv"
    telemetry_path = "/home/user/localization_data/telemetry.csv"
    anomalies_path = "/home/user/localization_data/anomalies.json"

    assert os.path.isfile(anomalies_path), f"Expected output file not found: {anomalies_path}"

    with open(anomalies_path, 'r', encoding='utf-8') as f:
        try:
            actual_anomalies = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {anomalies_path} is not valid JSON.")

    assert isinstance(actual_anomalies, list), "JSON output must be a list of objects."

    expected_anomalies = compute_expected_anomalies(strings_path, telemetry_path)

    # Sort both lists to compare them regardless of order
    def sort_key(x):
        return (x['translator_id'], x['timestamp'], x['string_id'])

    expected_sorted = sorted(expected_anomalies, key=sort_key)
    actual_sorted = sorted(actual_anomalies, key=sort_key)

    assert len(actual_sorted) == len(expected_sorted), \
        f"Expected {len(expected_sorted)} anomalies, but found {len(actual_sorted)}."

    for actual, expected in zip(actual_sorted, expected_sorted):
        assert actual.get("string_id") == expected["string_id"], f"Expected string_id {expected['string_id']}, got {actual.get('string_id')}"
        assert actual.get("translator_id") == expected["translator_id"], f"Expected translator_id {expected['translator_id']}, got {actual.get('translator_id')}"
        assert actual.get("language_code") == expected["language_code"], f"Expected language_code {expected['language_code']}, got {actual.get('language_code')}"
        assert actual.get("timestamp") == expected["timestamp"], f"Expected timestamp {expected['timestamp']}, got {actual.get('timestamp')}"

        actual_avg = actual.get("rolling_avg")
        expected_avg = expected["rolling_avg"]
        assert actual_avg is not None, "Missing 'rolling_avg' key in anomaly object."
        assert abs(actual_avg - expected_avg) <= 0.001, \
            f"Expected rolling_avg {expected_avg} for {expected['string_id']}, got {actual_avg}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
