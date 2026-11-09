#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import unicodedata
import hashlib
import pytest

def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi/2.0)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2.0)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c

def test_final_output_correctness():
    output_path = '/home/user/closest_stores.json'
    assert os.path.isfile(output_path), f"Output file is missing at {output_path}"

    config_path = '/home/user/config.json'
    assert os.path.isfile(config_path), f"Config file is missing at {config_path}"
    with open(config_path, 'r') as f:
        config = json.load(f)
    ref_lat = config['ref_lat']
    ref_lon = config['ref_lon']

    csv_path = '/home/user/raw_stores.csv'
    assert os.path.isfile(csv_path), f"Input file is missing at {csv_path}"

    seen_hashes = set()
    expected_stores = []

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            store_id = row['store_id']
            name_native = row['name_native']
            lat = float(row['latitude'])
            lon = float(row['longitude'])

            name_normalized = unicodedata.normalize('NFKC', name_native).lower()
            lat_rounded = round(lat, 2)
            lon_rounded = round(lon, 2)

            # Use string representation of the rounded floats to match the prompt
            hash_str = f"{name_normalized}|{lat_rounded},{lon_rounded}"
            md5_hash = hashlib.md5(hash_str.encode('utf-8')).hexdigest()

            if md5_hash not in seen_hashes:
                seen_hashes.add(md5_hash)
                dist = haversine(lat, lon, ref_lat, ref_lon)
                expected_stores.append({
                    "store_id": store_id,
                    "name_normalized": name_normalized,
                    "distance_km": round(dist, 2)
                })

    expected_stores.sort(key=lambda x: x['distance_km'])

    with open(output_path, 'r', encoding='utf-8') as f:
        try:
            student_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_path} is not valid JSON")

    assert isinstance(student_output, list), "Output must be a JSON array"
    assert len(student_output) == len(expected_stores), f"Expected {len(expected_stores)} deduplicated stores, got {len(student_output)}"

    for i, (student_store, expected_store) in enumerate(zip(student_output, expected_stores)):
        assert student_store.get('store_id') == expected_store['store_id'], f"Mismatch at index {i} for 'store_id'. Expected {expected_store['store_id']}, got {student_store.get('store_id')}"
        assert student_store.get('name_normalized') == expected_store['name_normalized'], f"Mismatch at index {i} for 'name_normalized'. Expected {expected_store['name_normalized']}, got {student_store.get('name_normalized')}"
        assert student_store.get('distance_km') == expected_store['distance_km'], f"Mismatch at index {i} for 'distance_km'. Expected {expected_store['distance_km']}, got {student_store.get('distance_km')}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
