#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math

def compute_expected_recommendations():
    raw_file = '/home/user/raw_data.csv'
    if not os.path.exists(raw_file):
        return {}

    with open(raw_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    valid_rows = []
    prices = []
    for r in rows:
        price_str = r['price']
        if price_str == '' or price_str.lower() == 'nan':
            valid_rows.append(r)
        else:
            p = float(price_str)
            if 0 <= p <= 1000:
                valid_rows.append(r)
                prices.append(p)

    if not valid_rows:
        return {}

    prices.sort()
    n = len(prices)
    if n % 2 == 0:
        median_price = (prices[n//2 - 1] + prices[n//2]) / 2.0
    else:
        median_price = prices[n//2]

    processed = []
    for r in valid_rows:
        p_str = r['price']
        p = median_price if (p_str == '' or p_str.lower() == 'nan') else float(p_str)

        r_str = r['rating']
        rt = 0.0 if (r_str == '' or r_str.lower() == 'nan') else float(r_str)

        processed.append({
            'item_id': int(r['item_id']),
            'category': r['category'],
            'price': p,
            'rating': rt
        })

    min_p = min(x['price'] for x in processed)
    max_p = max(x['price'] for x in processed)
    min_r = min(x['rating'] for x in processed)
    max_r = max(x['rating'] for x in processed)

    categories = sorted(list(set(x['category'] for x in processed)))

    vectors = {}
    for x in processed:
        sp = (x['price'] - min_p) / (max_p - min_p) if max_p > min_p else 0.0
        sr = (x['rating'] - min_r) / (max_r - min_r) if max_r > min_r else 0.0
        vec = [sp, sr]
        for c in categories:
            vec.append(1.0 if x['category'] == c else 0.0)
        vectors[x['item_id']] = vec

    def dot(v1, v2):
        return sum(a*b for a, b in zip(v1, v2))
    def norm(v):
        return math.sqrt(dot(v, v))

    norms = {k: norm(v) for k, v in vectors.items()}

    recs = {}
    item_ids = list(vectors.keys())
    for i in item_ids:
        sims = []
        for j in item_ids:
            if i == j: continue
            # Avoid division by zero
            denom = norms[i] * norms[j]
            sim = dot(vectors[i], vectors[j]) / denom if denom > 0 else 0.0
            sims.append((sim, j))
        # Sort by similarity descending, then item_id ascending
        sims.sort(key=lambda x: (-x[0], x[1]))
        recs[str(i)] = [sims[0][1], sims[1][1]]

    return recs

def test_recommendations_file_exists():
    """Test that the recommendations.json file was created."""
    assert os.path.exists('/home/user/recommendations.json'), "recommendations.json was not found in /home/user."

def test_recommendations_content():
    """Test that the recommendations.json file contains the correct recommendations."""
    expected_recs = compute_expected_recommendations()
    assert expected_recs, "Could not compute expected recommendations (maybe raw_data.csv is missing or empty)."

    try:
        with open('/home/user/recommendations.json', 'r', encoding='utf-8') as f:
            actual_recs = json.load(f)
    except Exception as e:
        assert False, f"Failed to read or parse recommendations.json: {e}"

    assert isinstance(actual_recs, dict), "recommendations.json should contain a dictionary."

    # Check keys
    expected_keys = set(expected_recs.keys())
    actual_keys = set(actual_recs.keys())
    assert expected_keys == actual_keys, f"Expected item IDs {expected_keys}, got {actual_keys}."

    # Check values
    for k in expected_keys:
        assert actual_recs[k] == expected_recs[k], f"Expected recommendations for {k} to be {expected_recs[k]}, but got {actual_recs[k]}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
