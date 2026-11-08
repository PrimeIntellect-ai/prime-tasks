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

GO_FILE = "/home/user/detector.go"


def test_video_analysis_frames():
    output_file = "/home/user/deadlock_frames.txt"
    assert os.path.exists(output_file), f"Output file missing: {output_file}"

    with open(output_file, "r") as f:
        content = f.read().strip()

    try:
        frames = [int(x.strip()) for x in content.split(",") if x.strip()]
    except ValueError:
        pytest.fail(f"File {output_file} contains non-integer values: {content}")

    expected_frames = [24, 78, 142, 205, 310]
    assert frames == expected_frames, f"Expected frames {expected_frames}, but got {frames}"


def test_go_detector_evil_corpus():
    assert os.path.exists(GO_FILE), f"Go detector missing at {GO_FILE}"
    assert os.path.isfile(GO_FILE), f"Go detector is not a regular file: {GO_FILE}"

    evil_dir = "/app/corpus/evil/"
    evil_files = [os.path.basename(f) for f in glob.glob(os.path.join(evil_dir, "*.json"))]
    assert evil_files, f"No JSON files found in {evil_dir}"

    result = subprocess.run(["go", "run", GO_FILE, evil_dir], capture_output=True, text=True, timeout=45)
    assert result.returncode == 0, f"Go program failed on evil corpus: {result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    missed_files = set(evil_files) - set(output_lines)
    assert not missed_files, f"{len(missed_files)} of {len(evil_files)} evil bypassed. Missed: {', '.join(missed_files)}"


def test_go_detector_clean_corpus():
    assert os.path.exists(GO_FILE), f"Go detector missing at {GO_FILE}"
    assert os.path.isfile(GO_FILE), f"Go detector is not a regular file: {GO_FILE}"

    clean_dir = "/app/corpus/clean/"
    clean_files = [os.path.basename(f) for f in glob.glob(os.path.join(clean_dir, "*.json"))]
    assert clean_files, f"No JSON files found in {clean_dir}"

    result = subprocess.run(["go", "run", GO_FILE, clean_dir], capture_output=True, text=True, timeout=45)
    assert result.returncode == 0, f"Go program failed on clean corpus: {result.stderr}"

    output_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    flagged_files = set(clean_files).intersection(set(output_lines))
    assert not flagged_files, f"{len(flagged_files)} of {len(clean_files)} clean modified. Flagged: {', '.join(flagged_files)}"


def has_cycle_from_json(document):
    transactions = document["transactions"]
    holders = {}
    for tx in transactions:
        for lock in tx["holds_locks_on"]:
            holders.setdefault(lock, []).append(tx["id"])

    graph = {tx["id"]: set() for tx in transactions}
    for tx in transactions:
        for lock in tx["waiting_for_locks_on"]:
            graph[tx["id"]].update(holders.get(lock, []))

    state = {}
    def visit(node):
        if state.get(node) == 1:
            return True
        if state.get(node) == 2:
            return False
        state[node] = 1
        for neighbor in graph.get(node, ()):
            if visit(neighbor):
                return True
        state[node] = 2
        return False

    return any(visit(node) for node in graph if state.get(node, 0) == 0)


def make_document(want_cycle, rng):
    n = rng.randint(3, 8)
    ids = ["tx_" + secrets.token_hex(5) for _ in range(n)]
    edges = set()

    if want_cycle:
        cycle_nodes = rng.sample(range(n), rng.randint(2, n))
        for i, source in enumerate(cycle_nodes):
            edges.add((source, cycle_nodes[(i + 1) % len(cycle_nodes)]))
        candidates = [(i, j) for i in range(n) for j in range(n) if i != j and (i, j) not in edges]
        rng.shuffle(candidates)
        edges.update(candidates[:rng.randint(0, min(len(candidates), n + 2))])
    else:
        topological_order = list(range(n))
        rng.shuffle(topological_order)
        candidates = []
        for left in range(n):
            for right in range(left + 1, n):
                candidates.append((topological_order[left], topological_order[right]))
        rng.shuffle(candidates)
        edges.update(candidates[:rng.randint(0, min(len(candidates), n + 3))])

    held = [[] for _ in range(n)]
    waiting = [[] for _ in range(n)]
    shuffled_edges = list(edges)
    rng.shuffle(shuffled_edges)
    for source, target in shuffled_edges:
        lock = "lock_" + secrets.token_hex(7)
        waiting[source].append(lock)
        held[target].append(lock)

    for i in range(n):
        held[i].append("private_" + secrets.token_hex(6))
        if rng.choice([True, False]):
            waiting[i].append("unheld_" + secrets.token_hex(6))
        rng.shuffle(held[i])
        rng.shuffle(waiting[i])

    transactions = [
        {
            "id": ids[i],
            "holds_locks_on": held[i],
            "waiting_for_locks_on": waiting[i],
        }
        for i in range(n)
    ]
    rng.shuffle(transactions)
    document = {"transactions": transactions}
    assert has_cycle_from_json(document) == want_cycle
    return document


def run_and_check(directory, expected):
    result = subprocess.run(
        ["go", "run", GO_FILE, directory],
        capture_output=True,
        text=True,
        timeout=45,
    )
    assert result.returncode == 0, f"Go program failed on generated corpus: {result.stderr}"
    actual = result.stdout.splitlines()
    assert actual == sorted(expected), (
        "Detector output must contain exactly the cyclic JSON filenames in alphabetical order. "
        f"Expected {sorted(expected)}, got {actual}"
    )


def test_go_detector_generated_content_and_argument_sensitive_corpora():
    assert os.path.isfile(GO_FILE), f"Go detector missing or not a regular file at {GO_FILE}"
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="wait_graph_a_") as first, tempfile.TemporaryDirectory(prefix="wait_graph_b_") as second:
        expected_first = []
        expected_second = []

        # Both directories use the same unpredictable filenames, but each file's
        # classification is reversed. Thus filenames or a fixed output list cannot pass.
        for index in range(20):
            filename = "case_" + secrets.token_hex(8) + ".json"
            first_is_cycle = (index % 2 == 0)
            first_doc = make_document(first_is_cycle, rng)
            second_doc = make_document(not first_is_cycle, rng)

            with open(os.path.join(first, filename), "w") as f:
                json.dump(first_doc, f)
            with open(os.path.join(second, filename), "w") as f:
                json.dump(second_doc, f)

            if has_cycle_from_json(first_doc):
                expected_first.append(filename)
            if has_cycle_from_json(second_doc):
                expected_second.append(filename)

        with open(os.path.join(first, "ignore_" + secrets.token_hex(4) + ".txt"), "w") as f:
            f.write("not JSON")
        with open(os.path.join(second, "ignore_" + secrets.token_hex(4) + ".txt"), "w") as f:
            f.write("not JSON")

        run_and_check(first, expected_first)
        run_and_check(second, expected_second)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
