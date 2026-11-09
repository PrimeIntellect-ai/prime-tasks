#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
from collections import defaultdict, deque

AGENT_SCRIPT = "/home/user/audit_query.sh"
ORACLE_BIN = "/app/access_oracle"
GRAPH_FILE = "/app/access_graph.tsv"


def load_graph():
    adjacency = defaultdict(list)
    nodes = set()
    edges = []
    with open(GRAPH_FILE, "r") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) == 2:
                src, dst = parts
                adjacency[src].append(dst)
                nodes.update((src, dst))
                edges.append((src, dst))
    return adjacency, nodes, edges


def expected_access(adjacency, source, target):
    queue = deque(adjacency.get(source, ()))
    visited = set()
    while queue:
        current = queue.popleft()
        if current == target:
            return "GRANTED\n"
        if current in visited:
            continue
        visited.add(current)
        queue.extend(adjacency.get(current, ()))
    return "DENIED\n"


def restore_oracle(payload, mode):
    try:
        os.unlink(ORACLE_BIN)
    except FileNotFoundError:
        pass
    with open(ORACLE_BIN, "wb") as f:
        f.write(payload)
    os.chmod(ORACLE_BIN, stat.S_IMODE(mode))


def test_audit_query_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary {ORACLE_BIN} is missing."
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary {ORACLE_BIN} is not executable."
    assert os.path.isfile(GRAPH_FILE), f"Graph file {GRAPH_FILE} is missing."

    sources = set()
    targets = set()
    with open(GRAPH_FILE, "r") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) == 2:
                sources.add(parts[0])
                targets.add(parts[1])

    assert sources, "No source nodes found in the graph."
    assert targets, "No target nodes found in the graph."

    sources = sorted(sources)
    targets = sorted(targets)
    with open(ORACLE_BIN, "rb") as f:
        oracle_payload = f.read()
    oracle_mode = os.stat(ORACLE_BIN).st_mode

    random.seed(42)
    try:
        for _ in range(100):
            src = random.choice(sources)
            tgt = random.choice(targets)

            oracle_proc = subprocess.run(
                [ORACLE_BIN, src, tgt], capture_output=True, text=True
            )
            oracle_out = oracle_proc.stdout.strip()

            # The oracle must not be available while the submitted artifact runs.
            os.unlink(ORACLE_BIN)
            agent_proc = subprocess.run(
                ["bash", AGENT_SCRIPT, src, tgt], capture_output=True, text=True
            )
            restore_oracle(oracle_payload, oracle_mode)
            agent_out = agent_proc.stdout.strip()

            assert agent_proc.returncode == 0, (
                f"Agent script failed on inputs {src} {tgt} with stderr: "
                f"{agent_proc.stderr}"
            )
            assert oracle_out == agent_out, (
                f"Output mismatch for inputs '{src}' and '{tgt}'.\n"
                f"Oracle output: '{oracle_out}'\n"
                f"Agent output: '{agent_out}'"
            )
    finally:
        restore_oracle(oracle_payload, oracle_mode)


def test_derived_reachability_without_oracle():
    adjacency, nodes, edges = load_graph()
    assert nodes, "No nodes found in the graph."

    with open(ORACLE_BIN, "rb") as f:
        oracle_payload = f.read()
    oracle_mode = os.stat(ORACLE_BIN).st_mode

    ordered_nodes = sorted(nodes)
    cases = set(edges)
    cases.update((node, node) for node in ordered_nodes)
    cases.update({("UNKNOWN_SOURCE", ordered_nodes[0]),
                  (ordered_nodes[0], "UNKNOWN_TARGET"),
                  ("UNKNOWN_SOURCE", "UNKNOWN_TARGET")})

    rng = random.Random(9173)
    for _ in range(300):
        cases.add((rng.choice(ordered_nodes), rng.choice(ordered_nodes)))

    os.unlink(ORACLE_BIN)
    try:
        for src, tgt in sorted(cases):
            expected = expected_access(adjacency, src, tgt)
            proc = subprocess.run(
                ["bash", AGENT_SCRIPT, src, tgt], capture_output=True, text=True
            )
            assert proc.returncode == 0, (
                f"Agent script failed on inputs {src} {tgt} with stderr: {proc.stderr}"
            )
            assert proc.stdout == expected, (
                f"Output mismatch for inputs '{src}' and '{tgt}'.\n"
                f"Expected exactly: {expected!r}\n"
                f"Agent output: {proc.stdout!r}"
            )
    finally:
        restore_oracle(oracle_payload, oracle_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
