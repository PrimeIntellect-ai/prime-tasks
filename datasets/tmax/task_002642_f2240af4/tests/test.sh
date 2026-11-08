#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/home/user/kg_filter"
SOURCE_PATH = "/home/user/kg_filter.cpp"
CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
FINAL_REPORT_PATH = "/home/user/final_report.json"


def run_filter(binary, path):
    try:
        return subprocess.run([binary, path], capture_output=True, timeout=5).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out on {path}")


def test_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF binary"


def test_cpp_source_exists_and_builds():
    assert os.path.isfile(SOURCE_PATH), f"C++ source not found at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, f"C++ source at {SOURCE_PATH} is empty"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", "/tmp/kg_filter_from_source"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, "Submitted C++ source does not compile:\n" + result.stderr


def test_adversarial_corpus_filter():
    # Preserve the original visible-corpus assertions.
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR)
                  if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    evil_bypassed = []
    for fpath in evil_files:
        if run_filter(BINARY_PATH, fpath) != 1:
            evil_bypassed.append(os.path.basename(fpath))

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR)
                   if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    clean_rejected = []
    for fpath in clean_files:
        if run_filter(BINARY_PATH, fpath) != 0:
            clean_rejected.append(os.path.basename(fpath))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")
    assert not errors, "Adversarial corpus filtering failed:\n" + "\n".join(errors)


def make_holdout(directory):
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    cases = []

    def write_case(edges, evil):
        path = os.path.join(directory, secrets.token_hex(16) + ".dat")
        rng.shuffle(edges)
        with open(path, "w") as f:
            for u, v in edges:
                f.write(f"{u} {v}\n")
        cases.append((path, 1 if evil else 0))

    # Random DAGs: every edge follows a secret topological ordering.
    for _ in range(8):
        n = rng.randint(5, 35)
        nodes = rng.sample(range(-1000000, 1000001), n)
        edges = []
        for i in range(n):
            for j in range(i + 1, n):
                if rng.random() < 0.14:
                    edges.append((nodes[i], nodes[j]))
        if not edges:
            edges.append((nodes[0], nodes[-1]))
        write_case(edges, False)

    # Cyclic graphs with random labels, cycle lengths, tails, and disconnected edges.
    for _ in range(8):
        n = rng.randint(6, 35)
        nodes = rng.sample(range(-1000000, 1000001), n)
        cycle_len = rng.randint(2, min(9, n))
        edges = [(nodes[i], nodes[(i + 1) % cycle_len]) for i in range(cycle_len)]
        for i in range(cycle_len, n):
            if rng.random() < 0.8:
                edges.append((nodes[rng.randrange(i)], nodes[i]))
        write_case(edges, True)

    # Explicitly cover self-loops and disconnected acyclic components.
    x = rng.randint(2000001, 3000000)
    write_case([(x, x)], True)
    vals = rng.sample(range(3000001, 4000000), 8)
    write_case([(vals[0], vals[1]), (vals[2], vals[3]), (vals[4], vals[5]),
                (vals[5], vals[6]), (vals[4], vals[7])], False)
    return cases


def test_generated_holdout_against_binary_and_source():
    with tempfile.TemporaryDirectory(prefix="kg_holdout_") as directory:
        cases = make_holdout(directory)
        for binary in (BINARY_PATH, "/tmp/kg_filter_from_source"):
            for path, expected in cases:
                actual = run_filter(binary, path)
                assert actual == expected, (
                    f"{binary} returned {actual} for generated graph {os.path.basename(path)}; "
                    f"expected {expected}"
                )


def test_final_report():
    assert os.path.isfile(FINAL_REPORT_PATH), f"Final report not found at {FINAL_REPORT_PATH}"
    with open(FINAL_REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Final report at {FINAL_REPORT_PATH} is not valid JSON")

    for key in ("audio_transcript", "filtering_rule", "top_node_graph_001"):
        assert key in report, f"Key '{key}' missing in final report"

    transcript = report["audio_transcript"]
    rule = report["filtering_rule"]
    assert isinstance(transcript, str) and transcript.strip(), "audio_transcript must be a non-empty string"
    assert isinstance(rule, str) and rule.strip(), "filtering_rule must be a non-empty string"

    transcript_lower = transcript.lower()
    assert "directed" in transcript_lower and "cycle" in transcript_lower, \
        "audio_transcript must identify directed cycles"
    assert ("corrupt" in transcript_lower or "evil" in transcript_lower) and \
           ("acyclic" in transcript_lower or "dag" in transcript_lower), \
        "audio_transcript does not convey the clean/corrupted graph distinction"

    rule_lower = rule.lower()
    assert "cycle" in rule_lower and "directed" in rule_lower, \
        "filtering_rule must describe the directed-cycle rule"
    assert any(word in rule_lower for word in ("filter", "reject", "evil", "corrupt", "invalid")), \
        "filtering_rule must state how cyclic graphs are treated"
    sentences = [s for s in re.split(r"[.!?]+", rule.strip()) if s.strip()]
    assert len(sentences) == 1, "filtering_rule must be a one-sentence summary"

    assert str(report["top_node_graph_001"]) == "73", \
        f"Expected top_node_graph_001 to be '73', got {report['top_node_graph_001']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
