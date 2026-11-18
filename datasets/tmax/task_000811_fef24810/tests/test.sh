#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/detect_deadlocks.sh"
SCHEMA = re.compile(r"^TXN-[0-9]{4},TXN-[0-9]{4}$")


def run_script(filepath):
    """Run the submitted Bash script and return stripped stdout and exit code."""
    try:
        result = subprocess.run(
            ["bash", SCRIPT_PATH, filepath],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", -1
    except Exception as exc:
        return str(exc), -1


def expected_result(filepath):
    """Independently validate the schema and classify the wait-for graph."""
    with open(filepath, "r", encoding="utf-8", newline="") as handle:
        data = handle.read()

    lines = data.splitlines()
    if any(SCHEMA.fullmatch(line) is None for line in lines):
        return "INVALID_SCHEMA", 1

    graph = {}
    nodes = set()
    for line in lines:
        waiting, holding = line.split(",")
        graph.setdefault(waiting, []).append(holding)
        nodes.add(waiting)
        nodes.add(holding)

    color = {}

    def visit(node):
        color[node] = 1
        for neighbor in graph.get(node, []):
            if color.get(neighbor, 0) == 1:
                return True
            if color.get(neighbor, 0) == 0 and visit(neighbor):
                return True
        color[node] = 2
        return False

    cyclic = any(color.get(node, 0) == 0 and visit(node) for node in nodes)
    return ("DEADLOCK", 0) if cyclic else ("VALID", 0)


def assert_classification(filepath):
    expected_out, expected_code = expected_result(filepath)
    out, code = run_script(filepath)
    assert (out, code) == (expected_out, expected_code), (
        f"Wrong result for {os.path.basename(filepath)}: "
        f"expected {(expected_out, expected_code)}, got {(out, code)}"
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK) or os.access(SCRIPT_PATH, os.R_OK), (
        f"Script not executable/readable: {SCRIPT_PATH}"
    )
    syntax = subprocess.run(["bash", "-n", SCRIPT_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid Bash syntax: {syntax.stderr}"


def test_evil_corpus():
    """Classify every supplied evil-corpus graph from its actual contents."""
    csv_files = glob.glob("/app/corpus/evil/*.csv")
    assert csv_files, "No files found in evil corpus."
    for filepath in csv_files:
        assert_classification(filepath)


def test_clean_corpus():
    """Test that all files in the clean corpus output VALID and exit with 0."""
    csv_files = glob.glob("/app/corpus/clean/*.csv")
    assert csv_files, "No files found in clean corpus."
    failures = []
    for filepath in csv_files:
        out, code = run_script(filepath)
        if out != "VALID" or code != 0:
            failures.append(f"{os.path.basename(filepath)} (out: {out}, code: {code})")
    assert not failures, (
        f"{len(failures)} of {len(csv_files)} clean modified/failed: "
        f"{', '.join(failures[:10])}"
    )


def test_invalid_corpus():
    """Test that all files in the invalid corpus reject their malformed schema."""
    csv_files = glob.glob("/app/corpus/invalid/*.csv")
    assert csv_files, "No files found in invalid corpus."
    failures = []
    for filepath in csv_files:
        out, code = run_script(filepath)
        if out != "INVALID_SCHEMA" or code != 1:
            failures.append(f"{os.path.basename(filepath)} (out: {out}, code: {code})")
    assert not failures, (
        f"{len(failures)} of {len(csv_files)} invalid bypassed: "
        f"{', '.join(failures[:10])}"
    )


def test_unlabeled_generated_graphs():
    """Exercise novel graphs at random, non-label-revealing paths."""
    rng = random.SystemRandom()
    fixtures = []

    def txn(number):
        return f"TXN-{number:04d}"

    # Deep DAG whose transaction numbers do not reveal topological order.
    dag_nodes = [txn(n) for n in rng.sample(range(10000), 120)]
    fixtures.append([f"{dag_nodes[i]},{dag_nodes[i + 1]}" for i in range(119)])

    # Deep cycle using an independently randomized labeling.
    cycle_nodes = [txn(n) for n in rng.sample(range(10000), 120)]
    cycle_lines = [f"{cycle_nodes[i]},{cycle_nodes[i + 1]}" for i in range(119)]
    cycle_lines.append(f"{cycle_nodes[-1]},{cycle_nodes[0]}")
    fixtures.append(cycle_lines)

    # Self-loop and a disconnected multi-node cycle.
    self_node = txn(rng.randrange(10000))
    fixtures.append([f"{self_node},{self_node}"])
    disconnected = [txn(n) for n in rng.sample(range(10000), 8)]
    fixtures.append([
        f"{disconnected[0]},{disconnected[1]}",
        f"{disconnected[1]},{disconnected[2]}",
        f"{disconnected[3]},{disconnected[4]}",
        f"{disconnected[4]},{disconnected[5]}",
        f"{disconnected[5]},{disconnected[3]}",
    ])

    # Additional novel DAGs and cyclic graphs with randomized IDs and edges.
    for index in range(16):
        nodes = [txn(n) for n in rng.sample(range(10000), rng.randint(12, 35))]
        order = nodes[:]
        rng.shuffle(order)
        edges = {(order[i], order[i + 1]) for i in range(len(order) - 1)}
        for _ in range(len(order) * 2):
            left = rng.randrange(len(order) - 1)
            right = rng.randrange(left + 1, len(order))
            edges.add((order[left], order[right]))
        if index % 2:
            # The chain above guarantees a path from first to last.
            edges.add((order[-1], order[0]))
        fixtures.append([f"{left},{right}" for left, right in edges])

    # Malformed inputs, including one which would otherwise contain a cycle.
    good_a, good_b = [txn(n) for n in rng.sample(range(10000), 2)]
    malformed = [
        ["TXN-123,TXN-1234"],
        ["TXN-01234,TXN-1234"],
        ["txn-1234,TXN-5678"],
        ["TXN-1234;TXN-5678"],
        ["TXN-1234, TXN-5678"],
        ["TXN-1234,TXN-5678,TXN-9999"],
        [f"{good_a},{good_b}", "", f"{good_b},{good_a}"],
        [f"{good_a},{good_b}", "NOT_A_TRANSACTION", f"{good_b},{good_a}"],
    ]
    fixtures.extend(malformed)
    rng.shuffle(fixtures)

    with tempfile.TemporaryDirectory(prefix=f"graphcheck_{secrets.token_hex(8)}_") as directory:
        paths = []
        for lines in fixtures:
            path = os.path.join(directory, f"{secrets.token_hex(12)}.csv")
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write("\n".join(lines) + "\n")
            paths.append(path)
        rng.shuffle(paths)
        for path in paths:
            assert_classification(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
