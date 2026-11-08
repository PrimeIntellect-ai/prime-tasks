#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import heapq
import os
import random
import re
import shutil
import subprocess

RUST_BIN = "/home/user/workspace/rust_graph/bin/graph_resolver"
ORACLE_BIN = "/app/oracle_graph_solver"
GO_DIR = "/home/user/workspace/go_tester"
GO_TEST = os.path.join(GO_DIR, "bench_test.go")
LOG_FILE = "/tmp/graph_invocations.log"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 180)
    return subprocess.run(cmd, **kwargs)


def expected_result(graph):
    tokens = graph.replace(",", " ").replace("-", " ").replace(">", " ").split()
    adj = collections.defaultdict(list)
    indegree = {}
    nodes = set()
    for i in range(0, len(tokens) - 1, 2):
        u, v = tokens[i], tokens[i + 1]
        adj[u].append(v)
        indegree[v] = indegree.get(v, 0) + 1
        indegree.setdefault(u, 0)
        nodes.add(u)
        nodes.add(v)

    queue = [node for node in nodes if indegree[node] == 0]
    heapq.heapify(queue)
    result = []
    while queue:
        node = heapq.heappop(queue)
        result.append(node)
        for nxt in adj[node]:
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                heapq.heappush(queue, nxt)
    if nodes and len(result) != len(nodes):
        return "CYCLE_DETECTED"
    return ",".join(result)


def assert_solver(binary, graph):
    result = run([binary, graph], timeout=10)
    assert result.returncode == 0, f"{binary} failed for {graph!r}: {result.stderr}"
    assert result.stdout.strip() == expected_result(graph), (
        f"Wrong result for {graph!r}: got {result.stdout.strip()!r}, "
        f"expected {expected_result(graph)!r}"
    )


def test_rust_binary_exists():
    assert os.path.exists(RUST_BIN), f"Rust binary missing at {RUST_BIN}"
    assert os.path.isfile(RUST_BIN), f"Rust path {RUST_BIN} is not a file"
    assert os.access(RUST_BIN, os.X_OK), f"Rust binary at {RUST_BIN} is not executable"
    with open(RUST_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "graph_resolver is not a compiled ELF executable"
    info = run(["file", RUST_BIN], timeout=10)
    assert info.returncode == 0
    lowered = info.stdout.lower()
    assert "x86-64" in lowered and ("statically linked" in lowered or "static-pie linked" in lowered), info.stdout


def test_rust_project_cross_compiles_and_binary_behaves():
    env = os.environ.copy()
    env.update({"RUSTUP_HOME": "/opt/rust", "CARGO_HOME": "/opt/cargo"})
    env["PATH"] = "/opt/cargo/bin:" + env.get("PATH", "")
    build = run(
        ["cargo", "build", "--release", "--target", "x86_64-unknown-linux-musl"],
        cwd="/home/user/workspace/rust_graph",
        env=env,
    )
    assert build.returncode == 0, f"Rust project does not cross-compile:\n{build.stdout}\n{build.stderr}"

    cases = [
        "A->B, B->C, A->C",
        "B->D, A->D, A->C, C->E, D->E",
        "A->B, B->A",
        "A->B, B->C, C->A",
        "A->B, A->B, B->C",
        "z->x, a->x, a->b",
        "",
    ]
    rng = random.Random(0x6A09E667)
    for case_no in range(80):
        count = rng.randint(3, 14)
        nodes = [f"n{case_no}_{i}" for i in range(count)]
        order = nodes[:]
        rng.shuffle(order)
        edges = []
        for i in range(count - 1):
            edges.append((order[i], order[i + 1]))
        for i in range(count):
            for j in range(i + 2, count):
                if rng.random() < 0.18:
                    edges.append((order[i], order[j]))
        rng.shuffle(edges)
        cases.append(", ".join(f"{u}->{v}" for u, v in edges))
    for graph in cases:
        assert_solver(RUST_BIN, graph)


def test_go_tester_exists():
    assert os.path.exists(GO_TEST), f"Go test file missing at {GO_TEST}"
    source = open(GO_TEST, encoding="utf-8").read()
    assert re.search(r"func\s+BenchmarkGraphSolver\s*\(", source), "BenchmarkGraphSolver is missing"
    assert ("testing/quick" in source or "math/rand" in source or "crypto/rand" in source), (
        "The harness does not use property/random generation"
    )
    assert (re.search(r"\bgo\s+", source) or "RunParallel" in source), (
        "The harness does not contain concurrent benchmark execution"
    )


def test_go_tests_pass():
    result = run(["go", "test", "-count=1"], cwd=GO_DIR)
    assert result.returncode == 0, f"Go tests failed:\n{result.stdout}\n{result.stderr}"


def compile_invocation_wrapper():
    source = r'''
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int oracle = strstr(argv[0], "oracle_graph_solver") != NULL;
    const char *real = oracle ? "/app/oracle_graph_solver.verifier-real" :
                                "/home/user/workspace/rust_graph/bin/graph_resolver.verifier-real";
    const char *logpath = getenv("GRAPH_VERIFY_LOG");
    if (logpath && argc > 1) {
        int fd = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0666);
        if (fd >= 0) {
            char line[8192];
            int n = snprintf(line, sizeof(line), "%c\t%s\n", oracle ? 'O' : 'R', argv[1]);
            if (n > 0) write(fd, line, (size_t)(n < (int)sizeof(line) ? n : (int)sizeof(line)));
            close(fd);
        }
    }
    if (oracle && getenv("VERIFIER_CORRUPT_ORACLE")) {
        puts("VERIFIER_INTENTIONAL_WRONG_RESULT");
        return 0;
    }
    execv(real, argv);
    perror("execv");
    return 127;
}
'''
    path = "/tmp/graph_invocation_wrapper.c"
    with open(path, "w", encoding="utf-8") as f:
        f.write(source)
    result = run(["gcc", "-O2", path, "-o", "/tmp/graph_invocation_wrapper"], timeout=30)
    assert result.returncode == 0, result.stderr


def graph_is_dag(graph):
    tokens = graph.replace(",", " ").replace("-", " ").replace(">", " ").split()
    if "->" not in graph or len(tokens) < 2 or len(tokens) % 2:
        return False
    adj = collections.defaultdict(list)
    indegree = collections.defaultdict(int)
    nodes = set()
    for i in range(0, len(tokens), 2):
        u, v = tokens[i], tokens[i + 1]
        adj[u].append(v)
        indegree[v] += 1
        nodes.update((u, v))
    queue = [n for n in nodes if indegree[n] == 0]
    seen = 0
    while queue:
        node = queue.pop()
        seen += 1
        for nxt in adj[node]:
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                queue.append(nxt)
    return seen == len(nodes)


def test_go_benchmark_throughput_and_property_checks():
    compile_invocation_wrapper()
    rust_real = RUST_BIN + ".verifier-real"
    oracle_real = ORACLE_BIN + ".verifier-real"
    assert not os.path.exists(rust_real) and not os.path.exists(oracle_real)
    os.replace(RUST_BIN, rust_real)
    os.replace(ORACLE_BIN, oracle_real)
    shutil.copy2("/tmp/graph_invocation_wrapper", RUST_BIN)
    shutil.copy2("/tmp/graph_invocation_wrapper", ORACLE_BIN)
    os.chmod(RUST_BIN, 0o755)
    os.chmod(ORACLE_BIN, 0o755)

    env = os.environ.copy()
    env["GRAPH_VERIFY_LOG"] = LOG_FILE
    try:
        open(LOG_FILE, "w").close()
        result = run(
            ["go", "test", "-count=1", "-bench", ".", "-benchtime=5s"],
            cwd=GO_DIR,
            env=env,
        )
        assert result.returncode == 0, f"Go benchmark failed:\n{result.stdout}\n{result.stderr}"

        match = re.search(r"(\d+(?:\.\d+)?)\s+ns/op", result.stdout)
        assert match is not None, f"Could not parse ns/op from benchmark output:\n{result.stdout}"
        ns_per_op = float(match.group(1))
        throughput = 1e9 / ns_per_op
        assert throughput >= 500.0, (
            f"Throughput {throughput:.2f} ops/sec is below 500.0 ops/sec "
            f"(ns/op: {ns_per_op})"
        )

        rust_calls = []
        oracle_calls = []
        with open(LOG_FILE, encoding="utf-8", errors="replace") as f:
            for line in f:
                tag, sep, graph = line.rstrip("\n").partition("\t")
                if not sep:
                    continue
                (oracle_calls if tag == "O" else rust_calls if tag == "R" else []).append(graph)

        rust_counts = collections.Counter(rust_calls)
        oracle_counts = collections.Counter(oracle_calls)
        paired_dags = sum(
            min(count, oracle_counts[graph])
            for graph, count in rust_counts.items()
            if graph_is_dag(graph)
        )
        distinct_dags = {
            graph for graph in rust_counts
            if oracle_counts[graph] and graph_is_dag(graph)
        }
        assert paired_dags >= 5000, (
            f"Benchmark invoked both solvers on only {paired_dags} paired DAGs; at least 5000 are required"
        )
        assert len(distinct_dags) >= 100, (
            f"Only {len(distinct_dags)} distinct DAGs were exercised; random property generation is missing"
        )

        corrupt_env = env.copy()
        corrupt_env["VERIFIER_CORRUPT_ORACLE"] = "1"
        corrupt = run(
            ["go", "test", "-count=1", "-bench", ".", "-benchtime=1x"],
            cwd=GO_DIR,
            env=corrupt_env,
        )
        assert corrupt.returncode != 0, (
            "Benchmark still passed when the oracle returned deliberately incorrect answers; "
            "it is not asserting equivalence between the two executables"
        )
    finally:
        for wrapper in (RUST_BIN, ORACLE_BIN):
            if os.path.exists(wrapper):
                os.remove(wrapper)
        if os.path.exists(rust_real):
            os.replace(rust_real, RUST_BIN)
        if os.path.exists(oracle_real):
            os.replace(oracle_real, ORACLE_BIN)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
