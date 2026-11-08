#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import string
import subprocess
import tempfile
import uuid
import pytest

BINARY_PATH = "/home/user/query_sanitizer/target/release/query_sanitizer"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"
EVIL_CORPUS_DIR = "/app/corpora/evil/"

def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Expected compiled Rust binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"

def run_sanitizer(file_path):
    try:
        result = subprocess.run(
            [BINARY_PATH, file_path],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {str(e)}"

def test_clean_corpus():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Binary not found")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, f"No JSON files found in clean corpus dir: {CLEAN_CORPUS_DIR}"

    failed_files = []
    for filename in clean_files:
        file_path = os.path.join(CLEAN_CORPUS_DIR, filename)
        output = run_sanitizer(file_path)
        if output != "ACCEPT":
            failed_files.append((filename, output))

    if failed_files:
        details = ", ".join([f"{name} (got {out})" for name, out in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected or failed: {details}")

def test_evil_corpus():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Binary not found")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, f"No JSON files found in evil corpus dir: {EVIL_CORPUS_DIR}"

    failed_files = []
    for filename in evil_files:
        file_path = os.path.join(EVIL_CORPUS_DIR, filename)
        output = run_sanitizer(file_path)
        if output != "REJECT":
            failed_files.append((filename, output))

    if failed_files:
        details = ", ".join([f"{name} (got {out})" for name, out in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed or failed: {details}")

def random_word():
    alphabet = string.ascii_letters + string.digits + "_-"
    return ''.join(secrets.choice(alphabet) for _ in range(secrets.randbelow(18) + 6))

def expected_for(document):
    if document["pagination"]["limit"] > 100:
        return "REJECT"
    if ";" in document["source_document"]:
        return "REJECT"
    for join in document.get("graph_mapping", {}).get("joins", []):
        if "condition" not in join:
            return "REJECT"
    return "ACCEPT"

def make_document(kind):
    source = random_word()
    limit = secrets.randbelow(101)
    joins = [{
        "type": secrets.choice(["inner", "left", "right"]),
        "target": random_word(),
        "condition": f"{random_word()}.id = {random_word()}.ref_id"
    }]

    if kind == "large_limit":
        limit = 101 + secrets.randbelow(100000)
    elif kind == "semicolon":
        position = secrets.randbelow(len(source) + 1)
        source = source[:position] + ";" + source[position:]
    elif kind == "missing_condition":
        joins.append({"type": "inner", "target": random_word()})
    elif kind == "combined":
        limit = 101 + secrets.randbelow(100000)
        source += ";" + random_word()
        joins.append({"type": "left", "target": random_word()})
    elif kind == "no_joins":
        joins = []

    document = {
        "source_document": source,
        "graph_mapping": {
            "node_label": random_word(),
            "joins": joins
        },
        "pagination": {
            "limit": limit,
            "offset": secrets.randbelow(10000)
        }
    }
    return document

def test_generated_content_based_cases():
    if not os.path.isfile(BINARY_PATH):
        pytest.skip("Binary not found")

    kinds = (
        ["valid"] * 10 + ["no_joins"] * 5 +
        ["large_limit"] * 10 + ["semicolon"] * 10 +
        ["missing_condition"] * 10 + ["combined"] * 5
    )
    random.SystemRandom().shuffle(kinds)
    failures = []

    with tempfile.TemporaryDirectory(prefix=f"query_inputs_{uuid.uuid4().hex}_") as temp_dir:
        for kind in kinds:
            document = make_document(kind)
            expected = expected_for(document)
            path = os.path.join(temp_dir, f"{uuid.uuid4().hex}.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(document, handle)
            output = run_sanitizer(path)
            if output != expected:
                failures.append((kind, expected, output))

        malformed_path = os.path.join(temp_dir, f"{uuid.uuid4().hex}.json")
        with open(malformed_path, "w", encoding="utf-8") as handle:
            handle.write('{"source_document": "' + random_word() + '", "pagination": {"limit": 50')
        malformed_output = run_sanitizer(malformed_path)
        if malformed_output != "REJECT":
            failures.append(("malformed_json", "REJECT", malformed_output))

    if failures:
        details = ", ".join(
            f"{kind} expected {expected} (got {actual})"
            for kind, expected, actual in failures
        )
        pytest.fail(f"Generated validation cases failed: {details}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
