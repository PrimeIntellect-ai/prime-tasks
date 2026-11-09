#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/detect_papermill.sh"
LEGACY_PATH = "/app/legacy_detector"


def run_submission(path):
    try:
        return subprocess.run(
            [SCRIPT_PATH, str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Detector timed out on {path}")


def expected_result(edges):
    edge_set = set(edges)
    for u, v in edge_set:
        for x, w in edge_set:
            if x == v and (w, u) in edge_set:
                return 1
    return 0


def write_graph(directory, edges, rng):
    path = directory / (secrets.token_hex(12) + ".dat")
    lines = [f"{u} {v}\n" for u, v in edges]
    rng.shuffle(lines)
    path.write_text("".join(lines), encoding="ascii")
    return path


def test_detect_papermill():
    # Preserve the original artifact and fixed-corpus assertions.
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."

    data = Path(SCRIPT_PATH).read_bytes()
    assert data != Path(LEGACY_PATH).read_bytes(), "Submission is the legacy executable."
    assert b"\x00" not in data, "Submission must be a Bash text script."
    first_line = data.splitlines()[0].decode("utf-8", "strict") if data.splitlines() else ""
    assert first_line.startswith("#!") and "bash" in first_line, "Submission must have a Bash shebang."

    evil_corpus_dir = "/verify/corpus/evil"
    clean_corpus_dir = "/verify/corpus/clean"
    evil_files = [os.path.join(evil_corpus_dir, f) for f in os.listdir(evil_corpus_dir)
                  if os.path.isfile(os.path.join(evil_corpus_dir, f))]
    clean_files = [os.path.join(clean_corpus_dir, f) for f in os.listdir(clean_corpus_dir)
                   if os.path.isfile(os.path.join(clean_corpus_dir, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = [os.path.basename(p) for p in evil_files if run_submission(p) != 1]
    clean_modified = [os.path.basename(p) for p in clean_files if run_submission(p) != 0]
    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not evil_bypassed and not clean_modified, " | ".join(errors)

    # Generate unpredictable neutral-path graphs and derive their answers from
    # the directed closed-walk-of-length-three condition implemented by the oracle.
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    with tempfile.TemporaryDirectory(prefix="citation_checks_") as temp:
        directory = Path(temp)
        cases = [
            [],
            [(1, 2)],
            [(1, 2), (2, 1)],
            [(1, 2), (2, 3), (3, 4), (4, 1)],
            [(7, 7)],
            [(10, 20), (20, 30), (30, 10)],
            [(5, 6), (5, 6), (6, 7), (7, 5)],
        ]

        # Guaranteed acyclic graphs.
        for _ in range(35):
            count = rng.randint(4, 24)
            nodes = rng.sample(range(-1000000, 1000001), count)
            order = nodes[:]
            rng.shuffle(order)
            edges = []
            for i in range(count):
                for j in range(i + 1, count):
                    if rng.random() < 0.12:
                        edges.append((order[i], order[j]))
            cases.append(edges)

        # Graphs with a hidden three-edge directed cycle plus unrelated noise.
        for _ in range(35):
            nodes = rng.sample(range(-2000000000, 2000000001), rng.randint(8, 25))
            a, b, c = nodes[:3]
            edges = [(a, b), (b, c), (c, a)]
            rest = nodes[3:]
            for i in range(len(rest)):
                for j in range(i + 1, len(rest)):
                    if rng.random() < 0.1:
                        edges.append((rest[i], rest[j]))
            cases.append(edges)

        # Unconstrained random graphs exercise both outcomes and repeated nodes.
        for _ in range(60):
            nodes = rng.sample(range(-500000, 500001), rng.randint(3, 14))
            edges = []
            for _ in range(rng.randint(0, 35)):
                edges.append((rng.choice(nodes), rng.choice(nodes)))
            cases.append(edges)

        for edges in cases:
            path = write_graph(directory, edges, rng)
            expected = expected_result(edges)

            # Cross-check the independently derived answer against the legacy oracle.
            oracle = subprocess.run(
                [LEGACY_PATH],
                input=path.read_bytes(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert oracle.returncode == expected, "Generated-case expectation disagrees with oracle."

            actual = run_submission(path)
            assert actual == expected, (
                f"Incorrect exit code for generated graph: expected {expected}, got {actual}; "
                f"edges={edges!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
