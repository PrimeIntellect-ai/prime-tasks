#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import pytest

def test_rust_project_exists():
    cargo_toml = "/home/user/tracker/Cargo.toml"
    assert os.path.isfile(cargo_toml), f"Rust project not found: {cargo_toml} is missing."
    main_rs = "/home/user/tracker/src/main.rs"
    assert os.path.isfile(main_rs), f"Rust source code not found: {main_rs} is missing."

def test_predictions_json():
    predictions_file = "/home/user/experiments/predictions.json"
    assert os.path.isfile(predictions_file), f"Output file missing: {predictions_file} was not created."

    metadata = {}
    with open("/home/user/experiments/metadata.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            metadata[row["run_id"]] = row["status"]

    success_logs = []
    with open("/home/user/experiments/logs.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if metadata.get(row["run_id"]) == "SUCCESS":
                success_logs.append({
                    "run_id": row["run_id"],
                    "x1": float(row["x1"]),
                    "x2": float(row["x2"]),
                    "x3": float(row["x3"]),
                    "y_pred": float(row["y_pred"])
                })

    b = 0.0
    w1 = 0.0
    w2 = 0.0
    w3 = 0.0

    for log in success_logs:
        if log["x1"] == 0.0 and log["x2"] == 0.0 and log["x3"] == 0.0:
            b = log["y_pred"]
            break

    for log in success_logs:
        if log["x1"] != 0.0 and log["x2"] == 0.0 and log["x3"] == 0.0:
            w1 = (log["y_pred"] - b) / log["x1"]
        elif log["x1"] == 0.0 and log["x2"] != 0.0 and log["x3"] == 0.0:
            w2 = (log["y_pred"] - b) / log["x2"]
        elif log["x1"] == 0.0 and log["x2"] == 0.0 and log["x3"] != 0.0:
            w3 = (log["y_pred"] - b) / log["x3"]

    expected_predictions = []
    with open("/home/user/experiments/test.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            t_id = row["test_id"]
            x1 = float(row["x1"])
            x2 = float(row["x2"])
            x3 = float(row["x3"])
            x_comp = (x1 * x2) + x3
            y_pred = (w1 * x1) + (w2 * x2) + (w3 * x3) + b
            expected_predictions.append({
                "test_id": t_id,
                "x_comp": x_comp,
                "y_pred": y_pred
            })

    with open(predictions_file, "r") as f:
        try:
            actual_predictions = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {predictions_file} does not contain valid JSON.")

    assert isinstance(actual_predictions, list), "The JSON output must be a list of objects."
    assert len(actual_predictions) == len(expected_predictions), f"Expected {len(expected_predictions)} predictions, but found {len(actual_predictions)}."

    expected_dict = {item["test_id"]: item for item in expected_predictions}
    actual_dict = {item.get("test_id"): item for item in actual_predictions}

    for t_id, exp in expected_dict.items():
        assert t_id in actual_dict, f"Missing prediction for test_id: {t_id}"
        act = actual_dict[t_id]
        assert "x_comp" in act, f"Missing 'x_comp' in prediction for {t_id}"
        assert "y_pred" in act, f"Missing 'y_pred' in prediction for {t_id}"
        assert math.isclose(act["x_comp"], exp["x_comp"], rel_tol=1e-5, abs_tol=1e-5), \
            f"Incorrect x_comp for {t_id}: expected {exp['x_comp']}, got {act['x_comp']}"
        assert math.isclose(act["y_pred"], exp["y_pred"], rel_tol=1e-5, abs_tol=1e-5), \
            f"Incorrect y_pred for {t_id}: expected {exp['y_pred']}, got {act['y_pred']}"
TEST_EOF

passed=0
backup_dir=$(mktemp -d)
cp /home/user/experiments/logs.csv "$backup_dir/logs.csv"
cp /home/user/experiments/metadata.csv "$backup_dir/metadata.csv"
cp /home/user/experiments/test.csv "$backup_dir/test.csv"

if [ -f /home/user/tracker/Cargo.toml ] && [ -f /home/user/tracker/src/main.rs ] && \
   (cd /home/user/tracker && cargo build --quiet); then
    rm -f /home/user/experiments/predictions.json
    if (cd /home/user/tracker && cargo run --quiet) && \
       python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then

        if python3 - << 'DYNAMIC_EOF'
import csv
import secrets

b = secrets.randbelow(31) - 15
weights = [secrets.choice([i for i in range(-9, 10) if i != 0]) for _ in range(3)]
deltas = [secrets.choice([i for i in range(-6, 7) if i != 0]) for _ in range(3)]
tag = secrets.token_hex(6)

logs = [
    [f"base_{tag}", 0, 0, 0, b],
    [f"one_{tag}", deltas[0], 0, 0, b + weights[0] * deltas[0]],
    [f"two_{tag}", 0, deltas[1], 0, b + weights[1] * deltas[1]],
    [f"three_{tag}", 0, 0, deltas[2], b + weights[2] * deltas[2]],
    [f"failed_{tag}", 11, 0, 0, 987654],
    [f"spaced_{tag}", 0, 13, 0, -765432],
]
metadata = [
    [f"base_{tag}", "SUCCESS"],
    [f"one_{tag}", "SUCCESS"],
    [f"two_{tag}", "SUCCESS"],
    [f"three_{tag}", "SUCCESS"],
    [f"failed_{tag}", "FAILED"],
    [f"spaced_{tag}", "SUCCESS "],
]

def nonzero():
    return secrets.choice([i for i in range(-8, 9) if i != 0])

tests = [[f"case_{tag}_{i}", nonzero(), nonzero(), nonzero()] for i in range(5)]
tests.append([f"zero_{tag}", 0, 0, 0])

with open("/home/user/experiments/logs.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["run_id", "x1", "x2", "x3", "y_pred"])
    w.writerows(logs)
with open("/home/user/experiments/metadata.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["run_id", "status"])
    w.writerows(metadata)
with open("/home/user/experiments/test.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["test_id", "x1", "x2", "x3"])
    w.writerows(tests)
DYNAMIC_EOF
        then
            rm -f /home/user/experiments/predictions.json
            if (cd /home/user/tracker && cargo run --quiet) && \
               python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
                passed=1
            fi
        fi
    fi
fi

cp "$backup_dir/logs.csv" /home/user/experiments/logs.csv
cp "$backup_dir/metadata.csv" /home/user/experiments/metadata.csv
cp "$backup_dir/test.csv" /home/user/experiments/test.csv
rm -rf "$backup_dir"

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
