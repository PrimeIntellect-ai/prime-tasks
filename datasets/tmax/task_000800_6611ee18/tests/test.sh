#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
import uuid
import pytest

AGENT_SCRIPT = "/home/user/sanitizer.py"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def run_sanitizer(path, *extra):
    return subprocess.run(
        [AGENT_SCRIPT, path, *extra],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def test_sanitizer_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"{AGENT_SCRIPT} is not executable"


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No JSON files found in evil corpus"

    bypassed_files = []

    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run(
            ["python3", AGENT_SCRIPT, filepath],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        if result.returncode != 1:
            bypassed_files.append(filename)

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_files)}")


def test_clean_corpus_accepted():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No JSON files found in clean corpus"

    rejected_files = []

    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run(
            ["python3", AGENT_SCRIPT, filepath],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        if result.returncode != 0:
            rejected_files.append(filename)

    if rejected_files:
        pytest.fail(f"{len(rejected_files)} of {len(clean_files)} clean modified/rejected: {', '.join(rejected_files)}")


def expected_exit(query):
    limit = query.get("limit")
    if isinstance(limit, bool) or not isinstance(limit, (int, float)) or limit > 100:
        return 1

    if "traverse" in query:
        traverse = query["traverse"]
        if isinstance(traverse, dict):
            depth = traverse.get("depth", 0)
            if isinstance(depth, bool) or not isinstance(depth, (int, float)):
                depth = 0
            shortest = traverse.get("shortest_path") is True
            if depth > (10 if shortest else 3):
                return 1

    if "cross_mapping" in query:
        mapping = query["cross_mapping"]
        if not isinstance(mapping, dict) or mapping.get("indexed") is not True:
            return 1

    return 0


def test_generated_queries_on_unclassified_paths():
    rng = secrets.SystemRandom()
    cases = [
        {"limit": 100},
        {"limit": 101},
        {"other": "missing limit"},
        {"limit": 10, "traverse": {"depth": 3}},
        {"limit": 10, "traverse": {"depth": 4}},
        {"limit": 10, "traverse": {"depth": 10, "shortest_path": True}},
        {"limit": 10, "traverse": {"depth": 11, "shortest_path": True}},
        {"limit": 10, "cross_mapping": {"indexed": True}},
        {"limit": 10, "cross_mapping": {"indexed": False}},
        {"limit": 10, "cross_mapping": {}},
    ]

    for _ in range(80):
        query = {
            "limit": rng.randint(-20, 140),
            "nonce": uuid.uuid4().hex,
            "filter": {"field": uuid.uuid4().hex, "value": rng.randint(0, 100000)},
        }
        if rng.randrange(4) != 0:
            traverse = {"depth": rng.randint(0, 15)}
            if rng.randrange(2):
                traverse["shortest_path"] = rng.choice([True, False])
            query["traverse"] = traverse
        if rng.randrange(3) == 0:
            mapping = {}
            if rng.randrange(3) != 0:
                mapping["indexed"] = rng.choice([True, False])
            query["cross_mapping"] = mapping
        cases.append(query)

    with tempfile.TemporaryDirectory(prefix="query-check-") as tmp:
        failures = []
        for query in cases:
            filename = uuid.uuid4().hex + ".json"
            path = os.path.join(tmp, filename)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(query, f)
            expected = expected_exit(query)
            actual = run_sanitizer(path).returncode
            if actual != expected:
                failures.append((query, expected, actual))

        malformed = os.path.join(tmp, uuid.uuid4().hex + ".json")
        with open(malformed, "w", encoding="utf-8") as f:
            f.write('{"limit": 10,')
        malformed_rc = run_sanitizer(malformed).returncode
        if malformed_rc != 1:
            failures.append(("malformed JSON", 1, malformed_rc))

        assert not failures, f"Generated-query failures: {failures[:5]}"


def test_exactly_one_argument_is_required():
    no_args = subprocess.run(
        [AGENT_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    extra_args = subprocess.run(
        [AGENT_SCRIPT, "/dev/null", "/dev/null"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert no_args.returncode != 0, "Sanitizer accepted no query argument"
    assert extra_args.returncode != 0, "Sanitizer accepted more than one positional argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
