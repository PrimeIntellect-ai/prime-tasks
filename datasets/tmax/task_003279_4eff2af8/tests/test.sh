#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_submission.py
import math
import os
import random
import re
import stat
import subprocess

SOURCE = "/home/user/simulate.c"
GRAPH_A = "/home/user/graph_A.txt"
GRAPH_B = "/home/user/graph_B.txt"
RESULT = "/home/user/kl_result.txt"
BINARY = "/tmp/verifier_simulate"


def node_count(*filenames):
    maximum = -1
    for filename in filenames:
        with open(filename, "r") as f:
            for line in f:
                if not line.strip():
                    continue
                u, v, _ = line.split()
                maximum = max(maximum, int(u), int(v))
    return maximum + 1


def build_matrix(filename, n):
    adj = [[0.0] * n for _ in range(n)]
    with open(filename, "r") as f:
        for line in f:
            if not line.strip():
                continue
            u, v, w = line.split()
            u, v, w = int(u), int(v), float(w)
            adj[u][v] = w
            adj[v][u] = w

    matrix = [[0.0] * n for _ in range(n)]
    for i in range(n):
        row_sum = sum(adj[i])
        if row_sum > 0.0:
            for j in range(n):
                matrix[i][j] = adj[i][j] / row_sum
    return matrix


def simulate(matrix, steps=100):
    n = len(matrix)
    p = [0.0] * n
    p[0] = 1.0
    for _ in range(steps):
        next_p = [0.0] * n
        for i in range(n):
            if p[i] != 0.0:
                for j in range(n):
                    next_p[j] += p[i] * matrix[i][j]
        p = next_p

    p = [x + 1e-9 for x in p]
    total = sum(p)
    return [x / total for x in p]


def expected_kl(graph_a, graph_b):
    n = node_count(graph_a, graph_b)
    pa = simulate(build_matrix(graph_a, n))
    pb = simulate(build_matrix(graph_b, n))
    return sum(a * math.log(a / b) for a, b in zip(pa, pb))


def run_and_check(expected):
    try:
        os.remove(RESULT)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    completed = subprocess.run(
        [BINARY], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )

    # Preserve the original output existence and numerical correctness checks.
    assert os.path.isfile(RESULT), f"The output file {RESULT} is missing."
    with open(RESULT, "r") as f:
        content = f.read()
    assert content.strip(), f"The output file {RESULT} is empty."
    assert re.fullmatch(r"[+-]?\d+\.\d{6}\n?", content), (
        "kl_result.txt must contain one value formatted to exactly 6 decimal places."
    )
    try:
        actual = float(content.strip())
    except ValueError:
        raise AssertionError(f"The content of {RESULT} is not a valid float: {content!r}")
    assert math.isfinite(actual), "The KL divergence must be finite."
    tolerance = 0.000005
    assert abs(actual - expected) <= tolerance, (
        f"The computed KL divergence {actual} differs from the expected "
        f"{expected:.6f} by more than {tolerance}."
    )


def make_case(n, split, rng):
    edges = {}

    def add(u, v, weight):
        if u > v:
            u, v = v, u
        edges[(u, v)] = weight

    # Two internally connected components, each containing a triangle to avoid
    # periodicity, joined by one bridge whose weight differs between A and B.
    for lo, hi in ((0, split), (split, n)):
        size = hi - lo
        for i in range(size):
            u = lo + i
            v = lo + ((i + 1) % size)
            add(u, v, rng.uniform(0.4, 2.0))
        add(lo, lo + 2, rng.uniform(0.4, 2.0))
        if size >= 5:
            add(lo + 1, lo + 3, rng.uniform(0.4, 2.0))

    bridge = (split - 1, split)
    add(bridge[0], bridge[1], rng.uniform(0.7, 1.5))
    edges_a = dict(edges)
    edges_b = dict(edges)
    edges_b[bridge] = rng.uniform(0.0001, 0.001)

    def render(items):
        order = list(items)
        rng.shuffle(order)
        return "".join(f"{u} {v} {items[(u, v)]:.12g}\n" for u, v in order)

    return render(edges_a), render(edges_b)


def main():
    # Preserve the original source existence assertion and require a real file.
    assert os.path.isfile(SOURCE), "The source file /home/user/simulate.c is missing."
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode) and not os.path.islink(SOURCE), (
        "/home/user/simulate.c must be a regular C source file."
    )

    # Preprocessing strips comments and inactive #if branches, so this checks
    # for an active OpenMP parallel-for directive rather than matching a comment.
    preprocessed = subprocess.run(
        ["gcc", "-fopenmp", "-E", SOURCE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert preprocessed.returncode == 0, f"C preprocessing failed: {preprocessed.stderr}"
    assert re.search(r"(?m)^\s*#\s*pragma\s+omp\s+parallel\s+for\b", preprocessed.stdout), (
        "simulate.c must contain an active '#pragma omp parallel for' directive."
    )

    compiled = subprocess.run(
        ["gcc", "-fopenmp", "-O2", SOURCE, "-o", BINARY, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert compiled.returncode == 0, f"simulate.c failed to compile: {compiled.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Compilation did not produce an executable."
    )

    with open(GRAPH_A, "rb") as f:
        original_a = f.read()
    with open(GRAPH_B, "rb") as f:
        original_b = f.read()

    try:
        # Execute the submitted artifact on the original inputs and retain the
        # original verifier's expected-value assertion.
        run_and_check(expected_kl(GRAPH_A, GRAPH_B))

        # Hidden, generated valid graphs ensure the program parses and computes
        # results instead of merely writing the one known answer.
        rng = random.SystemRandom()
        for n, split in ((10, 5), (12, 6)):
            case_a, case_b = make_case(n, split, rng)
            with open(GRAPH_A, "w") as f:
                f.write(case_a)
            with open(GRAPH_B, "w") as f:
                f.write(case_b)
            run_and_check(expected_kl(GRAPH_A, GRAPH_B))
    finally:
        with open(GRAPH_A, "wb") as f:
            f.write(original_a)
        with open(GRAPH_B, "wb") as f:
            f.write(original_b)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_submission.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
