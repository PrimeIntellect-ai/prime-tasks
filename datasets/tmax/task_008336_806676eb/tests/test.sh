#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess

import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

PROJECT_DIR = "/home/user/fraud_project"
SCRIPT_PATH = os.path.join(PROJECT_DIR, "train_model.py")
DATA_DIR = os.path.join(PROJECT_DIR, "data")
PARQUET_PATH = os.path.join(PROJECT_DIR, "data_merged.parquet")
METRICS_PATH = os.path.join(PROJECT_DIR, "metrics.json")


def _call_name(call):
    if not isinstance(call, ast.Call):
        return ""
    node = call.func
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def _literal_keyword(call, name):
    for keyword in call.keywords:
        if keyword.arg == name:
            try:
                return ast.literal_eval(keyword.value)
            except Exception:
                return None
    return None


def _make_hidden_inputs():
    # Exercise the submitted program on fresh data so precomputed artifacts or
    # hard-coded results cannot satisfy the verifier.
    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)
    n = 80
    user_ids = np.arange(1, n + 1)

    users = pd.DataFrame({
        "user_id": user_ids,
        "age": rng.integers(18, 76, size=n),
        "credit_score": rng.integers(480, 851, size=n),
    })

    rows = []
    for uid in user_ids:
        # Leave some users without transactions to exercise the left join and fillna.
        if uid % 11 == 0:
            continue
        for _ in range(int(rng.integers(1, 4))):
            rows.append({"user_id": uid, "amount": int(rng.integers(5, 3000))})
    transactions = pd.DataFrame(rows, columns=["user_id", "amount"])

    labels_array = rng.integers(0, 2, size=n)
    train_idx, test_idx = train_test_split(
        np.arange(n), test_size=0.2, random_state=42
    )
    # Deterministically guarantee both classes in both partitions.
    labels_array[test_idx[0]] = 0
    labels_array[test_idx[1]] = 1
    labels_array[train_idx[0]] = 0
    labels_array[train_idx[1]] = 1
    labels = pd.DataFrame({"user_id": user_ids, "is_fraud": labels_array})

    users.to_csv(os.path.join(DATA_DIR, "users.csv"), index=False)
    transactions.to_csv(os.path.join(DATA_DIR, "transactions.csv"), index=False)
    labels.to_csv(os.path.join(DATA_DIR, "labels.csv"), index=False)

    tx_agg = transactions.groupby("user_id")["amount"].sum().reset_index()
    expected_df = users.merge(tx_agg, on="user_id", how="left").merge(
        labels, on="user_id", how="left"
    )
    expected_df["amount"] = expected_df["amount"].fillna(0)

    X = expected_df[["age", "credit_score", "amount"]]
    y = expected_df["is_fraud"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    model = Pipeline([
        ("scaler", StandardScaler()),
        ("model", LogisticRegression(random_state=42)),
    ])
    model.fit(X_train, y_train)
    predictions = model.predict_proba(X_test)[:, 1]

    y_values = np.asarray(y_test)
    np.random.seed(42)
    bootstrap_scores = []
    for _ in range(1000):
        indices = np.random.choice(
            len(y_values), size=len(y_values), replace=True
        )
        # ROC-AUC is undefined for a one-class bootstrap sample. A successful
        # implementation must omit such samples rather than emit NaN or crash.
        if np.unique(y_values[indices]).size < 2:
            continue
        bootstrap_scores.append(
            roc_auc_score(y_values[indices], predictions[indices])
        )

    expected_metrics = {
        "roc_auc_mean": float(np.mean(bootstrap_scores)),
        "roc_auc_lower": float(np.percentile(bootstrap_scores, 2.5)),
        "roc_auc_upper": float(np.percentile(bootstrap_scores, 97.5)),
    }
    return expected_df, expected_metrics


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Missing required script: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH) and not os.path.isdir(SCRIPT_PATH)

    expected_df, expected_metrics = _make_hidden_inputs()
    for path in (PARQUET_PATH, METRICS_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "train_model.py did not run successfully.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return expected_df, expected_metrics


def test_script_implements_required_workflow():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    split_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call) and _call_name(node).endswith("train_test_split")
    ]
    assert split_calls, "train_model.py must call train_test_split"
    valid_splits = [
        call for call in split_calls
        if _literal_keyword(call, "test_size") == 0.2
        and _literal_keyword(call, "random_state") == 42
    ]
    assert valid_splits, "train_test_split must use test_size=0.2 and random_state=42"
    split_line = min(call.lineno for call in valid_splits)

    scaler_vars = set()
    pipeline_vars = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            names = [target.id for target in targets if isinstance(target, ast.Name)]
            if isinstance(value, ast.Call) and _call_name(value).endswith("StandardScaler"):
                scaler_vars.update(names)
            if isinstance(value, ast.Call) and _call_name(value).split(".")[-1] in {
                "Pipeline", "make_pipeline"
            }:
                contains_scaler = any(
                    (isinstance(child, ast.Call) and _call_name(child).endswith("StandardScaler"))
                    or (isinstance(child, ast.Name) and child.id in scaler_vars)
                    for child in ast.walk(value)
                )
                if contains_scaler:
                    pipeline_vars.update(names)

    scaler_fit_calls = []
    pipeline_fit_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        receiver = node.func.value
        if node.func.attr in {"fit", "fit_transform"} and isinstance(receiver, ast.Name):
            if receiver.id in scaler_vars:
                scaler_fit_calls.append(node)
            if receiver.id in pipeline_vars:
                pipeline_fit_calls.append(node)

    assert not any(call.lineno < split_line for call in scaler_fit_calls), (
        "StandardScaler is fitted before train_test_split, causing data leakage"
    )
    manual_scaling_is_safe = any(call.lineno > split_line for call in scaler_fit_calls)
    pipeline_scaling_is_safe = any(call.lineno > split_line for call in pipeline_fit_calls)
    assert manual_scaling_is_safe or pipeline_scaling_is_safe, (
        "The scaler must be fitted after the split or fitted through a Pipeline on training data"
    )

    seed_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and _call_name(node).endswith("random.seed")
        and node.args
        and isinstance(node.args[0], ast.Constant)
        and node.args[0].value == 42
    ]
    bootstrap_loops = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.For, ast.AsyncFor)):
            continue
        if not (
            isinstance(node.iter, ast.Call)
            and _call_name(node.iter).split(".")[-1] == "range"
            and node.iter.args
            and isinstance(node.iter.args[0], ast.Constant)
            and node.iter.args[0].value == 1000
        ):
            continue
        choices = [
            child for child in ast.walk(node)
            if isinstance(child, ast.Call) and _call_name(child).endswith("random.choice")
        ]
        valid_choices = [
            call for call in choices
            if _literal_keyword(call, "replace") is True
            and any(keyword.arg == "size" for keyword in call.keywords)
        ]
        auc_calls = [
            child for child in ast.walk(node)
            if isinstance(child, ast.Call) and _call_name(child).endswith("roc_auc_score")
        ]
        if valid_choices and auc_calls:
            bootstrap_loops.append(node)

    assert bootstrap_loops, (
        "Expected a 1000-iteration bootstrap loop using np.random.choice(..., size=..., replace=True) "
        "and roc_auc_score"
    )
    assert any(
        seed.lineno < loop.lineno for seed in seed_calls for loop in bootstrap_loops
    ), "np.random.seed(42) must be set before the bootstrap loop"


def test_parquet_file_exists_and_valid(execute_submission):
    expected_df, _ = execute_submission
    assert os.path.isfile(PARQUET_PATH), f"Merged Parquet file is missing at {PARQUET_PATH}"

    # Keep the original magic-byte assertions.
    with open(PARQUET_PATH, "rb") as f:
        header = f.read(4)
        f.seek(-4, os.SEEK_END)
        footer = f.read(4)
    assert header == b"PAR1", "File does not have a valid Parquet header."
    assert footer == b"PAR1" or footer == b"PARE", "File does not have a valid Parquet footer."

    actual_df = pd.read_parquet(PARQUET_PATH)
    assert_frame_equal(
        actual_df.reset_index(drop=True),
        expected_df.reset_index(drop=True),
        check_dtype=False,
        check_like=False,
    )


def test_metrics_json_exists_and_valid(execute_submission):
    _, expected_metrics = execute_submission
    assert os.path.isfile(METRICS_PATH), f"Metrics JSON file is missing at {METRICS_PATH}"

    with open(METRICS_PATH, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("metrics.json is not a valid JSON file.")

    expected_keys = {"roc_auc_mean", "roc_auc_lower", "roc_auc_upper"}
    actual_keys = set(metrics.keys())
    assert expected_keys.issubset(actual_keys), (
        f"metrics.json is missing required keys. Expected {expected_keys}, found {actual_keys}"
    )

    mean_val = metrics["roc_auc_mean"]
    lower_val = metrics["roc_auc_lower"]
    upper_val = metrics["roc_auc_upper"]
    assert isinstance(mean_val, (int, float)), "roc_auc_mean must be a number"
    assert isinstance(lower_val, (int, float)), "roc_auc_lower must be a number"
    assert isinstance(upper_val, (int, float)), "roc_auc_upper must be a number"
    assert 0.0 <= mean_val <= 1.0, f"roc_auc_mean {mean_val} is out of valid ROC AUC range [0, 1]"
    assert 0.0 <= lower_val <= 1.0, f"roc_auc_lower {lower_val} is out of valid ROC AUC range [0, 1]"
    assert 0.0 <= upper_val <= 1.0, f"roc_auc_upper {upper_val} is out of valid ROC AUC range [0, 1]"
    assert lower_val <= mean_val <= upper_val, (
        "Metrics percentiles are inconsistent: expected lower <= mean <= upper"
    )

    for key, expected in expected_metrics.items():
        assert np.isclose(metrics[key], expected, rtol=1e-10, atol=1e-12), (
            f"{key} is incorrect: got {metrics[key]!r}, expected {expected!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
