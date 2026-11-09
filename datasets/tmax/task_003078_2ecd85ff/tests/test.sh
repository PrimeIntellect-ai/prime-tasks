#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import struct
import subprocess
import math
import uuid
from functools import lru_cache

import numpy as np
import requests
import pytest
from scipy import stats

DB_PATH = "/home/user/data/embeddings.db"
RAW_TEXTS_PATH = "/home/user/raw_texts.json"
BINARY_PATH = "/app/embed_oracle"
BASE_URL = "http://127.0.0.1:8080"

@lru_cache(maxsize=None)
def get_embedding_bytes(text):
    p = subprocess.run(
        [BINARY_PATH], input=text.encode("utf-8"), capture_output=True, check=True
    )
    assert len(p.stdout) == 64 * 4, (
        f"Oracle returned {len(p.stdout)} bytes instead of a 64-dimensional float32 vector"
    )
    return p.stdout

def get_embedding(text):
    raw = get_embedding_bytes(text)
    return struct.unpack("64f", raw)

def cosine_similarity(v1, v2):
    dot = sum(x * y for x, y in zip(v1, v2))
    norm1 = math.sqrt(sum(x * x for x in v1))
    norm2 = math.sqrt(sum(x * x for x in v2))
    if norm1 == 0 or norm2 == 0:
        return 0.0
    return dot / (norm1 * norm2)

def load_raw_texts():
    with open(RAW_TEXTS_PATH, "r") as f:
        return json.load(f)

def load_verified_docs():
    raw_texts = load_raw_texts()
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("SELECT id, text, embedding FROM docs").fetchall()
    finally:
        conn.close()

    assert len(rows) == len(raw_texts)
    assert sorted(row[1] for row in rows) == sorted(raw_texts), (
        "The texts stored in docs do not exactly match raw_texts.json"
    )

    docs = []
    for doc_id, text, blob in rows:
        assert isinstance(doc_id, int), "Document IDs must be integers"
        assert isinstance(text, str), "Document text must be stored as TEXT"
        assert isinstance(blob, bytes), "Embeddings must be stored as SQLite BLOB values"
        expected_blob = get_embedding_bytes(text)
        assert len(blob) == 256, f"Embedding for document {doc_id} is not 64 float32 values"
        assert blob == expected_blob, f"Incorrect embedding stored for document {doc_id}"
        docs.append({"id": doc_id, "text": text, "embedding": get_embedding(text)})
    return docs

def assert_close(actual, expected, name, tolerance=1e-6):
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool), (
        f"Value for '{name}' should be a number"
    )
    assert math.isfinite(float(actual)), f"Value for '{name}' must be finite"
    assert math.isclose(float(actual), float(expected), rel_tol=tolerance, abs_tol=tolerance), (
        f"Incorrect {name}: expected {expected}, got {actual}"
    )

def test_database_setup():
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='docs'")
    assert cursor.fetchone() is not None, "Table 'docs' does not exist in the database"

    cursor.execute("PRAGMA table_info(docs)")
    info = cursor.fetchall()
    columns = {row[1]: row[2] for row in info}
    assert 'id' in columns, "Column 'id' missing"
    assert 'text' in columns, "Column 'text' missing"
    assert 'embedding' in columns, "Column 'embedding' missing"
    assert columns['id'].upper() == 'INTEGER', "Column 'id' must be INTEGER"
    assert columns['text'].upper() == 'TEXT', "Column 'text' must be TEXT"
    assert columns['embedding'].upper() == 'BLOB', "Column 'embedding' must be BLOB"
    id_info = next(row for row in info if row[1] == 'id')
    assert id_info[5] == 1, "Column 'id' must be the primary key"

    raw_texts = load_raw_texts()
    cursor.execute("SELECT count(*) FROM docs")
    count = cursor.fetchone()[0]
    assert count == len(raw_texts), f"Expected {len(raw_texts)} rows in docs table, got {count}"
    conn.close()

    load_verified_docs()

def test_stats_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /stats endpoint: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /stats is not valid JSON")

    for key in ["mean_similarity", "p_value", "ci_lower", "ci_upper"]:
        assert key in data, f"Key '{key}' missing from /stats response"
        assert isinstance(data[key], (int, float)), f"Value for '{key}' should be a number"

    docs = load_verified_docs()
    similarities = np.asarray([
        cosine_similarity(docs[i]["embedding"], docs[j]["embedding"])
        for i in range(len(docs))
        for j in range(i + 1, len(docs))
    ], dtype=np.float64)

    expected_mean = float(np.mean(similarities))
    expected_p = float(stats.ttest_1samp(similarities, popmean=0.0).pvalue)
    standard_error = float(stats.sem(similarities))
    margin = float(stats.t.ppf(0.975, len(similarities) - 1) * standard_error)
    expected_lower = expected_mean - margin
    expected_upper = expected_mean + margin

    assert_close(data["mean_similarity"], expected_mean, "mean_similarity")
    assert_close(data["p_value"], expected_p, "p_value")
    assert_close(data["ci_lower"], expected_lower, "ci_lower")
    assert_close(data["ci_upper"], expected_upper, "ci_upper")

def check_search(query_text, top_k):
    payload = {"query": query_text, "top_k": top_k}
    try:
        response = requests.post(f"{BASE_URL}/search", json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /search endpoint: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /search is not valid JSON")

    assert isinstance(data, list), "Response from /search should be a list"
    assert len(data) == top_k, f"Expected {top_k} results, got {len(data)}"

    for item in data:
        assert "id" in item, "Key 'id' missing from search result"
        assert "text" in item, "Key 'text' missing from search result"
        assert "score" in item, "Key 'score' missing from search result"
        assert isinstance(item["score"], (int, float)), "Score should be a number"
        assert math.isfinite(float(item["score"])), "Score must be finite"

    scores = [item["score"] for item in data]
    assert scores == sorted(scores, reverse=True), (
        "Search results are not sorted by score in descending order"
    )

    query_embedding = get_embedding(query_text)
    docs = load_verified_docs()
    expected = sorted(
        [
            {
                "id": doc["id"],
                "text": doc["text"],
                "score": cosine_similarity(query_embedding, doc["embedding"]),
            }
            for doc in docs
        ],
        key=lambda item: item["score"],
        reverse=True,
    )[:top_k]

    for index, (actual, wanted) in enumerate(zip(data, expected)):
        assert actual["id"] == wanted["id"], f"Incorrect document ID at rank {index + 1}"
        assert actual["text"] == wanted["text"], f"Incorrect document text at rank {index + 1}"
        assert_close(actual["score"], wanted["score"], f"search score at rank {index + 1}", 1e-5)

def test_search_endpoint():
    check_search("test query", 3)
    check_search("semantic verifier probe " + uuid.uuid4().hex, 7)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
