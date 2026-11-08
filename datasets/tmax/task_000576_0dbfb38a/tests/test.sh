#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import subprocess
from collections import defaultdict
from decimal import Decimal

import psycopg2
import pytest
import redis


def database_snapshot(include_citations=False):
    conn = psycopg2.connect(
        host="localhost",
        dbname="research",
        user="postgres",
        password="password",
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, score FROM authors")
            authors = {int(author_id): score for author_id, score in cur.fetchall()}

            citations = None
            if include_citations:
                citations = defaultdict(set)
                cur.execute("SELECT citing_author_id, cited_author_id FROM citations")
                for citing_id, cited_id in cur.fetchall():
                    citations[int(citing_id)].add(str(int(cited_id)))
                citations = dict(citations)
        return authors, citations
    finally:
        conn.close()


def test_extract_graph_performance_and_correctness():
    assert os.path.isfile('/app/extract_graph.py'), "/app/extract_graph.py is missing or is not a regular file"

    r = redis.Redis(host='localhost', port=6379, decode_responses=True)
    r.flushall()

    # Capture the database before execution. The supplied traffic worker only
    # increases scores, so every author already above the threshold must appear.
    before, citations = database_snapshot(include_citations=True)
    required_ids = {author_id for author_id, score in before.items() if score > Decimal('50.0')}

    start = time.time()
    try:
        result = subprocess.run(
            ["python", "/app/extract_graph.py"],
            capture_output=True,
            timeout=3.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Execution time exceeded the 2.5 second limit")
    runtime = time.time() - start

    assert result.returncode == 0, f"Script failed with error: {result.stderr.decode('utf-8', errors='ignore')}"

    after, _ = database_snapshot(include_citations=False)

    # Retain the original basic assertions.
    keys = r.keys("author:*:score")
    assert len(keys) > 0, "No author score keys found in Redis. The script did not populate the expected data."

    sample_key = keys[0]
    author_id = sample_key.split(":")[1]
    score_val = r.get(sample_key)
    assert score_val is not None
    try:
        float(score_val)
    except ValueError:
        pytest.fail(f"Score value '{score_val}' for key {sample_key} is not a valid float.")

    cites_key = f"author:{author_id}:cites"
    key_type = r.type(cites_key)
    if key_type != 'none':
        assert key_type == 'set', f"Expected {cites_key} to be a Redis Set, got {key_type}"

    # Validate every projected author, not just one sampled key.
    score_key_re = re.compile(r'^author:([0-9]+):score$')
    output_ids = set()
    for key in keys:
        match = score_key_re.fullmatch(key)
        assert match, f"Malformed score key: {key}"
        output_ids.add(int(match.group(1)))

    assert required_ids <= output_ids, "Redis is missing authors that were above 50.0 when extraction began"
    assert output_ids <= set(before), "Redis contains author IDs that did not exist when extraction began"

    # An author that crossed the threshold concurrently may appear, but no
    # author still at or below the threshold after execution may appear.
    invalid_ids = {
        author_id for author_id in output_ids
        if author_id not in after or after[author_id] <= Decimal('50.0')
    }
    assert not invalid_ids, f"Redis contains authors whose scores are not above 50.0: {sorted(invalid_ids)[:20]}"

    expected_redis_keys = set()
    for author_id in output_ids:
        score_key = f"author:{author_id}:score"
        expected_redis_keys.add(score_key)

        raw_score = r.get(score_key)
        assert raw_score is not None
        try:
            stored_score = Decimal(raw_score)
        except Exception:
            pytest.fail(f"Score value '{raw_score}' for {score_key} is not numeric")
        assert stored_score.is_finite(), f"Non-finite score stored in {score_key}"
        assert stored_score.as_tuple().exponent >= -2, f"Score in {score_key} was not rounded to 2 decimal places"

        low = before[author_id].quantize(Decimal('0.01'))
        high = after[author_id].quantize(Decimal('0.01'))
        assert low <= stored_score <= high, (
            f"Incorrect score for author {author_id}: got {stored_score}, "
            f"expected a concurrently valid rounded value between {low} and {high}"
        )

        expected_cites = citations.get(author_id, set())
        cites_key = f"author:{author_id}:cites"
        if expected_cites:
            expected_redis_keys.add(cites_key)
            assert r.type(cites_key) == 'set', f"Expected {cites_key} to be a Redis Set"
            assert r.smembers(cites_key) == expected_cites, f"Incorrect citation set for author {author_id}"
        else:
            assert r.type(cites_key) == 'none', f"Unexpected citations stored for author {author_id}"

    actual_projection_keys = set(r.keys('author:*'))
    assert actual_projection_keys == expected_redis_keys, "Redis contains missing, extra, or malformed projection keys"

    assert runtime <= 2.5, f"Execution time {runtime:.3f}s exceeded the threshold of 2.5s. The script is not efficient enough."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
