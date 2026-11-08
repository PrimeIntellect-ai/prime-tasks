#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile
from collections import deque

import pytest

EXECUTABLE = "/home/user/graph_filter"
SOURCE = "/home/user/graph_filter.cpp"
CLEAN_DIR = "/app/data/clean"
EVIL_DIR = "/app/data/evil"

ALLOWED = {
    ("GENE", "TRANSCRIPT"),
    ("TRANSCRIPT", "PROTEIN"),
    ("PROTEIN", "METABOLITE"),
    ("METABOLITE", "PATHWAY"),
    ("PROTEIN", "COMPLEX"),
    ("COMPLEX", "PATHWAY"),
}
MAX_PATH_LENGTH = 4
ALL_TYPES = ["GENE", "TRANSCRIPT", "PROTEIN", "METABOLITE", "COMPLEX", "PATHWAY"]


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "graph_filter is not a compiled ELF executable"


def test_source_exists():
    assert os.path.isfile(SOURCE), f"Source not found at {SOURCE}"


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.txt"))
    assert len(clean_files) > 0, f"No files found in clean corpus directory {CLEAN_DIR}"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 0 or output != "ACCEPT":
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.txt"))
    assert len(evil_files) > 0, f"No files found in evil corpus directory {EVIL_DIR}"

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([EXECUTABLE, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if result.returncode != 1 or output != "REJECT":
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_files)}")


def oracle(text):
    edges = []
    for line in text.splitlines():
        fields = line.split()
        if len(fields) != 4:
            return False
        st, sid, tt, tid = fields
        if (st, tt) not in ALLOWED:
            return False
        edges.append(((st, sid), (tt, tid)))

    adjacency = {}
    genes = set()
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)
        if source[0] == "GENE":
            genes.add(source)
        if target[0] == "GENE":
            genes.add(target)

    queue = deque((node, 0) for node in genes)
    best = {node: 0 for node in genes}
    while queue:
        node, distance = queue.popleft()
        if node[0] == "PATHWAY" and distance <= MAX_PATH_LENGTH:
            return True
        if distance == MAX_PATH_LENGTH:
            continue
        for target in adjacency.get(node, []):
            next_distance = distance + 1
            if next_distance < best.get(target, MAX_PATH_LENGTH + 1):
                best[target] = next_distance
                queue.append((target, next_distance))
    return False


def edge(st, sid, tt, tid):
    return f"{st} {sid} {tt} {tid}"


def valid_graph(rng, token):
    middle = rng.choice([("METABOLITE", "M"), ("COMPLEX", "C")])
    lines = [
        edge("GENE", "G" + token, "TRANSCRIPT", "T" + token),
        edge("TRANSCRIPT", "T" + token, "PROTEIN", "P" + token),
        edge("PROTEIN", "P" + token, middle[0], middle[1] + token),
        edge(middle[0], middle[1] + token, "PATHWAY", "W" + token),
    ]
    # Add allowed disconnected components and vary edge order.
    if rng.randrange(2):
        lines.append(edge("GENE", "DG" + token, "TRANSCRIPT", "DT" + token))
    if rng.randrange(2):
        lines.append(edge("PROTEIN", "DP" + token, "COMPLEX", "DC" + token))
    rng.shuffle(lines)
    return "\n".join(lines) + "\n"


def make_cases():
    rng = random.SystemRandom()
    cases = []

    for _ in range(30):
        token = secrets.token_hex(8)
        cases.append(valid_graph(rng, token))

    # A valid path plus one forbidden transition must be rejected.
    disallowed = [(a, b) for a in ALL_TYPES for b in ALL_TYPES if (a, b) not in ALLOWED]
    for _ in range(25):
        token = secrets.token_hex(8)
        text = valid_graph(rng, token)
        st, tt = rng.choice(disallowed)
        text += edge(st, "BAD_S" + token, tt, "BAD_T" + token) + "\n"
        cases.append(text)

    # Every edge is schema-valid, but identifiers prevent a connected path.
    for _ in range(25):
        token = secrets.token_hex(8)
        lines = [
            edge("GENE", "G" + token, "TRANSCRIPT", "T1" + token),
            edge("TRANSCRIPT", "T2" + token, "PROTEIN", "P1" + token),
            edge("PROTEIN", "P2" + token, "METABOLITE", "M1" + token),
            edge("METABOLITE", "M2" + token, "PATHWAY", "W" + token),
            edge("PROTEIN", "P3" + token, "COMPLEX", "C1" + token),
            edge("COMPLEX", "C2" + token, "PATHWAY", "W2" + token),
        ]
        rng.shuffle(lines)
        cases.append("\n".join(lines) + "\n")

    # Malformed records remain invalid even when a valid path is also present.
    malformed = [
        "GENE only_two_fields",
        "GENE A TRANSCRIPT B EXTRA",
        "this is not an edge",
        "GENE",
    ]
    for _ in range(12):
        token = secrets.token_hex(8)
        cases.append(valid_graph(rng, token) + rng.choice(malformed) + "\n")

    # Independently generated mixed graphs, classified only by the oracle below.
    for _ in range(50):
        token = secrets.token_hex(5)
        node_ids = {t: [f"{t[0]}{token}_{i}" for i in range(4)] for t in ALL_TYPES}
        lines = []
        for _ in range(rng.randint(1, 12)):
            st = rng.choice(ALL_TYPES)
            tt = rng.choice(ALL_TYPES)
            lines.append(edge(st, rng.choice(node_ids[st]), tt, rng.choice(node_ids[tt])))
        rng.shuffle(lines)
        cases.append("\n".join(lines) + "\n")

    rng.shuffle(cases)
    assert any(oracle(text) for text in cases)
    assert any(not oracle(text) for text in cases)
    return cases


def run_and_check(binary, filepath, expected):
    try:
        result = subprocess.run([binary, filepath], capture_output=True, timeout=3)
    except subprocess.TimeoutExpired:
        pytest.fail(f"{binary} timed out on a generated graph")
    wanted_output = b"ACCEPT\n" if expected else b"REJECT\n"
    wanted_code = 0 if expected else 1
    assert result.returncode == wanted_code, (
        f"{binary} returned {result.returncode}, expected {wanted_code}"
    )
    assert result.stdout == wanted_output, (
        f"{binary} printed {result.stdout!r}, expected {wanted_output!r}"
    )


def test_generated_graph_semantics():
    with tempfile.TemporaryDirectory(prefix="graph_checks_") as directory:
        rebuilt = os.path.join(directory, "rebuilt_filter")
        compile_result = subprocess.run(
            ["g++", "-O3", "-std=c++17", SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"Submitted source does not compile: {compile_result.stderr}"

        cases = make_cases()
        for index, text in enumerate(cases):
            # Neutral randomized names place accepted and rejected cases together.
            filepath = os.path.join(directory, f"case_{index}_{secrets.token_hex(8)}.dat")
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(text)
            expected = oracle(text)
            run_and_check(EXECUTABLE, filepath, expected)
            run_and_check(rebuilt, filepath, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
