#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import tempfile
import uuid

import pytest

BINARY_PATH = "/home/user/query_sanitizer/target/release/query_sanitizer"
CLEAN_CORPUS_DIR = "/app/test_corpora/clean"
EVIL_CORPUS_DIR = "/app/test_corpora/evil"


def test_sanitizer_binary_exists():
    assert os.path.exists(BINARY_PATH), f"Sanitizer binary not found at {BINARY_PATH}"
    assert os.path.isfile(BINARY_PATH), f"Sanitizer path {BINARY_PATH} is not a file"
    assert os.access(BINARY_PATH, os.X_OK), f"Sanitizer binary {BINARY_PATH} is not executable"
    assert stat.S_ISREG(os.stat(BINARY_PATH).st_mode), f"Sanitizer path {BINARY_PATH} is not a regular file"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer is not a compiled ELF binary"


def test_adversarial_corpus():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]

    assert clean_files, "No clean files found in corpus"
    assert evil_files, "No evil files found in corpus"

    clean_failed = []
    evil_failed = []

    for clean_file in clean_files:
        try:
            result = subprocess.run([BINARY_PATH, clean_file], capture_output=True, text=True, timeout=5)
            if result.returncode != 0 or "SAFE" not in result.stdout:
                clean_failed.append(os.path.basename(clean_file))
        except Exception:
            clean_failed.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        try:
            result = subprocess.run([BINARY_PATH, evil_file], capture_output=True, text=True, timeout=5)
            if result.returncode != 1 or "EVIL" not in result.stdout:
                evil_failed.append(os.path.basename(evil_file))
        except Exception:
            evil_failed.append(os.path.basename(evil_file))

    error_messages = []
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_randomized_path_independent_queries():
    rng = secrets.SystemRandom()
    cases = []

    # Generate fresh safe and evil pipelines. Labels are derived from the documented
    # resource limits, while paths contain no clean/evil marker.
    for _ in range(35):
        depth = rng.randrange(0, 6)
        safe_graph = [
            {"$match": {"status": uuid.uuid4().hex}},
            {"$graphLookup": {
                "from": "collection_" + uuid.uuid4().hex,
                "startWith": "$parent",
                "connectFromField": "parent",
                "connectToField": "name",
                "as": "result",
                "maxDepth": depth,
            }},
        ]
        cases.append((safe_graph, 0, "SAFE"))

        excessive_depth = rng.randrange(6, 10000)
        evil_graph = [{"$graphLookup": {
            "as": "result",
            "from": "collection_" + uuid.uuid4().hex,
            "maxDepth": excessive_depth,
        }}]
        cases.append((evil_graph, 1, "EVIL"))

    for _ in range(20):
        safe_lookup = [{"$lookup": {
            "from": "inventory_" + uuid.uuid4().hex,
            "pipeline": [{"$match": {"enabled": bool(rng.randrange(2))}}],
            "as": "items",
        }}]
        cases.append((safe_lookup, 0, "SAFE"))

        nested_lookup = [{"$lookup": {
            "from": "outer_" + uuid.uuid4().hex,
            "pipeline": [
                {"$match": {"token": uuid.uuid4().hex}},
                {"$lookup": {
                    "from": "inner_" + uuid.uuid4().hex,
                    "localField": "key",
                    "foreignField": "key",
                    "as": "joined",
                }},
            ],
            "as": "outer_join",
        }}]
        cases.append((nested_lookup, 1, "EVIL"))

    for _ in range(20):
        unbounded_graph = [{"$graphLookup": {
            "from": "collection_" + uuid.uuid4().hex,
            "startWith": "$parent",
            "connectFromField": "parent",
            "connectToField": "name",
            "as": "result",
        }}]
        cases.append((unbounded_graph, 1, "EVIL"))

        ordinary_lookup = [{"$lookup": {
            "from": "collection_" + uuid.uuid4().hex,
            "localField": "item",
            "foreignField": "sku",
            "as": "docs",
        }}]
        cases.append((ordinary_lookup, 0, "SAFE"))

    rng.shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="qs-" + uuid.uuid4().hex + "-") as directory:
        materialized = []
        for pipeline, expected_code, expected_text in cases:
            path = os.path.join(directory, uuid.uuid4().hex + ".json")
            with open(path, "w", encoding="utf-8") as f:
                if rng.randrange(2):
                    json.dump(pipeline, f, separators=(",", ":"))
                else:
                    json.dump(pipeline, f, indent=rng.choice([1, 2, 4]))
                    f.write("\n")
            materialized.append((path, expected_code, expected_text))

        rng.shuffle(materialized)
        for path, expected_code, expected_text in materialized:
            try:
                result = subprocess.run(
                    [BINARY_PATH, path], capture_output=True, text=True, timeout=5
                )
                if result.returncode != expected_code or result.stdout.strip() != expected_text:
                    failures.append(
                        f"{os.path.basename(path)} expected ({expected_code}, {expected_text}) "
                        f"but got ({result.returncode}, {result.stdout.strip()!r})"
                    )
            except Exception as exc:
                failures.append(f"{os.path.basename(path)} raised {exc!r}")

    assert not failures, "Randomized query failures: " + " | ".join(failures[:20])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
