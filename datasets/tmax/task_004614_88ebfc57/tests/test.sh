#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import subprocess
import tempfile
import uuid
import pytest

EXECUTABLE = "/home/user/audit_checker"
SOURCE = "/home/user/audit_checker.cpp"
MAKEFILE = "/home/user/Makefile"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"


def test_submission_builds_and_uses_required_sqlite_features():
    assert os.path.isfile(SOURCE), f"Source not found at {SOURCE}"
    assert os.path.isfile(MAKEFILE), f"Makefile not found at {MAKEFILE}"

    source = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    lower = source.lower()
    assert "sqlite3_open" in lower and ":memory:" in lower, "Source must open an in-memory SQLite database"
    assert "create table" in lower, "Source must create a SQLite table"
    assert "sqlite3_prepare" in lower, "Source must use prepared SQLite statements"
    assert "sqlite3_bind_" in lower and "?" in source, "Source must insert data using parameterized queries"
    assert re.search(r"\bwith\b", lower) and re.search(r"\brecursive\b", lower), "Source must use a recursive CTE"

    result = subprocess.run(
        ["make", "-B", "-C", "/home/user"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Makefile failed to rebuild audit_checker:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_checker must be a compiled native executable"


def test_adversarial_corpus_evaluation():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))

    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    for filepath in evil_files:
        try:
            result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "EVIL":
                evil_bypassed.append((os.path.basename(filepath), output))
        except Exception as e:
            evil_bypassed.append((os.path.basename(filepath), str(e)))

    clean_modified = []
    for filepath in clean_files:
        try:
            result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_modified.append((os.path.basename(filepath), output))
        except Exception as e:
            clean_modified.append((os.path.basename(filepath), str(e)))

    error_messages = []
    if evil_bypassed:
        basenames = [f[0] for f in evil_bypassed]
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(basenames)}")

    if clean_modified:
        basenames = [f[0] for f in clean_modified]
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(basenames)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def has_cycle(edges):
    graph = {}
    nodes = set()
    for src, dst in edges:
        graph.setdefault(src, []).append(dst)
        nodes.add(src)
        nodes.add(dst)

    state = {}
    def visit(node):
        if state.get(node) == 1:
            return True
        if state.get(node) == 2:
            return False
        state[node] = 1
        for nxt in graph.get(node, []):
            if visit(nxt):
                return True
        state[node] = 2
        return False

    return any(visit(node) for node in nodes if state.get(node, 0) == 0)


def test_generated_graphs_at_neutral_paths():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    cases = []

    # Explicitly exercise self-cycles, disconnected cycles, and ordinary DAGs.
    cases.append([("q1", "q1")])
    cases.append([("q1", "q2"), ("q3", "q4"), ("q4", "q5"), ("q5", "q3")])
    cases.append([("q1", "q2"), ("q1", "q3"), ("q2", "q4"), ("q3", "q4")])
    cases.append([("q1", "q2"), ("q3", "q4")])

    for cyclic in (False, True):
        for _ in range(8):
            count = rng.randint(4, 11)
            nodes = ["acct_" + uuid.uuid4().hex[:10] for _ in range(count)]
            order = nodes[:]
            rng.shuffle(order)
            edges = []

            if cyclic:
                ring_size = rng.randint(2, count)
                ring = order[:ring_size]
                edges.extend((ring[i], ring[(i + 1) % ring_size]) for i in range(ring_size))
                for _ in range(rng.randint(0, count)):
                    a, b = rng.sample(nodes, 2)
                    edges.append((a, b))
            else:
                # Edges only move forward in a random topological order.
                edges.extend((order[i], order[i + 1]) for i in range(count - 1))
                for i in range(count):
                    for j in range(i + 2, count):
                        if rng.random() < 0.22:
                            edges.append((order[i], order[j]))

            rng.shuffle(edges)
            cases.append(edges)

    neutral_dir = tempfile.mkdtemp(prefix="audit_cases_", dir="/tmp")
    for index, edges in enumerate(cases):
        transactions = [
            {
                "tx_id": index * 1000 + edge_index + 1,
                "src": src,
                "dst": dst,
                "amount": round(rng.uniform(1.0, 10000.0), 2),
            }
            for edge_index, (src, dst) in enumerate(edges)
        ]
        rng.shuffle(transactions)
        filepath = os.path.join(neutral_dir, f"case_{uuid.uuid4().hex}.json")
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(transactions, f)
            f.write("\n")

        expected = "EVIL" if has_cycle(edges) else "CLEAN"
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"Case {index} exited with {result.returncode}: {result.stderr}"
        assert result.stdout == expected + "\n", (
            f"Case {index} expected {expected}, got stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
