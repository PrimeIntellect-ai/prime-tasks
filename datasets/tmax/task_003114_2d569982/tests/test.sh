#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import urllib.request
from urllib.parse import urlparse

import pytest
import redis


def test_final_dataset_metric_and_services():
    filepath = "/home/user/final_dataset.jsonl"
    assert os.path.isfile(filepath), f"Output file not found at {filepath}"

    with open(filepath, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 1000, f"Expected exactly 1000 lines in {filepath}, but got {len(lines)}"

    with open("/home/user/app/raw_texts.json", "r") as f:
        raw_documents = json.load(f)

    expected = {}
    for doc in raw_documents:
        tokens = doc.get("text", "").split()
        expected[str(doc["id"])] = {
            "tokens": tokens,
            "score": min(len(tokens) / 20.0, 1.0),
        }

    scores = []
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

        assert "score" in data, f"Line {i+1} missing 'score' key: {data}"
        assert isinstance(data["score"], (int, float)), f"Line {i+1} 'score' is not a number: {data['score']}"
        scores.append(data["score"])

        assert "id" in data, f"Line {i+1} missing 'id' key: {data}"
        assert "tokens" in data, f"Line {i+1} missing 'tokens' key: {data}"
        doc_id = str(data["id"])
        assert doc_id in expected, f"Line {i+1} has unknown document id: {data['id']}"
        assert isinstance(data["tokens"], list), f"Line {i+1} 'tokens' is not a list"
        assert data["tokens"] == expected[doc_id]["tokens"], f"Line {i+1} has incorrect tokens for id {doc_id}"
        assert math.isfinite(float(data["score"])), f"Line {i+1} has a non-finite score"
        assert abs(float(data["score"]) - expected[doc_id]["score"]) < 1e-12, f"Line {i+1} has incorrect score for id {doc_id}"

    assert len(scores) == 1000, f"Expected exactly 1000 valid JSON objects, got {len(scores)}"

    mean_score = sum(scores) / len(scores)
    assert mean_score >= 0.80, f"Mean score is {mean_score:.4f}, which is below the required threshold of 0.80"

    with open("/home/user/app/data_ingest/index.js", "r") as f:
        ingestor_source = f.read()
    redis_urls = re.findall(r"redis://[^'\"\s]+", ingestor_source)
    assert redis_urls, "The ingestor does not contain a Redis connection URL"
    valid_local_url = False
    for value in redis_urls:
        parsed = urlparse(value)
        if parsed.hostname in ("localhost", "127.0.0.1", "::1") and parsed.port in (None, 6379):
            valid_local_url = True
    assert valid_local_url, "The ingestor Redis URL is not configured for local Redis on the default port"
    assert "localhost:9999" not in ingestor_source, "The original misconfigured Redis URL remains"

    with open("/home/user/app/scoring_service/main.py", "r") as f:
        scoring_source = f.read()
    assert re.search(r"uvicorn\.run\s*\([^)]*\bport\s*=\s*8000\b", scoring_source, re.DOTALL), \
        "The scoring service main.py is not configured to run on port 8000"

    client = redis.Redis(host="localhost", port=6379, db=0, socket_connect_timeout=2, socket_timeout=2)
    assert client.ping() is True, "Redis is not running on the default port"
    assert client.llen("doc_queue") == 0, "Not all documents were consumed from doc_queue"

    canary_id = "verifier-service-canary"
    canary_text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
    client.rpush("doc_queue", json.dumps({"id": canary_id, "text": canary_text}))
    try:
        with urllib.request.urlopen("http://localhost:8000/process_next", timeout=5) as response:
            assert response.status == 200
            result = json.loads(response.read().decode("utf-8"))
    finally:
        # Remove the canary if a broken endpoint failed to consume it.
        remaining = client.lrange("doc_queue", 0, -1)
        for item in remaining:
            try:
                if json.loads(item).get("id") == canary_id:
                    client.lrem("doc_queue", 0, item)
            except Exception:
                pass

    canary_tokens = canary_text.split()
    assert result.get("id") == canary_id, "The scoring service did not process the queued document"
    assert result.get("tokens") == canary_tokens, "The scoring service returned incorrect tokens"
    assert isinstance(result.get("score"), (int, float)), "The scoring service returned a non-numeric score"
    assert abs(float(result["score"]) - min(len(canary_tokens) / 20.0, 1.0)) < 1e-12, \
        "The scoring service returned an incorrect score"
    assert client.llen("doc_queue") == 0, "The scoring service did not pop the canary from Redis"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
