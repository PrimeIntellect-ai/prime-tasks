#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import string
import pytest

def test_urgent_logs_output():
    config_path = "/home/user/config.json"
    raw_logs_path = "/home/user/raw_logs.csv"
    urgent_logs_path = "/home/user/urgent_logs.json"

    assert os.path.isfile(config_path), f"Missing {config_path}"
    assert os.path.isfile(raw_logs_path), f"Missing {raw_logs_path}"
    assert os.path.isfile(urgent_logs_path), f"Missing {urgent_logs_path}"

    with open(config_path, "r") as f:
        config = json.load(f)

    prior_u = config["prior_urgent"]
    prior_n = 1.0 - prior_u
    likelihoods = config["likelihoods"]

    expected_urgent = []
    with open(raw_logs_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            msg = row["message"].lower()
            for p in string.punctuation:
                msg = msg.replace(p, " ")
            words = set(msg.split())

            p_u = prior_u
            p_n = prior_n

            for w in words:
                if w in likelihoods:
                    p_u *= likelihoods[w]["urgent"]
                    p_n *= likelihoods[w]["normal"]

            post_u = p_u / (p_u + p_n)
            if post_u > 0.5:
                expected_urgent.append({
                    "id": int(row["id"]) if row["id"].isdigit() else row["id"],
                    "posterior": round(post_u, 4)
                })

    with open(urgent_logs_path, "r") as f:
        try:
            actual_urgent = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {urgent_logs_path} is not valid JSON.")

    assert isinstance(actual_urgent, list), "Output should be a JSON array."
    assert len(actual_urgent) == len(expected_urgent), f"Expected {len(expected_urgent)} urgent logs, found {len(actual_urgent)}."

    # Compare sorted by id
    actual_urgent_sorted = sorted(actual_urgent, key=lambda x: int(x["id"]))
    expected_urgent_sorted = sorted(expected_urgent, key=lambda x: int(x["id"]))

    for act, exp in zip(actual_urgent_sorted, expected_urgent_sorted):
        assert int(act["id"]) == int(exp["id"]), f"Expected id {exp['id']}, got {act['id']}"
        assert abs(act["posterior"] - exp["posterior"]) < 1e-4, f"Expected posterior {exp['posterior']} for id {exp['id']}, got {act['posterior']}"

def test_mlflow_tracking():
    mlruns_dir = "/home/user/mlruns"
    assert os.path.isdir(mlruns_dir), f"MLflow tracking directory {mlruns_dir} not found."

    # Find the ETL_Anomaly_Detection experiment
    exp_id = None
    for item in os.listdir(mlruns_dir):
        meta_path = os.path.join(mlruns_dir, item, "meta.yaml")
        if os.path.isfile(meta_path):
            with open(meta_path, "r") as f:
                content = f.read()
                if "name: ETL_Anomaly_Detection" in content:
                    exp_id = item
                    break

    assert exp_id is not None, "Experiment 'ETL_Anomaly_Detection' not found in mlruns."

    exp_dir = os.path.join(mlruns_dir, exp_id)
    run_found = False

    # Find a run with the correct params and metrics
    for run_item in os.listdir(exp_dir):
        if run_item == "meta.yaml":
            continue
        run_dir = os.path.join(exp_dir, run_item)
        if not os.path.isdir(run_dir):
            continue

        param_path = os.path.join(run_dir, "params", "prior_urgent")
        metric_path = os.path.join(run_dir, "metrics", "urgent_count")

        if os.path.isfile(param_path) and os.path.isfile(metric_path):
            with open(param_path, "r") as f:
                param_val = f.read().strip()

            if param_val != "0.1":
                continue

            with open(metric_path, "r") as f:
                lines = f.readlines()
                for line in lines:
                    parts = line.strip().split()
                    # MLflow metrics file typically has lines like: timestamp value [step]
                    val_str = parts[1] if len(parts) >= 2 else parts[0]
                    try:
                        metric_val = float(val_str)
                        if metric_val == 2.0:
                            run_found = True
                            break
                    except ValueError:
                        continue

        if run_found:
            break

    assert run_found, "Could not find an MLflow run with parameter 'prior_urgent' = 0.1 and metric 'urgent_count' = 2."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
