#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import json
import csv
import secrets
import subprocess
import pytest
import pandas as pd
import numpy as np
from sklearn.feature_extraction.text import HashingVectorizer

SCRIPT_PATH = '/home/user/prepare_data.py'
SUMMARY_PATH = '/home/user/experiment_summary.json'
TRANSACTIONS_PATH = '/home/user/raw_data/transactions.csv'
QUERIES_PATH = '/home/user/raw_data/queries.json'
EXPECTED_KEYS = {
    "initial_rows",
    "outliers_removed",
    "cleaned_rows",
    "bootstrap_revenue_ci_lower",
    "bootstrap_revenue_ci_upper",
    "embedding_sum_mean"
}


def run_submission():
    assert os.path.isfile(SCRIPT_PATH), f"The required script {SCRIPT_PATH} does not exist."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} must be a regular Python script, not a symlink."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."
    subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} was removed while it ran."


def load_summary():
    assert os.path.isfile(SUMMARY_PATH), f"The file {SUMMARY_PATH} does not exist. Did you save the experiment summary?"
    with open(SUMMARY_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {SUMMARY_PATH} is not valid JSON.")


def reference_summary():
    transactions = pd.read_csv(TRANSACTIONS_PATH)
    with open(QUERIES_PATH, 'r') as f:
        queries = pd.DataFrame(json.load(f))

    joined = transactions.merge(queries, on='user_id', how='inner')
    initial_rows = len(joined)
    joined['user_query'] = joined['user_query'].fillna('empty')
    cleaned = joined[(joined['revenue'] >= 0) & (joined['revenue'] <= 5000)].copy()

    embeddings = HashingVectorizer(n_features=10).transform(cleaned['user_query'])
    cleaned['query_embedding_sum'] = np.asarray(embeddings.sum(axis=1)).ravel()

    revenues = cleaned['revenue'].to_numpy()
    np.random.seed(42)
    bootstrap_means = [
        np.random.choice(revenues, size=len(revenues), replace=True).mean()
        for _ in range(1000)
    ]
    lower, upper = np.percentile(bootstrap_means, [2.5, 97.5])

    return {
        'initial_rows': int(initial_rows),
        'outliers_removed': int(initial_rows - len(cleaned)),
        'cleaned_rows': int(len(cleaned)),
        'bootstrap_revenue_ci_lower': round(float(lower), 2),
        'bootstrap_revenue_ci_upper': round(float(upper), 2),
        'embedding_sum_mean': round(float(cleaned['query_embedding_sum'].mean()), 4),
    }


def test_prepare_data_script_exists_and_executes():
    run_submission()


def test_experiment_summary_exists():
    assert os.path.isfile(SUMMARY_PATH), f"The file {SUMMARY_PATH} does not exist. Did you save the experiment summary?"


def test_experiment_summary_contents():
    summary = load_summary()

    # Recompute basic counts using stdlib
    with open(TRANSACTIONS_PATH, 'r') as f:
        reader = csv.DictReader(f)
        transactions = list(reader)

    with open(QUERIES_PATH, 'r') as f:
        queries = json.load(f)

    # Join
    query_map = {q['user_id']: q['user_query'] for q in queries}
    joined = []
    for t in transactions:
        if t['user_id'] in query_map:
            joined.append({
                'revenue': float(t['revenue']),
                'user_query': query_map[t['user_id']]
            })

    expected_initial_rows = len(joined)

    # Outliers
    valid_rows = [row for row in joined if 0 <= row['revenue'] <= 5000]
    expected_cleaned_rows = len(valid_rows)
    expected_outliers_removed = expected_initial_rows - expected_cleaned_rows

    # Check keys
    assert set(summary.keys()) == EXPECTED_KEYS, f"Expected keys {EXPECTED_KEYS}, but found {set(summary.keys())}."

    # Assert counts
    assert summary["initial_rows"] == expected_initial_rows, f"Expected initial_rows to be {expected_initial_rows}, got {summary['initial_rows']}."
    assert summary["outliers_removed"] == expected_outliers_removed, f"Expected outliers_removed to be {expected_outliers_removed}, got {summary['outliers_removed']}."
    assert summary["cleaned_rows"] == expected_cleaned_rows, f"Expected cleaned_rows to be {expected_cleaned_rows}, got {summary['cleaned_rows']}."

    # Assert complex computed values
    assert isinstance(summary["bootstrap_revenue_ci_lower"], (int, float)), "bootstrap_revenue_ci_lower must be a float."
    assert isinstance(summary["bootstrap_revenue_ci_upper"], (int, float)), "bootstrap_revenue_ci_upper must be a float."
    assert isinstance(summary["embedding_sum_mean"], (int, float)), "embedding_sum_mean must be a float."

    assert abs(summary["bootstrap_revenue_ci_lower"] - 72.43) < 0.01, f"Expected bootstrap_revenue_ci_lower to be ~72.43, got {summary['bootstrap_revenue_ci_lower']}."
    assert abs(summary["bootstrap_revenue_ci_upper"] - 250.71) < 0.01, f"Expected bootstrap_revenue_ci_upper to be ~250.71, got {summary['bootstrap_revenue_ci_upper']}."
    assert abs(summary["embedding_sum_mean"] - 0.165) < 0.001, f"Expected embedding_sum_mean to be ~0.165, got {summary['embedding_sum_mean']}."


def test_script_processes_unseen_inputs():
    with open(TRANSACTIONS_PATH, 'rb') as f:
        original_transactions = f.read()
    with open(QUERIES_PATH, 'rb') as f:
        original_queries = f.read()

    token = secrets.token_hex(8)
    offset = secrets.randbelow(10000) / 100.0
    transactions = [
        ['txn_a', 'alpha', 11.25 + offset],
        ['txn_b', 'beta', 83.50 + offset],
        ['txn_c', 'gamma', -1.0 - offset],
        ['txn_d', 'delta', 5001.0 + offset],
        ['txn_e', 'alpha', 317.75 + offset],
        ['txn_f', 'epsilon', 44.0 + offset],
        ['txn_g', 'zeta', 902.25 + offset],
        ['txn_h', 'eta', 5.5 + offset],
        ['txn_i', 'theta', 1200.0 + offset],
        ['txn_j', 'iota', 260.25 + offset],
        ['txn_k', 'without_query', 999.0 + offset],
    ]
    queries = [
        {'user_id': 'alpha', 'user_query': f'alpha_{token} shoes'},
        {'user_id': 'beta', 'user_query': None},
        {'user_id': 'gamma', 'user_query': f'gamma_{token}'},
        {'user_id': 'delta', 'user_query': f'delta_{token} premium'},
        {'user_id': 'epsilon', 'user_query': f'epsilon_{token} sale'},
        {'user_id': 'zeta', 'user_query': f'zeta_{token} running'},
        {'user_id': 'eta', 'user_query': f'eta_{token}'},
        {'user_id': 'theta', 'user_query': f'theta_{token} search words'},
        {'user_id': 'iota', 'user_query': f'iota_{token} gloves'},
        {'user_id': 'query_without_transaction', 'user_query': f'unused_{token}'},
    ]

    try:
        with open(TRANSACTIONS_PATH, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['txn_id', 'user_id', 'revenue'])
            writer.writerows(transactions)
        with open(QUERIES_PATH, 'w') as f:
            json.dump(queries, f)

        expected = reference_summary()
        run_submission()
        actual = load_summary()

        assert set(actual.keys()) == EXPECTED_KEYS
        assert actual['initial_rows'] == expected['initial_rows']
        assert actual['outliers_removed'] == expected['outliers_removed']
        assert actual['cleaned_rows'] == expected['cleaned_rows']
        assert actual['bootstrap_revenue_ci_lower'] == pytest.approx(expected['bootstrap_revenue_ci_lower'], abs=1e-9)
        assert actual['bootstrap_revenue_ci_upper'] == pytest.approx(expected['bootstrap_revenue_ci_upper'], abs=1e-9)
        assert actual['embedding_sum_mean'] == pytest.approx(expected['embedding_sum_mean'], abs=1e-9)
    finally:
        with open(TRANSACTIONS_PATH, 'wb') as f:
            f.write(original_transactions)
        with open(QUERIES_PATH, 'wb') as f:
            f.write(original_queries)
        if os.path.isfile(SCRIPT_PATH):
            subprocess.run(['python3', SCRIPT_PATH], cwd='/home/user', timeout=60,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
