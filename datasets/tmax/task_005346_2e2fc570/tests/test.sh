#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import subprocess
import time

import numpy as np
import pytest
import requests
from sklearn.linear_model import Ridge
from sklearn.model_selection import KFold

BASE_URL = "http://127.0.0.1:8080"
HEADERS = {"X-API-Token": "token_ds_7788"}
FEATURE_NAMES = [f"f{i}" for i in range(1, 21)]
DB_ENV = {**os.environ, "PGPASSWORD": "password123"}


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def psql(sql, capture=False, stdin=None):
    return run(
        ["psql", "-h", "127.0.0.1", "-U", "admin", "-d", "telemetry",
         "-v", "ON_ERROR_STOP=1", "-c", sql],
        env=DB_ENV,
        input=stdin,
        capture_output=capture,
    )


def prepare_random_fixture():
    # Replace the development fixture after the agent has finished with fresh,
    # unpredictable data so a hard-coded response cannot pass.
    rng = np.random.default_rng(secrets.randbits(128))
    n = 72
    values = rng.normal(0.0, 1.0, size=(n, 20))
    values[:, 5] = 1.7 * values[:, 1]       # f6 redundant with f2
    values[:, 11] = 0.8 * values[:, 3]      # f12 redundant with f4
    values[:, 19] = 1.2 * values[:, 0]      # f20 redundant with f1
    target = (
        8.0 * values[:, 0]
        - 6.0 * values[:, 2]
        + 4.0 * values[:, 4]
        + 3.0 * values[:, 7]
        - 2.0 * values[:, 9]
        + rng.normal(0.0, 0.02, size=n)
    )

    missing = rng.random((n, 20)) < 0.06
    # Leave enough observations in every column and in each redundant pair.
    missing[:8, :] = False
    stored = values.copy()
    stored[missing] = np.nan

    psql("DROP TABLE IF EXISTS public.raw_signals; CREATE TABLE public.raw_signals (id INTEGER PRIMARY KEY, target DOUBLE PRECISION, " +
         ", ".join(f"{name} DOUBLE PRECISION" for name in FEATURE_NAMES) + ");")

    output = io.StringIO()
    writer = csv.writer(output, lineterminator="\n")
    for i in range(n):
        row = [i + 1, repr(float(target[i]))]
        row.extend("" if np.isnan(v) else repr(float(v)) for v in stored[i])
        writer.writerow(row)
    psql("COPY public.raw_signals FROM STDIN WITH (FORMAT csv, NULL '');", stdin=output.getvalue())
    run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "DEL", "dataset:cleaned"], capture_output=True)


def read_database_rows():
    result = psql(
        "COPY (SELECT id, target, " + ", ".join(FEATURE_NAMES) +
        " FROM public.raw_signals ORDER BY id) TO STDOUT WITH (FORMAT csv, HEADER true);",
        capture=True,
    )
    rows = list(csv.DictReader(io.StringIO(result.stdout)))
    ids = np.array([int(r["id"]) for r in rows], dtype=int)
    targets = np.array([float(r["target"]) for r in rows], dtype=float)
    matrix = np.array([
        [float(r[name]) if r[name] != "" else np.nan for name in FEATURE_NAMES]
        for r in rows
    ], dtype=float)
    return ids, targets, matrix


def derive_expected_pipeline():
    ids, targets, matrix = read_database_rows()

    dropped = set()
    for lower in range(matrix.shape[1]):
        if lower in dropped:
            continue
        for higher in range(lower + 1, matrix.shape[1]):
            if higher in dropped:
                continue
            mask = ~np.isnan(matrix[:, lower]) & ~np.isnan(matrix[:, higher])
            correlation = np.corrcoef(matrix[mask, lower], matrix[mask, higher])[0, 1]
            if abs(float(correlation)) > 0.90:
                dropped.add(higher)

    kept_indices = [i for i in range(20) if i not in dropped]
    cleaned = matrix[:, kept_indices].copy()
    means = np.nanmean(cleaned, axis=0)
    missing_rows, missing_cols = np.where(np.isnan(cleaned))
    cleaned[missing_rows, missing_cols] = means[missing_cols]

    fold_importances = []
    splitter = KFold(n_splits=3, shuffle=False)
    for train_indices, _ in splitter.split(cleaned):
        model = Ridge(alpha=1.0)
        model.fit(cleaned[train_indices], targets[train_indices])
        fold_importances.append(np.abs(model.coef_))
    importances = np.mean(np.vstack(fold_importances), axis=0)
    top_positions = np.argsort(-importances, kind="stable")[:5]
    selected = [FEATURE_NAMES[kept_indices[p]] for p in top_positions]

    expected_rows = []
    for row_number, row_id in enumerate(ids):
        record = {"id": int(row_id), "target": float(targets[row_number])}
        for name, position in zip(selected, top_positions):
            record[name] = float(cleaned[row_number, position])
        expected_rows.append(record)
    return selected, expected_rows


def assert_cleaned_rows(actual, expected, selected):
    assert isinstance(actual, list), "Cleaned dataset must be a JSON array."
    assert len(actual) == len(expected), f"Expected {len(expected)} cleaned rows, got {len(actual)}."
    assert all(isinstance(row, dict) for row in actual), "Every cleaned row must be a JSON object."

    required_keys = {"id", "target", *selected}
    by_id = {}
    for row in actual:
        assert set(row) == required_keys, f"Unexpected cleaned-row columns: {set(row)}"
        assert isinstance(row["id"], (int, float)) and not isinstance(row["id"], bool)
        row_id = int(row["id"])
        assert float(row["id"]) == row_id, f"Non-integral id value: {row['id']}"
        assert row_id not in by_id, f"Duplicate cleaned row id {row_id}"
        by_id[row_id] = row

    for wanted in expected:
        assert wanted["id"] in by_id, f"Missing cleaned row id {wanted['id']}"
        got = by_id[wanted["id"]]
        for key, value in wanted.items():
            assert isinstance(got[key], (int, float)) and not isinstance(got[key], bool), (
                f"Column {key} for id {wanted['id']} is not numeric"
            )
            assert np.isfinite(float(got[key])), f"Column {key} contains a non-finite value"
            assert float(got[key]) == pytest.approx(value, rel=1e-7, abs=1e-8), (
                f"Incorrect {key} for id {wanted['id']}"
            )


def test_end_to_end_feature_engineering_flow():
    prepare_random_fixture()
    expected_features, expected_rows = derive_expected_pipeline()

    # Every endpoint must reject missing or incorrect authorization.
    try:
        resp_unauth = requests.get(f"{BASE_URL}/fetch_cleaned", timeout=5)
        assert resp_unauth.status_code in (401, 403)
        resp_bad_post = requests.post(
            f"{BASE_URL}/engineer_features",
            headers={"X-API-Token": "wrong-token"},
            timeout=5,
        )
        assert resp_bad_post.status_code in (401, 403)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the service at {BASE_URL}: {exc}")

    unauthorized_cache = run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "GET", "dataset:cleaned"],
        capture_output=True,
    ).stdout.strip()
    assert not unauthorized_cache or unauthorized_cache == "(nil)", "Unauthorized POST performed engineering work."

    resp_engineer = requests.post(f"{BASE_URL}/engineer_features", headers=HEADERS, timeout=30)
    assert resp_engineer.status_code == 200, (
        f"Expected 200 OK from /engineer_features, got {resp_engineer.status_code}: {resp_engineer.text}"
    )
    try:
        response_data = resp_engineer.json()
    except ValueError:
        pytest.fail(f"Response from /engineer_features was not valid JSON: {resp_engineer.text}")
    assert response_data.get("status") == "engineered"

    features_file = "/home/user/selected_features.json"
    assert os.path.isfile(features_file), f"File {features_file} does not exist."
    with open(features_file, "r", encoding="utf-8") as handle:
        try:
            features = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail(f"File {features_file} is not valid JSON.")
    assert isinstance(features, list)
    assert len(features) == 5
    assert len(set(features)) == 5
    assert all(isinstance(name, str) for name in features)
    assert set(features) == set(expected_features), (
        f"Selected features {features} do not match computed top features {expected_features}."
    )

    redis_out = run(
        ["redis-cli", "-h", "127.0.0.1", "-p", "6379", "GET", "dataset:cleaned"],
        capture_output=True,
    ).stdout.strip()
    assert redis_out and redis_out != "(nil)", "Redis key dataset:cleaned is missing."
    try:
        redis_data = json.loads(redis_out)
    except json.JSONDecodeError:
        pytest.fail("Redis key dataset:cleaned does not contain valid JSON.")
    assert_cleaned_rows(redis_data, expected_rows, expected_features)

    resp_fetch = requests.get(f"{BASE_URL}/fetch_cleaned", headers=HEADERS, timeout=5)
    assert resp_fetch.status_code == 200, (
        f"Expected 200 OK from /fetch_cleaned, got {resp_fetch.status_code}: {resp_fetch.text}"
    )
    try:
        fetch_data = resp_fetch.json()
    except ValueError:
        pytest.fail(f"Response from /fetch_cleaned was not valid JSON: {resp_fetch.text}")
    assert fetch_data == redis_data, "Data returned from /fetch_cleaned does not match Redis."
    assert_cleaned_rows(fetch_data, expected_rows, expected_features)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
