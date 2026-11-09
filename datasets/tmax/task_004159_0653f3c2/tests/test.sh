#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
import re
from datetime import datetime

def derive_expected_data(raw_path):
    with open(raw_path, "r", newline="", encoding="utf-8") as f:
        raw_rows = list(csv.DictReader(f))

    parsed_rows = []
    for row in raw_rows:
        meta_str = row["metadata"]
        # Replace \u not followed by 4 hex digits with ?
        fixed_meta_str = re.sub(r'\\u(?![0-9a-fA-F]{4})', '?', meta_str)
        meta = json.loads(fixed_meta_str)

        country = meta.get("country")
        if not country:
            domain = row["email"].split("@")[-1]
            tld = domain.split(".")[-1]
            tld_map = {"com": "US", "uk": "UK", "ca": "CA"}
            country = tld_map.get(tld, "")

        meta["country"] = country
        parsed_rows.append((row, meta))

    country_ages = {}
    for row, meta in parsed_rows:
        age = meta.get("age")
        c = meta["country"]
        if age is not None:
            country_ages.setdefault(c, []).append(int(age))

    country_mean_age = {}
    for c, ages in country_ages.items():
        country_mean_age[c] = sum(ages) // len(ages)

    expected = []
    for row, meta in parsed_rows:
        age = meta.get("age")
        if age is None:
            age = country_mean_age.get(meta["country"], "")

        name = meta.get("name", "").strip().title()

        email = row["email"]
        local, domain = email.split("@")
        anon_email = f"{local[0]}***@{domain}"

        ts = row["timestamp"]
        norm_ts = ts
        for fmt in ("%Y-%m-%d %H:%M:%S", "%m/%d/%Y %H:%M:%S", "%B %d, %Y %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
            try:
                dt = datetime.strptime(ts, fmt)
                norm_ts = dt.isoformat()
                break
            except ValueError:
                continue

        fb = row["feedback"]
        anon_fb = re.sub(r'\b\d(?:-?\d){9}\b', '[PHONE]', fb)

        expected.append({
            "id": row["id"],
            "anonymized_email": anon_email,
            "normalized_timestamp": norm_ts,
            "name": name,
            "age": str(age),
            "country": meta["country"],
            "anonymized_feedback": anon_fb
        })

    return expected

def test_clean_data_exists():
    assert os.path.isfile("/home/user/clean_data.csv"), "The output file /home/user/clean_data.csv was not created."

def test_clean_data_contents():
    raw_path = "/home/user/raw_data.csv"
    assert os.path.isfile(raw_path), "Raw data file is missing, cannot verify output."

    expected_data = derive_expected_data(raw_path)

    with open("/home/user/clean_data.csv", "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        actual_data = list(reader)

    expected_headers = ["id", "anonymized_email", "normalized_timestamp", "name", "age", "country", "anonymized_feedback"]
    assert reader.fieldnames == expected_headers, f"Headers mismatch. Expected {expected_headers}, got {reader.fieldnames}"

    assert len(actual_data) == len(expected_data), f"Row count mismatch. Expected {len(expected_data)}, got {len(actual_data)}"

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        for key in expected_headers:
            assert actual.get(key) == expected[key], f"Mismatch at row {i+1}, column '{key}'. Expected '{expected[key]}', got '{actual.get(key)}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
