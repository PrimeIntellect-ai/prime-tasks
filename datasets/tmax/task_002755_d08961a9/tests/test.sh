#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/audit.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def test_script_exists_and_executable():
    """Ensure the audit script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def run_script(file_path):
    """Run the submitted script and return its stripped stdout."""
    result = subprocess.run(
        [SCRIPT_PATH, file_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    return result.stdout.strip()


def test_adversarial_corpus():
    """Preserve the original checks against the supplied corpora."""
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_CORPUS_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_CORPUS_DIR}"

    clean_failures = []
    for clean_file in clean_files:
        output = run_script(clean_file)
        if output != "CLEAN":
            clean_failures.append(f"{os.path.basename(clean_file)} (got {output!r})")

    evil_failures = []
    for evil_file in evil_files:
        output = run_script(evil_file)
        if output != "EVIL":
            evil_failures.append(f"{os.path.basename(evil_file)} (got {output!r})")

    error_messages = []
    if evil_failures:
        error_messages.append(
            f"{len(evil_failures)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_failures)
        )
    if clean_failures:
        error_messages.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: "
            + ", ".join(clean_failures)
        )
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def has_admin_cycle(events):
    """Independently derive the policy result from the generated transaction log."""
    graph = {}
    nodes = set()
    for event in events:
        if event.get("action") == "GRANT" and event.get("role") == "ADMIN":
            source = event.get("source")
            target = event.get("target")
            nodes.add(source)
            nodes.add(target)
            graph.setdefault(source, []).append(target)

    state = {}

    def visit(node):
        if state.get(node) == 1:
            return True
        if state.get(node) == 2:
            return False
        state[node] = 1
        for target in graph.get(node, []):
            if visit(target):
                return True
        state[node] = 2
        return False

    return any(visit(node) for node in nodes if state.get(node, 0) == 0)


def grant(source, target, role):
    return {"action": "GRANT", "source": source, "target": target, "role": role}


def generated_cases(rng):
    cases = [
        [],
        [grant("A", "B", "USER"), grant("B", "A", "USER")],
        [grant("SELF", "SELF", "ADMIN")],
        [grant("A", "B", "ADMIN"), grant("B", "A", "USER")],
    ]

    # Construct acyclic ADMIN graphs containing distracting USER cycles.
    for case_number in range(12):
        nodes = [f"N{case_number}_{i}_{secrets.token_hex(2)}" for i in range(rng.randint(4, 9))]
        order = nodes[:]
        rng.shuffle(order)
        events = []
        for i in range(len(order)):
            for j in range(i + 1, len(order)):
                if rng.random() < 0.32:
                    events.append(grant(order[i], order[j], "ADMIN"))
        events.extend(grant(nodes[i], nodes[(i + 1) % len(nodes)], "USER") for i in range(len(nodes)))
        rng.shuffle(events)
        cases.append(events)

    # Construct ADMIN cycles with unrelated edges and USER transactions mixed in.
    for case_number in range(12):
        nodes = [f"M{case_number}_{i}_{secrets.token_hex(2)}" for i in range(rng.randint(4, 9))]
        cycle_size = rng.randint(2, len(nodes))
        cycle_nodes = rng.sample(nodes, cycle_size)
        events = [
            grant(cycle_nodes[i], cycle_nodes[(i + 1) % cycle_size], "ADMIN")
            for i in range(cycle_size)
        ]
        for _ in range(rng.randint(2, 10)):
            source, target = rng.sample(nodes, 2)
            events.append(grant(source, target, rng.choice(["ADMIN", "USER"])))
        rng.shuffle(events)
        cases.append(events)

    # Additional arbitrary graphs whose answers are computed, not assigned by construction.
    for case_number in range(20):
        nodes = [f"R{case_number}_{i}_{secrets.token_hex(2)}" for i in range(rng.randint(3, 9))]
        events = []
        for source in nodes:
            for target in nodes:
                if rng.random() < 0.14:
                    events.append(grant(source, target, rng.choice(["ADMIN", "ADMIN", "USER"])))
        rng.shuffle(events)
        cases.append(events)

    rng.shuffle(cases)
    return cases


def test_runtime_generated_logs():
    """Exercise unseen logs in neutral paths and derive each expected label by cycle detection."""
    rng = random.SystemRandom()
    cases = generated_cases(rng)
    expected_labels = {"CLEAN", "EVIL"}
    observed_labels = set()

    with tempfile.TemporaryDirectory(prefix="audit_inputs_") as directory:
        for events in cases:
            expected = "EVIL" if has_admin_cycle(events) else "CLEAN"
            observed_labels.add(expected)
            path = os.path.join(directory, secrets.token_hex(16) + ".json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(events, handle, indent=rng.choice([None, 2, 4]))
                handle.write("\n")
            output = run_script(path)
            assert output == expected, f"Generated log expected {expected}, got {output!r}"

    assert observed_labels == expected_labels, "Generated suite must exercise both policy outcomes"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
