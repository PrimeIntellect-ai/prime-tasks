#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/validate_schema.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
TARGET = "node_87"


def run_validator(filepath):
    return subprocess.run(
        [SCRIPT_PATH, filepath],
        capture_output=True,
        timeout=5,
    ).returncode


def test_script_exists_and_executable():
    """Verify the validation script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable"


def test_adversarial_corpus_validation():
    """Retain validation against the shipped clean and evil corpora."""
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}"

    clean_failures = []
    for filepath in clean_files:
        if run_validator(filepath) != 0:
            clean_failures.append(os.path.basename(filepath))

    evil_failures = []
    for filepath in evil_files:
        if run_validator(filepath) == 0:
            evil_failures.append(os.path.basename(filepath))

    error_messages = []
    if clean_failures:
        error_messages.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: "
            + ", ".join(clean_failures)
        )
    if evil_failures:
        error_messages.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_failures)
        )

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def schema_is_valid(schema):
    nodes = schema["nodes"]
    if TARGET not in nodes:
        return False

    adjacency = {node: [] for node in nodes}
    for edge in schema["edges"]:
        adjacency[edge["from"]].append(edge["to"])

    state = {node: 0 for node in nodes}

    def visit(node):
        if state[node] == 1:
            return False
        if state[node] == 2:
            return True
        state[node] = 1
        for neighbor in adjacency[node]:
            if not visit(neighbor):
                return False
        state[node] = 2
        return True

    return all(visit(node) for node in nodes)


def test_generated_hidden_graphs():
    """Exercise the validator on fresh paths and independently classified graphs."""
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="schema-check-") as directory:
        cases = []
        for case_number in range(32):
            count = rng.randint(3, 11)
            nodes = [f"srv_{uuid.uuid4().hex}" for _ in range(count)]
            mode = case_number % 4

            if mode in (0, 2):
                nodes[rng.randrange(count)] = TARGET

            ordering = nodes[:]
            rng.shuffle(ordering)
            edges = []
            for left in range(count):
                for right in range(left + 1, count):
                    if rng.random() < 0.22:
                        edges.append({"from": ordering[left], "to": ordering[right]})

            if mode in (2, 3):
                if case_number % 8 < 4:
                    cycle_node = rng.choice(nodes)
                    edges.append({"from": cycle_node, "to": cycle_node})
                else:
                    first, second = rng.sample(nodes, 2)
                    edges.extend([
                        {"from": first, "to": second},
                        {"from": second, "to": first},
                    ])

            schema = {"nodes": nodes, "edges": edges}
            filepath = os.path.join(directory, uuid.uuid4().hex + ".json")
            with open(filepath, "w", encoding="utf-8") as handle:
                json.dump(schema, handle)
            cases.append((filepath, schema_is_valid(schema)))

        rng.shuffle(cases)
        failures = []
        for filepath, expected_valid in cases:
            actual_valid = run_validator(filepath) == 0
            if actual_valid != expected_valid:
                failures.append(
                    f"{os.path.basename(filepath)} expected valid={expected_valid}, got valid={actual_valid}"
                )

        assert not failures, "Generated graph failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
