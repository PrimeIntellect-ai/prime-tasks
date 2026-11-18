#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import uuid
import pytest

SCRIPT_PATH = "/home/user/detector.sh"
ANALYZER_PATH = "/app/query_analyzer"


def run_detector(path):
    return subprocess.run(
        ["bash", SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    )


def analyzer_expected(path):
    result = subprocess.run(
        [ANALYZER_PATH, path],
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    )
    output = result.stdout
    if "PLAN: FULL_SCAN" in output or "CENTRALITY > 100" in output:
        return 1
    assert "PLAN: INDEX_SCAN" in output, f"Unexpected analyzer output: {output!r}"
    return 0


def test_detector_script_exists():
    script_path = "/home/user/detector.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_adversarial_corpus():
    script_path = "/home/user/detector.sh"
    evil_dir = "/hidden/corpus/evil"
    clean_dir = "/hidden/corpus/clean"

    assert os.path.isdir(evil_dir), f"Missing directory: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing directory: {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No files found in the evil corpus."
    assert len(clean_files) > 0, "No files found in the clean corpus."

    evil_bypassed = []
    for evil_file in evil_files:
        result = run_detector(evil_file)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    clean_flagged = []
    for clean_file in clean_files:
        result = run_detector(clean_file)
        if result.returncode != 0:
            clean_flagged.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_flagged:
        errors.append(f"{len(clean_flagged)} of {len(clean_files)} clean modified/flagged: {', '.join(clean_flagged)}")

    assert not errors, " | ".join(errors)


def test_generated_queries_at_label_neutral_paths():
    assert os.path.isfile(ANALYZER_PATH), f"Missing analyzer: {ANALYZER_PATH}"
    nonce = uuid.uuid4().hex
    definitions = [
        {
            "type": "relational",
            "query": f"SELECT * FROM users /* {nonce} */",
            "WHERE": "",
            "parameters": {"tenant": nonce},
        },
        {
            "type": "graph",
            "query": f"MATCH (a)-[*]->(b) RETURN b /* {nonce} */",
            "depth": "*",
            "parameters": {"start": nonce},
        },
        {
            "type": "graph",
            "query": f"CALL algo.betweenness.stream('{nonce}') YIELD nodeId, score",
            "centrality": True,
            "parameters": {"limit": 500},
        },
        {
            "type": "document",
            "query": f"resources[*].owner:{nonce}",
            "parameters": {"scope": "all"},
        },
        {
            "type": "relational",
            "query": "SELECT name FROM users WHERE id = :id",
            "WHERE": "id = :id",
            "parameters": {"id": 17, "nonce": nonce},
        },
        {
            "type": "graph",
            "query": "MATCH (n:User {id: $id})-[:KNOWS]->(m) RETURN m",
            "depth": "1",
            "parameters": {"id": 23, "nonce": nonce},
        },
        {
            "type": "graph",
            "query": "MATCH (n)-[:MEMBER_OF]->(g) RETURN g",
            "centrality": False,
            "parameters": {"nonce": nonce},
        },
        {
            "type": "document",
            "query": "resource.owner = :owner",
            "fields": ["name", "owner"],
            "parameters": {"owner": nonce},
        },
    ]

    with tempfile.TemporaryDirectory(prefix="query_inputs_") as directory:
        paths = []
        for definition in definitions:
            path = os.path.join(directory, uuid.uuid4().hex + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(definition, handle, indent=2)
            paths.append(path)

        random.SystemRandom().shuffle(paths)
        failures = []
        observed = set()
        for path in paths:
            expected = analyzer_expected(path)
            observed.add(expected)
            result = run_detector(path)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)}: expected exit {expected}, got {result.returncode}"
                )

        assert observed == {0, 1}, "Generated suite must contain both analyzer outcomes"
        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
