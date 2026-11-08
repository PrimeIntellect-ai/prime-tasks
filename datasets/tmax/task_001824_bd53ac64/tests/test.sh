#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import urllib.request
import urllib.error
import re
import sqlite3
import pytest

RAW_DATA_PATH = '/home/user/raw_data.jsonl'
DB_PATH = '/home/user/etl_store.db'


def load_docs():
    if not os.path.exists(RAW_DATA_PATH):
        pytest.fail(f"Raw data file {RAW_DATA_PATH} is missing.")

    docs = {}
    with open(RAW_DATA_PATH, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            item = json.loads(line)
            docs[item['id']] = item['text']
    return docs


def tokenize(text):
    cleaned = re.sub(r'[^a-z0-9\s]', '', text.lower())
    return [t for t in cleaned.split(' ') if t]


def compute_expected_similarities():
    docs = load_docs()
    tokenized_docs = {doc_id: tokenize(text) for doc_id, text in docs.items()}
    N = len(tokenized_docs)

    df = {}
    for tokens in tokenized_docs.values():
        for term in set(tokens):
            df[term] = df.get(term, 0) + 1

    tf_idf = {}
    for doc_id, tokens in tokenized_docs.items():
        tf = {}
        for term in tokens:
            tf[term] = tf.get(term, 0) + 1
        tf_idf[doc_id] = {
            term: count * math.log(N / df[term])
            for term, count in tf.items()
        }

    norms = {
        doc_id: math.sqrt(sum(value ** 2 for value in vector.values()))
        for doc_id, vector in tf_idf.items()
    }

    def get_top_3(target_id):
        target_vec = tf_idf[target_id]
        target_norm = norms[target_id]
        similarities = []

        for doc_id, vector in tf_idf.items():
            if doc_id == target_id:
                continue
            common_terms = set(target_vec) & set(vector)
            dot_product = sum(target_vec[t] * vector[t] for t in common_terms)
            if target_norm == 0 or norms[doc_id] == 0:
                similarity = 0
            else:
                similarity = dot_product / (target_norm * norms[doc_id])
            similarities.append((doc_id, similarity))

        similarities.sort(key=lambda item: (-item[1], item[0]))
        return [item[0] for item in similarities[:3]]

    return get_top_3


def fetch_similar(doc_id):
    url = 'http://127.0.0.1:8080/similar?id=' + urllib.parse.quote(doc_id)
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            try:
                data = json.loads(response.read().decode('utf-8'))
            except json.JSONDecodeError:
                pytest.fail(f"Server response for {doc_id} is not valid JSON.")
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to server at {url}: {e}")

    assert isinstance(data, dict), f"Response for {doc_id} must be a JSON object."
    assert 'similar_ids' in data, "Response JSON missing 'similar_ids' key."
    assert isinstance(data['similar_ids'], list), "'similar_ids' must be a list."
    return data['similar_ids']


def test_database_exists():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a file."

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()
        assert len(tables) > 0, "Database exists but contains no tables."

        stored_chunks = []
        for (table_name,) in tables:
            quoted_name = '"' + table_name.replace('"', '""') + '"'
            cursor.execute(f"SELECT * FROM {quoted_name}")
            for row in cursor.fetchall():
                for value in row:
                    if value is None:
                        continue
                    if isinstance(value, bytes):
                        stored_chunks.append(value.lower())
                    else:
                        stored_chunks.append(str(value).lower().encode('utf-8'))
        conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to read SQLite database at {DB_PATH}: {e}")

    stored = b'\n'.join(stored_chunks)
    docs = load_docs()

    for doc_id in docs:
        assert doc_id.lower().encode('utf-8') in stored, (
            f"Database does not contain document identifier {doc_id}."
        )

    vocabulary = sorted({term for text in docs.values() for term in tokenize(text)})
    missing_terms = [term for term in vocabulary if term.encode('utf-8') not in stored]
    assert not missing_terms, (
        "Database does not contain the extracted documents or complete vocabulary; "
        f"missing terms: {missing_terms}"
    )


def test_server_running_and_correct():
    get_top_3 = compute_expected_similarities()
    expected_doc3 = get_top_3('doc3')
    actual_doc3 = fetch_similar('doc3')
    assert actual_doc3 == expected_doc3, f"Expected {expected_doc3} for doc3, got {actual_doc3}"


def test_server_correct_for_every_document():
    get_top_3 = compute_expected_similarities()
    for doc_id in sorted(load_docs()):
        expected = get_top_3(doc_id)
        actual = fetch_similar(doc_id)
        assert actual == expected, f"Expected {expected} for {doc_id}, got {actual}"


def test_doc1_recommendations_file():
    output_path = '/home/user/doc1_recommendations.json'
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    get_top_3 = compute_expected_similarities()
    expected_doc1 = get_top_3('doc1')

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON.")

    assert 'similar_ids' in data, f"JSON in {output_path} missing 'similar_ids' key."
    assert data['similar_ids'] == expected_doc1, f"Expected {expected_doc1} in {output_path}, got {data['similar_ids']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
