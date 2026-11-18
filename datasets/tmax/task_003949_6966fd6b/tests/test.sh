#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import stat
import subprocess
import tempfile

SCRIPT = "/home/user/run_analysis.sh"


def test_run_analysis_exists_and_executable():
    path = SCRIPT
    assert os.path.isfile(path), f"File {path} does not exist."

    st = os.stat(path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"File {path} is not executable."


def test_metric_txt_content():
    path = "/home/user/metric.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "2", f"Expected metric.txt to contain exactly '2', but got '{content}'."


def expected_result(graph_path, primers_path):
    primers = {}
    with open(primers_path) as f:
        for line in f:
            node, sequence = line.rstrip("\n").split("\t")
            primers[node] = sequence

    edges = []
    with open(graph_path) as f:
        for line in f:
            node1, node2, weight = line.rstrip("\n").split("\t")
            edges.append((int(weight), node1, node2))

    _, node1, node2 = max(edges)
    return sum(a != b for a, b in zip(primers[node1], primers[node2]))


def run_and_check(graph_path, primers_path):
    expected = expected_result(graph_path, primers_path)
    result = subprocess.run(
        [SCRIPT, graph_path, primers_path],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert result.returncode == 0, f"run_analysis.sh exited with {result.returncode}: {result.stderr}"
    assert re.fullmatch(r"\d+\n?", result.stdout), f"Expected only an integer on stdout, got {result.stdout!r}"
    assert result.stdout.strip() == str(expected), f"Expected {expected}, got {result.stdout!r}"


def test_script_runs_on_provided_files():
    run_and_check("/home/user/mesh_graph.tsv", "/home/user/primers.tsv")


def test_script_parses_runtime_generated_tsv_inputs():
    rng = secrets.SystemRandom()
    distances = [0, 1, 6, 10]
    rng.shuffle(distances)
    alphabet = "ACGT"

    with tempfile.TemporaryDirectory() as root:
        for case_number, distance in enumerate(distances):
            case_dir = os.path.join(root, f"case_{case_number}_{secrets.token_hex(6)}")
            os.mkdir(case_dir)
            graph_path = os.path.join(case_dir, "mesh_graph.tsv")
            primers_path = os.path.join(case_dir, "primers.tsv")

            nodes = [f"Node_{secrets.token_hex(5)}" for _ in range(8)]
            first = "".join(rng.choice(alphabet) for _ in range(10))
            changed_positions = set(rng.sample(range(10), distance))
            second = "".join(
                rng.choice([base for base in alphabet if base != char]) if index in changed_positions else char
                for index, char in enumerate(first)
            )

            sequences = {node: "".join(rng.choice(alphabet) for _ in range(10)) for node in nodes}
            sequences[nodes[3]] = first
            sequences[nodes[6]] = second

            edges = [
                (nodes[0], nodes[1], 17),
                (nodes[2], nodes[4], 231),
                (nodes[3], nodes[6], 900 + rng.randrange(100)),
                (nodes[5], nodes[7], 408),
                (nodes[1], nodes[7], 73),
            ]
            rng.shuffle(edges)
            primer_rows = list(sequences.items())
            rng.shuffle(primer_rows)

            with open(graph_path, "w") as f:
                for node1, node2, weight in edges:
                    f.write(f"{node1}\t{node2}\t{weight}\n")
            with open(primers_path, "w") as f:
                for node, sequence in primer_rows:
                    f.write(f"{node}\t{sequence}\n")

            run_and_check(graph_path, primers_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
