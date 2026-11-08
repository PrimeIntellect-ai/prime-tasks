#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import secrets
import pytest
import requests
import pandas as pd
import numpy as np
import redis
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SEARCH_URL = "http://localhost:8080/api/search"
INGEST_URL = "http://localhost:8080/api/ingest"
CSV_PATH = "/home/user/data/training_data.csv"
SCRIPT_PATH = "/home/user/ingest_data.py"


def extract_ids(data):
    pred_ids = []
    if isinstance(data, list):
        pred_ids = data
    elif isinstance(data, dict):
        for key in ['ids', 'results', 'data']:
            if key in data:
                pred_data = data[key]
                if pred_data and isinstance(pred_data[0], dict) and 'id' in pred_data[0]:
                    pred_ids = [item['id'] for item in pred_data]
                else:
                    pred_ids = pred_data
                break
    return pred_ids


def test_ingest_script_exists():
    path = SCRIPT_PATH
    assert os.path.isfile(path), f"Ingest script missing at {path}"


def test_nginx_routing_and_recall_metric():
    csv_path = CSV_PATH
    assert os.path.isfile(csv_path), f"Data file missing at {csv_path}"

    df = pd.read_csv(csv_path)
    assert 'id' in df.columns and 'description' in df.columns, "CSV must contain 'id' and 'description' columns"

    vectorizer = TfidfVectorizer()
    tfidf_matrix = vectorizer.fit_transform(df['description'].fillna(''))

    np.random.seed(42)
    sample_indices = np.random.choice(len(df), size=min(20, len(df)), replace=False)
    queries = df.iloc[sample_indices]['description'].tolist()

    recalls = []
    for idx, query in zip(sample_indices, queries):
        q_vec = vectorizer.transform([query])
        sims = cosine_similarity(q_vec, tfidf_matrix).flatten()
        top5_idx = sims.argsort()[-5:][::-1]
        gt_ids = set(df.iloc[top5_idx]['id'].values)

        try:
            resp = requests.get(SEARCH_URL, params={'query': query}, timeout=5)
            assert resp.status_code == 200, f"API returned status {resp.status_code} for /api/search"
            data = resp.json()
        except Exception as e:
            pytest.fail(f"Failed to query the search endpoint: {e}")

        pred_ids = extract_ids(data)
        if not pred_ids:
            pytest.fail(f"Could not extract IDs from API response: {data}")

        pred_ids_set = set(pred_ids[:5])
        recall = len(gt_ids.intersection(pred_ids_set)) / 5.0
        recalls.append(recall)

    avg_recall = np.mean(recalls)
    assert avg_recall >= 0.85, f"Average Recall@5 is {avg_recall:.2f}, which is below the threshold of 0.85"


def make_dataset(groups, start_id):
    records = []
    queries = []
    for group in range(groups):
        category = "category" + secrets.token_hex(10)
        queries.append(category)
        for item in range(5):
            unique = "item" + secrets.token_hex(10)
            records.append({
                "id": start_id + group * 5 + item,
                "text": f"{category} {category} {unique} product feature",
            })
    return records, queries


def expected_top5(records, queries):
    texts = [r['text'] for r in records]
    ids = [r['id'] for r in records]
    vectorizer = TfidfVectorizer()
    matrix = vectorizer.fit_transform(texts)
    expected = []
    for query in queries:
        sims = cosine_similarity(vectorizer.transform([query]), matrix).flatten()
        indices = sims.argsort()[-5:][::-1]
        expected.append({str(ids[i]) for i in indices})
    return expected


def assert_search_recall(records, queries):
    expected = expected_top5(records, queries)
    recalls = []
    for query, gt_ids in zip(queries, expected):
        response = requests.get(SEARCH_URL, params={'query': query}, timeout=5)
        assert response.status_code == 200, response.text
        pred_ids = extract_ids(response.json())
        assert pred_ids, f"No IDs returned for randomized query: {response.text}"
        predicted = {str(value) for value in pred_ids[:5]}
        recalls.append(len(gt_ids.intersection(predicted)) / 5.0)
    assert np.mean(recalls) >= 0.85, f"Randomized Recall@5 was {np.mean(recalls):.2f}"


def assert_redis_contains_substantial_data(client):
    keys = list(client.scan_iter(match='*'))
    assert keys, "Ingestion did not store any keys in Redis"
    dumped_bytes = 0
    for key in keys:
        dumped = client.dump(key)
        if dumped:
            dumped_bytes += len(dumped)
    assert dumped_bytes >= 200, "Redis contains no substantial stored corpus/vector data"


def test_randomized_ingest_pipeline_and_redis_storage():
    assert os.path.isfile(SCRIPT_PATH)
    assert os.path.isfile(CSV_PATH)

    backup = CSV_PATH + ".verifier_backup"
    hidden = CSV_PATH + ".verifier_hidden"
    shutil.copy2(CSV_PATH, backup)
    client = redis.Redis(host='localhost', port=6379, db=0)
    client.ping()

    try:
        # Replace the known CSV with an unpredictable corpus, clear Redis, and
        # actually execute the artifact the task required.
        records, queries = make_dataset(6, 1000000 + secrets.randbelow(1000000))
        pd.DataFrame({
            'id': [r['id'] for r in records],
            'description': [r['text'] for r in records],
        }).to_csv(CSV_PATH, index=False)
        client.flushdb()

        completed = subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, (
            f"ingest_data.py failed:\nSTDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}"
        )
        assert_redis_contains_substantial_data(client)

        # Remove the source file while searching so /api/search cannot answer by
        # rereading the CSV instead of using the ingested state.
        os.replace(CSV_PATH, hidden)
        assert_search_recall(records, queries)

        # Independently exercise /api/ingest with another unpredictable corpus.
        direct_records, direct_queries = make_dataset(5, 3000000 + secrets.randbelow(1000000))
        client.flushdb()
        response = requests.post(INGEST_URL, json=direct_records, timeout=10)
        assert response.status_code == 200, f"/api/ingest returned {response.status_code}: {response.text}"
        assert_redis_contains_substantial_data(client)
        assert_search_recall(direct_records, direct_queries)
    finally:
        if os.path.exists(backup):
            shutil.copy2(backup, CSV_PATH)
            os.unlink(backup)
        if os.path.exists(hidden):
            os.unlink(hidden)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
