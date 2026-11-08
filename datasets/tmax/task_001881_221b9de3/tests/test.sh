#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

RESULTS_JSON = "/home/user/pipeline_results.json"
PIPELINE = "/home/user/pipeline.py"
DATA_DIR = "/home/user/data"


def load_results():
    with open(RESULTS_JSON, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_JSON} is not a valid JSON file.")


def test_pipeline_results_exists():
    """Verify that the pipeline_results.json file has been created."""
    assert os.path.isfile(RESULTS_JSON), f"Expected output file {RESULTS_JSON} is missing."


def test_pipeline_results_format_and_values():
    """Verify the contents of pipeline_results.json."""
    data = load_results()

    # Check required keys
    expected_keys = {"store_id_dtype", "base_accuracy", "ci_lower", "ci_upper"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in JSON output: {missing_keys}"

    # Check data types
    assert data["store_id_dtype"] == "int64", f"Expected store_id_dtype to be 'int64', got {data['store_id_dtype']}"

    # Verify numeric values within an epsilon of 0.01
    epsilon = 0.01

    # Expected values based on the canonical truth
    expected_base_accuracy = 0.82
    expected_ci_lower = 0.765
    expected_ci_upper = 0.87

    assert isinstance(data["base_accuracy"], (int, float)), "base_accuracy must be a number"
    assert isinstance(data["ci_lower"], (int, float)), "ci_lower must be a number"
    assert isinstance(data["ci_upper"], (int, float)), "ci_upper must be a number"

    assert abs(data["base_accuracy"] - expected_base_accuracy) <= epsilon, \
        f"base_accuracy {data['base_accuracy']} is not within {epsilon} of expected {expected_base_accuracy}"

    assert abs(data["ci_lower"] - expected_ci_lower) <= epsilon, \
        f"ci_lower {data['ci_lower']} is not within {epsilon} of expected {expected_ci_lower}"

    assert abs(data["ci_upper"] - expected_ci_upper) <= epsilon, \
        f"ci_upper {data['ci_upper']} is not within {epsilon} of expected {expected_ci_upper}"


def make_probe(seed, n=260):
    rng = np.random.default_rng(seed)
    user_ids = np.arange(10001, 10001 + n, dtype=np.int64)
    rng.shuffle(user_ids)
    ages = rng.integers(18, 70, size=n, dtype=np.int64)
    users = pd.DataFrame({"user_id": user_ids, "age": ages})

    has_transaction = rng.random(n) < 0.68
    # Ensure both missing and present transactions are exercised.
    has_transaction[:3] = [True, False, True]
    tx_ids = user_ids[has_transaction]
    transactions = pd.DataFrame({
        "user_id": tx_ids,
        "store_id": rng.integers(1, 15, size=len(tx_ids), dtype=np.int64),
        "amount": np.round(rng.uniform(5.0, 900.0, size=len(tx_ids)), 2),
    }).sample(frac=1, random_state=seed % (2**32 - 1)).reset_index(drop=True)

    churned = (
        (ages > 44).astype(np.int64)
        ^ ((user_ids % 4) == 0).astype(np.int64)
        ^ (~has_transaction).astype(np.int64)
    )
    labels = pd.DataFrame({"user_id": user_ids, "churned": churned})
    labels = labels.sample(frac=1, random_state=(seed + 17) % (2**32 - 1)).reset_index(drop=True)
    return users, transactions, labels


def expected_for(users, transactions, labels):
    merged = users.merge(transactions, on="user_id", how="left")
    merged = merged.merge(labels, on="user_id", how="left")
    merged["store_id"] = merged["store_id"].fillna(-1).astype("int64")
    merged["amount"] = merged["amount"].fillna(0.0)

    X = merged[["age", "store_id", "amount"]]
    y = merged["churned"]
    _, X_test, _, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    X_train, _, y_train, _ = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    model = RandomForestClassifier(random_state=42)
    model.fit(X_train, y_train)
    predictions = model.predict(X_test)
    base_accuracy = accuracy_score(y_test, predictions)

    np.random.seed(42)
    bootstrap_accuracies = []
    y_test_array = np.asarray(y_test)
    for _ in range(1000):
        indices = np.random.choice(len(y_test_array), size=len(y_test_array), replace=True)
        bootstrap_accuracies.append(
            accuracy_score(y_test_array[indices], predictions[indices])
        )
    ci_lower, ci_upper = np.percentile(bootstrap_accuracies, [2.5, 97.5])
    return {
        "store_id_dtype": str(merged["store_id"].dtype),
        "base_accuracy": float(base_accuracy),
        "ci_lower": float(ci_lower),
        "ci_upper": float(ci_upper),
    }


def test_pipeline_script_executes_and_computes_from_inputs():
    assert os.path.isfile(PIPELINE), f"Expected Python script {PIPELINE} is missing."
    assert os.path.getsize(PIPELINE) > 0, f"Expected Python script {PIPELINE} is empty."

    data_paths = [
        os.path.join(DATA_DIR, "users.csv"),
        os.path.join(DATA_DIR, "transactions.csv"),
        os.path.join(DATA_DIR, "labels.csv"),
    ]
    backups = {path: open(path, "rb").read() for path in data_paths}
    result_backup = open(RESULTS_JSON, "rb").read() if os.path.isfile(RESULTS_JSON) else None

    try:
        for _ in range(2):
            seed = secrets.randbelow(2**31 - 1) + 1
            users, transactions, labels = make_probe(seed)
            expected = expected_for(users, transactions, labels)

            users.to_csv(data_paths[0], index=False)
            transactions.to_csv(data_paths[1], index=False)
            labels.to_csv(data_paths[2], index=False)
            if os.path.exists(RESULTS_JSON):
                os.remove(RESULTS_JSON)

            completed = subprocess.run(
                ["python3", PIPELINE],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=180,
            )
            assert completed.returncode == 0, (
                f"Executing {PIPELINE} failed with exit code {completed.returncode}.\n"
                f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
            )
            assert os.path.isfile(RESULTS_JSON), (
                f"Executing {PIPELINE} did not create {RESULTS_JSON}."
            )
            actual = load_results()
            required = {"store_id_dtype", "base_accuracy", "ci_lower", "ci_upper"}
            assert required <= set(actual), f"Missing keys after execution: {required - set(actual)}"
            assert actual["store_id_dtype"] == expected["store_id_dtype"] == "int64"
            for key in ("base_accuracy", "ci_lower", "ci_upper"):
                assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool)
                assert np.isfinite(actual[key]), f"{key} must be finite"
                assert actual[key] == pytest.approx(expected[key], abs=1e-9), (
                    f"{key} was {actual[key]}, expected {expected[key]} for verifier-supplied data"
                )
    finally:
        for path, contents in backups.items():
            with open(path, "wb") as f:
                f.write(contents)
        if result_backup is None:
            if os.path.exists(RESULTS_JSON):
                os.remove(RESULTS_JSON)
        else:
            with open(RESULTS_JSON, "wb") as f:
                f.write(result_backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
