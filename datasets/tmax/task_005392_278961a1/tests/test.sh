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

SCRIPT_PATH = "/home/user/query_filter.py"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
HIERARCHY_PATH = "/app/kg_hierarchy.json"


def run_script(directory):
    result = subprocess.run(["python3", SCRIPT_PATH, directory], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    lines = result.stdout.strip().split('\n')

    parsed_results = {}
    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts = line.rsplit(',', 1)
        if len(parts) == 2:
            filename = os.path.basename(parts[0].strip())
            status = parts[1].strip()
            parsed_results[filename] = status

    return parsed_results


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path is not a file: {SCRIPT_PATH}"


def test_clean_corpus_accepted():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, f"No JSON files found in {CLEAN_DIR}"

    results = run_script(CLEAN_DIR)

    rejected_files = []
    missing_files = []

    for f in clean_files:
        if f not in results:
            missing_files.append(f)
        elif results[f] != "ACCEPT":
            rejected_files.append(f)

    error_msg = []
    if rejected_files:
        error_msg.append(f"{len(rejected_files)} of {len(clean_files)} clean queries modified/rejected: {', '.join(rejected_files)}")
    if missing_files:
        error_msg.append(f"{len(missing_files)} clean queries missing from output: {', '.join(missing_files)}")

    assert not error_msg, " | ".join(error_msg)


def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, f"No JSON files found in {EVIL_DIR}"

    results = run_script(EVIL_DIR)

    accepted_files = []
    missing_files = []

    for f in evil_files:
        if f not in results:
            missing_files.append(f)
        elif results[f] != "REJECT":
            accepted_files.append(f)

    error_msg = []
    if accepted_files:
        error_msg.append(f"{len(accepted_files)} of {len(evil_files)} evil queries bypassed/accepted: {', '.join(accepted_files)}")
    if missing_files:
        error_msg.append(f"{len(missing_files)} evil queries missing from output: {', '.join(missing_files)}")

    assert not error_msg, " | ".join(error_msg)


def descendants(hierarchy, root):
    found = set()
    pending = [root]
    while pending:
        node = pending.pop()
        if node in found:
            continue
        found.add(node)
        pending.extend(hierarchy.get(node, []))
    return found


def test_randomized_mixed_queries_and_recursive_hierarchy():
    with open(HIERARCHY_PATH, "r", encoding="utf-8") as f:
        original_text = f.read()
    hierarchy = json.loads(original_text)

    # Add an unpredictable three-level branch so implementations must actually
    # read and recursively traverse the hierarchy rather than hard-code names.
    dynamic_nodes = ["node_" + uuid.uuid4().hex for _ in range(3)]
    hierarchy.setdefault("Chimera", []).append(dynamic_nodes[0])
    hierarchy[dynamic_nodes[0]] = [dynamic_nodes[1]]
    hierarchy[dynamic_nodes[1]] = [dynamic_nodes[2]]

    try:
        with open(HIERARCHY_PATH, "w", encoding="utf-8") as f:
            json.dump(hierarchy, f)

        restricted = descendants(hierarchy, "Chimera")
        safe_nodes = ["Titan", "Apollo", "Atlas", "Sun"] + [
            "safe_" + uuid.uuid4().hex for _ in range(8)
        ]
        bad_nodes = list(restricted)
        random.SystemRandom().shuffle(bad_nodes)

        cases = []
        # Exercise every restricted node, alternating between start-node and
        # path positions, including dynamically generated deep descendants.
        for index, node in enumerate(bad_nodes):
            if index % 2 == 0:
                query = {
                    "start_node": node,
                    "path": [{"target_node": random.choice(safe_nodes)}],
                }
            else:
                query = {
                    "start_node": random.choice(safe_nodes),
                    "path": [
                        {"target_node": random.choice(safe_nodes)},
                        {"target_node": node},
                        {"target_node": random.choice(safe_nodes)},
                    ],
                }
            cases.append((query, "REJECT"))

        for _ in range(10):
            query = {
                "start_node": random.choice(safe_nodes),
                "path": [
                    {"target_node": random.choice(safe_nodes)}
                    for _ in range(random.randint(0, 4))
                ],
            }
            cases.append((query, "ACCEPT"))

        random.SystemRandom().shuffle(cases)
        with tempfile.TemporaryDirectory(prefix="query_batch_") as directory:
            expected = {}
            for query, status in cases:
                filename = uuid.uuid4().hex + ".json"
                with open(os.path.join(directory, filename), "w", encoding="utf-8") as f:
                    json.dump(query, f)
                expected[filename] = status

            with open(os.path.join(directory, "ignore.txt"), "w", encoding="utf-8") as f:
                f.write("not a query")

            result = subprocess.run(
                ["python3", SCRIPT_PATH, directory],
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0, (
                f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
            )

            lines = result.stdout.splitlines()
            assert len(lines) == len(expected), (
                f"Expected exactly one output line per JSON file; got {len(lines)} "
                f"lines for {len(expected)} files: {result.stdout!r}"
            )

            actual = {}
            for line in lines:
                parts = line.rsplit(',', 1)
                assert len(parts) == 2, f"Invalid output line: {line!r}"
                filename, status = parts
                assert filename in expected, f"Unexpected filename in output: {filename!r}"
                assert filename not in actual, f"Duplicate output for {filename!r}"
                assert status in {"ACCEPT", "REJECT"}, f"Invalid status in line: {line!r}"
                actual[filename] = status

            assert actual == expected, f"Incorrect classifications: expected {expected}, got {actual}"
    finally:
        with open(HIERARCHY_PATH, "w", encoding="utf-8") as f:
            f.write(original_text)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
