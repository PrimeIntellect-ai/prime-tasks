#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_risk_scores_computed_correctly():
    activity_log = "/home/user/activity.log"
    priors_csv = "/home/user/priors.csv"
    output_csv = "/home/user/risk_scores.csv"

    assert os.path.isfile(output_csv), f"Output file {output_csv} does not exist."

    # Read priors
    priors = {}
    with open(priors_csv, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row: continue
            user_id = row[0].strip()
            prior = float(row[1].strip())
            priors[user_id] = prior

    # Read activity
    activity = {u: {"N_logins": 0, "N_fails": 0, "Total_purchase": 0.0} for u in priors}
    with open(activity_log, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 4: continue
            user_id = parts[1]
            event_type = parts[2]
            event_value = parts[3]

            if user_id in activity:
                if event_type == "LOGIN":
                    activity[user_id]["N_logins"] += 1
                    if event_value == "FAIL":
                        activity[user_id]["N_fails"] += 1
                elif event_type == "PURCHASE":
                    activity[user_id]["Total_purchase"] += float(event_value)

    # Compute expected
    expected_scores = {}
    for user_id, prior in priors.items():
        n_logins = activity[user_id]["N_logins"]
        n_fails = activity[user_id]["N_fails"]
        total_purchase = activity[user_id]["Total_purchase"]

        lr = ((n_fails + 1) / (n_logins + 2)) * ((total_purchase + 10) / 100)
        odds = prior / (1 - prior)
        new_odds = odds * lr
        posterior = new_odds / (1 + new_odds)
        expected_scores[user_id] = f"{posterior:.4f}"

    # Read output
    actual_scores = {}
    actual_order = []
    with open(output_csv, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row: continue
            user_id = row[0].strip()
            posterior = row[1].strip()
            actual_scores[user_id] = posterior
            actual_order.append(user_id)

    # Assert correct users
    assert set(actual_scores.keys()) == set(expected_scores.keys()), "The set of users in the output does not match priors.csv."

    # Assert sorting
    expected_order = sorted(expected_scores.keys())
    assert actual_order == expected_order, "The output file is not sorted alphabetically by user_id."

    # Assert values
    for user_id in expected_order:
        expected_val = expected_scores[user_id]
        actual_val = actual_scores[user_id]
        assert actual_val == expected_val, f"Incorrect posterior for {user_id}. Expected {expected_val}, got {actual_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
