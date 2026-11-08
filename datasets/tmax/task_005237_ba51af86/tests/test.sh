#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math
import pytest

def compute_expected_recommendations():
    events_file = "/home/user/data/events.csv"
    assert os.path.exists(events_file), f"Missing input file: {events_file}"

    users = set()
    items = set()
    data = {}

    with open(events_file, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            u = int(row["user_id"])
            i = int(row["item_id"])
            c = int(row["clicks"])
            v = int(row["views"])
            users.add(u)
            items.add(i)
            data[(u, i)] = (c, v)

    users = sorted(list(users))
    items = sorted(list(items))

    # Phase 1: Feature Engineering & Bayesian Smoothing
    ctr = {}
    for u in users:
        ctr[u] = {}
        for i in items:
            c, v = data.get((u, i), (0, 0))
            ctr[u][i] = (c + 2.0) / (v + 10.0)

    # Phase 2: Similarity Search
    nn = {}
    for u1 in users:
        min_dist = float('inf')
        best_u2 = None
        for u2 in users:
            if u1 == u2:
                continue
            dist_sq = sum((ctr[u1][i] - ctr[u2][i])**2 for i in items)
            dist = math.sqrt(dist_sq)

            # Tie breaking: smaller user_id
            if dist < min_dist - 1e-9:
                min_dist = dist
                best_u2 = u2
            elif abs(dist - min_dist) <= 1e-9:
                if best_u2 is None or u2 < best_u2:
                    best_u2 = u2
        nn[u1] = best_u2

    # Phase 3: Recommendation
    recs = {}
    for u in users:
        neighbor = nn[u]
        best_item = None
        max_ctr = -float('inf')

        for i in items:
            # Candidate item must have 0 views for the target user
            _, v = data.get((u, i), (0, 0))
            if v == 0:
                n_ctr = ctr[neighbor][i]
                if n_ctr > max_ctr + 1e-9:
                    max_ctr = n_ctr
                    best_item = i
                elif abs(n_ctr - max_ctr) <= 1e-9:
                    if best_item is None or i < best_item:
                        best_item = i

        recs[str(u)] = {
            "nearest_neighbor": neighbor,
            "recommended_item": best_item
        }

    return recs

def test_recommendations_json_exists():
    file_path = "/home/user/recommendations.json"
    assert os.path.isfile(file_path), f"The output file {file_path} was not found."

def test_recommendations_json_content():
    file_path = "/home/user/recommendations.json"
    assert os.path.isfile(file_path), f"The output file {file_path} was not found."

    with open(file_path, "r", encoding="utf-8") as f:
        try:
            actual_recs = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_recs = compute_expected_recommendations()

    assert isinstance(actual_recs, dict), "The top-level JSON structure must be a dictionary."

    assert set(actual_recs.keys()) == set(expected_recs.keys()), \
        f"The user IDs in the JSON output do not match the expected users. Expected: {list(expected_recs.keys())}, Got: {list(actual_recs.keys())}"

    for user_id, expected_data in expected_recs.items():
        actual_data = actual_recs[user_id]
        assert isinstance(actual_data, dict), f"The value for user '{user_id}' must be a dictionary."

        assert "nearest_neighbor" in actual_data, f"Missing 'nearest_neighbor' for user '{user_id}'."
        assert "recommended_item" in actual_data, f"Missing 'recommended_item' for user '{user_id}'."

        assert actual_data["nearest_neighbor"] == expected_data["nearest_neighbor"], \
            f"Incorrect nearest neighbor for user '{user_id}'. Expected {expected_data['nearest_neighbor']}, got {actual_data['nearest_neighbor']}."

        assert actual_data["recommended_item"] == expected_data["recommended_item"], \
            f"Incorrect recommended item for user '{user_id}'. Expected {expected_data['recommended_item']}, got {actual_data['recommended_item']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
