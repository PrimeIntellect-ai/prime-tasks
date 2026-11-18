#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HARNESS_EOF' > /tmp/run_instrumented.py
import json
import runpy
import sys
import traceback

mode, log_path, script_path = sys.argv[1:4]

import sklearn.feature_extraction as feature_extraction
import sklearn.feature_extraction.text as text_module
import sklearn.metrics.pairwise as pairwise_module

RealTfidfVectorizer = text_module.TfidfVectorizer
real_cosine_similarity = pairwise_module.cosine_similarity
default_params = RealTfidfVectorizer().get_params(deep=False)
state = {"tfidf_calls": 0, "cosine_calls": 0, "default_params": True}

def recording_vectorizer(*args, **kwargs):
    obj = RealTfidfVectorizer(*args, **kwargs)
    state["tfidf_calls"] += 1
    if obj.get_params(deep=False) != default_params:
        state["default_params"] = False
    return obj

def recording_cosine_similarity(*args, **kwargs):
    state["cosine_calls"] += 1
    result = real_cosine_similarity(*args, **kwargs)
    if mode == "bad_diagonal":
        result = result.copy()
        result[0, 0] = 0.5
    return result

text_module.TfidfVectorizer = recording_vectorizer
feature_extraction.TfidfVectorizer = recording_vectorizer
pairwise_module.cosine_similarity = recording_cosine_similarity

try:
    runpy.run_path(script_path, run_name="__main__")
except BaseException as exc:
    with open(log_path, "w") as f:
        json.dump(state, f)
    if mode == "bad_diagonal" and isinstance(exc, AssertionError) and str(exc) == "Numerical accuracy check failed":
        sys.exit(0)
    traceback.print_exc()
    sys.exit(1)
else:
    with open(log_path, "w") as f:
        json.dump(state, f)
    if mode == "bad_diagonal":
        print("Script did not raise the required AssertionError", file=sys.stderr)
        sys.exit(1)
HARNESS_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SCRIPT_PATH = "/home/user/etl_pipeline.py"
RAW_PATH = "/home/user/raw_data.jsonl"
CSV_PATH = "/home/user/recommendations.csv"
HARNESS = "/tmp/run_instrumented.py"

ORIGINAL_DATA = """{"item_id": 10, "content": "the quick brown fox jumps over the lazy dog"}
{"item_id": 20, "content": "a quick brown fox"}
{"item_id": 30, "content": "the lazy dog sleeps all day"}
{"item_id": 40, "content": "a sleeping dog"}
{"item_id": 50, "content": "the quick brown fox jumps"}
"""

CUSTOM_ITEMS = [
    {"item_id": 71, "content": "violet amber copper"},
    {"item_id": 4, "content": "violet amber"},
    {"item_id": 38, "content": "ocean silver cloud"},
    {"item_id": 12, "content": "ocean silver"},
    {"item_id": 25, "content": "violet copper"},
    {"item_id": 2, "content": "isolatedword"},
]


def write_items(items):
    with open(RAW_PATH, "w") as f:
        for item in items:
            f.write(json.dumps(item) + "\n")


def assert_original_csv():
    csv_path = "/home/user/recommendations.csv"

    assert os.path.exists(csv_path), f"File {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"Path {csv_path} is not a file."

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["item_id", "rec_id", "score"], f"Incorrect CSV header. Got {header}"

        rows = list(reader)

    expected_rows = [
        (10, 50, 0.8573),
        (20, 50, 0.6974),
        (30, 10, 0.3708),
        (40, 30, 0.1873),
        (50, 10, 0.8573)
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(rows)}."

    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        try:
            actual_item_id = int(actual[0])
            actual_rec_id = int(actual[1])
            actual_score = float(actual[2])
        except ValueError as e:
            raise AssertionError(f"Row {i+1} has invalid data types: {actual}") from e

        assert actual_item_id == expected[0], f"Row {i+1} item_id mismatch. Expected {expected[0]}, got {actual_item_id}."
        assert actual_rec_id == expected[1], f"Row {i+1} rec_id mismatch. Expected {expected[1]}, got {actual_rec_id}."

        # Check if the score string is formatted to exactly 4 decimal places
        score_str = actual[2].strip()
        if "." in score_str:
            decimals = len(score_str.split(".")[1])
            assert decimals == 4, f"Row {i+1} score '{score_str}' is not formatted to exactly 4 decimal places."
        else:
            raise AssertionError(f"Row {i+1} score '{score_str}' missing decimal point.")

        assert abs(actual_score - expected[2]) <= 0.0001, f"Row {i+1} score mismatch. Expected {expected[2]}, got {actual_score}."


def expected_for(items):
    vectors = TfidfVectorizer().fit_transform([item["content"] for item in items])
    similarities = cosine_similarity(vectors)
    result = []
    for i, item in enumerate(items):
        candidates = [(similarities[i, j], items[j]["item_id"]) for j in range(len(items)) if j != i]
        best_score = max(score for score, _ in candidates)
        best_id = min(item_id for score, item_id in candidates if abs(score - best_score) <= 1e-12)
        result.append((item["item_id"], best_id, f"{best_score:.4f}"))
    return sorted(result)


def read_strict_csv():
    with open(CSV_PATH, "r", newline="") as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ["item_id", "rec_id", "score"]
    parsed = []
    for row in rows[1:]:
        assert len(row) == 3
        assert re.fullmatch(r"\d+\.\d{4}", row[2]), f"Bad score formatting: {row[2]}"
        parsed.append((int(row[0]), int(row[1]), row[2]))
    return parsed


def test_recommendations_csv_exists_and_correct():
    assert_original_csv()


def test_pipeline_exists_executes_and_implements_required_operations():
    assert os.path.exists(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a regular file."

    try:
        compile(open(SCRIPT_PATH, "rb").read(), SCRIPT_PATH, "exec")

        write_items(CUSTOM_ITEMS)
        if os.path.exists(CSV_PATH):
            os.unlink(CSV_PATH)
        log_path = "/tmp/pipeline_calls.json"
        subprocess.run(
            ["python3", HARNESS, "normal", log_path, SCRIPT_PATH],
            cwd="/home/user", check=True, timeout=30
        )
        with open(log_path) as f:
            calls = json.load(f)
        assert calls["tfidf_calls"] >= 1, "Pipeline did not use TfidfVectorizer."
        assert calls["default_params"], "TfidfVectorizer was not used with default parameters."
        assert calls["cosine_calls"] >= 1, "Pipeline did not call cosine_similarity."
        assert os.path.isfile(CSV_PATH), "Pipeline did not generate recommendations.csv."
        assert read_strict_csv() == expected_for(CUSTOM_ITEMS)

        if os.path.exists(CSV_PATH):
            os.unlink(CSV_PATH)
        bad_log = "/tmp/pipeline_bad_diagonal_calls.json"
        subprocess.run(
            ["python3", HARNESS, "bad_diagonal", bad_log, SCRIPT_PATH],
            cwd="/home/user", check=True, timeout=30
        )
        with open(bad_log) as f:
            bad_calls = json.load(f)
        assert bad_calls["tfidf_calls"] >= 1
        assert bad_calls["cosine_calls"] >= 1
        assert not os.path.exists(CSV_PATH), "Pipeline wrote output before failing its diagonal accuracy check."
    finally:
        with open(RAW_PATH, "w") as f:
            f.write(ORIGINAL_DATA)

    subprocess.run(["python3", SCRIPT_PATH], cwd="/home/user", check=True, timeout=30)
    assert_original_csv()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
