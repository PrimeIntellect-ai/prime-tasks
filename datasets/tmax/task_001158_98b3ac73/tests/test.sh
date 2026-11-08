#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import tempfile

WORK = "/home/user/mesh_simulation"
EXPECTED_GRAPH = "0 1\n0 2\n1 2\n1 3\n2 3\n"
EXPECTED_LINES = [
    "P(0)=0.202500",
    "P(1)=0.302300",
    "P(2)=0.297400",
    "P(3)=0.197800",
    "KL=0.000055",
]


def read_nonblank_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def expected_output(edges):
    neighbors = [[] for _ in range(4)]
    for a, b in edges:
        neighbors[a].append(b)
        neighbors[b].append(a)
    for entries in neighbors:
        entries.sort()
        assert entries

    seed = 42
    current = 0
    counts = [0, 0, 0, 0]
    for _ in range(10000):
        seed = (seed * 1103515245 + 12345) & 0x7fffffff
        current = neighbors[current][seed % len(neighbors[current])]
        counts[current] += 1

    probabilities = [count / 10000.0 for count in counts]
    twice_edges = 2.0 * len(edges)
    theoretical = [len(neighbors[i]) / twice_edges for i in range(4)]
    divergence = sum(
        p * math.log(p / q) for p, q in zip(probabilities, theoretical) if p > 0
    )
    return [*(f"P({i})={probabilities[i]:.6f}" for i in range(4)),
            f"KL={divergence:.6f}"]


def run_checked(command, cwd, timeout=20):
    return subprocess.run(
        command, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=True
    )


def test_directory_exists():
    assert os.path.isdir(WORK), "Directory /home/user/mesh_simulation does not exist."


def test_files_exist():
    for filename in ["graph.txt", "simulate.c", "Makefile", "results.txt"]:
        path = os.path.join(WORK, filename)
        assert os.path.isfile(path), f"Required file {path} is missing."


def test_graph_contents():
    with open(os.path.join(WORK, "graph.txt"), "r") as f:
        assert f.read() == EXPECTED_GRAPH, "graph.txt does not contain the required edges."


def test_results_contents():
    actual_lines = read_nonblank_lines(os.path.join(WORK, "results.txt"))
    assert len(actual_lines) == len(EXPECTED_LINES), (
        f"Expected {len(EXPECTED_LINES)} lines in results.txt, found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, EXPECTED_LINES)):
        assert actual == expected, (
            f"Mismatch on line {i+1} in results.txt. Expected '{expected}', got '{actual}'."
        )


def test_makefile_builds_and_runs_pipeline():
    executable = os.path.join(WORK, "simulate")
    results = os.path.join(WORK, "results.txt")
    if os.path.lexists(executable):
        os.remove(executable)

    run_checked(["make", "-B", "default"], WORK)
    assert os.path.isfile(executable), "The default target did not produce simulate."
    mode = os.stat(executable).st_mode
    assert mode & stat.S_IXUSR, "simulate is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "simulate is not a compiled ELF executable."

    if os.path.lexists(results):
        os.remove(results)
    run_checked(["make", "-B", "run"], WORK)
    assert os.path.isfile(results), "The run target did not create results.txt."
    assert read_nonblank_lines(results) == EXPECTED_LINES


def test_c_program_computes_walk_from_graph_input():
    source = os.path.join(WORK, "simulate.c")
    with tempfile.TemporaryDirectory() as tempdir:
        binary = os.path.join(tempdir, "simulate_test")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", source, "-lm", "-o", binary],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert compile_result.returncode == 0, compile_result.stderr

        cases = [
            [(2, 3), (1, 3), (1, 2), (0, 2), (0, 1)],
            [(0, 1), (1, 2), (2, 3), (3, 0)],
            [(0, 1), (0, 2), (0, 3)],
        ]

        rng = secrets.SystemRandom()
        for _ in range(3):
            edge_set = set()
            for node in range(1, 4):
                parent = rng.randrange(node)
                edge_set.add((parent, node))
            for a in range(4):
                for b in range(a + 1, 4):
                    if rng.randrange(2):
                        edge_set.add((a, b))
            edges = list(edge_set)
            rng.shuffle(edges)
            oriented = [(b, a) if rng.randrange(2) else (a, b) for a, b in edges]
            cases.append(oriented)

        graph_path = os.path.join(tempdir, "graph.txt")
        for edges in cases:
            with open(graph_path, "w") as f:
                for a, b in edges:
                    f.write(f"{a} {b}\n")
            completed = run_checked([binary], tempdir)
            actual = completed.stdout.strip().splitlines()
            assert actual == expected_output(edges), (
                f"Incorrect simulation output for graph {edges}:\n"
                f"stdout={completed.stdout!r}\nstderr={completed.stderr!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
