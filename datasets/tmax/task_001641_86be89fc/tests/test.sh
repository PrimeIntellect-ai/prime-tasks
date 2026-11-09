#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile
import time

import pytest

ROOT = "/app/libmathgraph-1.4.2"
EXE = os.path.join(ROOT, "mathgraph_cli")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def extract_result(stdout):
    values = re.findall(r"(?<![A-Za-z0-9_.])[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?", stdout)
    assert values, f"Solver produced no numeric result. Stdout: {stdout!r}"
    return [float(v) for v in values]


def write_graph(path, rows):
    with open(path, "w") as f:
        f.write(f"{len(rows)}\n")
        for edges in rows:
            f.write(str(len(edges)))
            if edges:
                f.write(" " + " ".join(map(str, edges)))
            f.write("\n")


def test_makefile_and_rebuild():
    makefile = os.path.join(ROOT, "Makefile")
    assert os.path.isfile(makefile), "Makefile is missing"
    text = open(makefile).read()
    assert re.search(r"(?:^|\s)-O3(?:\s|$)", text), "Makefile does not use -O3"
    assert re.search(r"(?:^|\s)-lm(?:\s|$)", text), "Makefile does not link libm with -lm"
    assert re.search(r"(?:^|\s)-static(?:\s|$)", text), "Makefile does not request static linking"
    assert "mathgraph_cli" in text and "src/cli_wrapper.c" in text, "Makefile does not build mathgraph_cli from cli_wrapper.c"

    clean = run(["make", "clean"], cwd=ROOT, timeout=30)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    built = run(["make"], cwd=ROOT, timeout=60)
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(os.path.join(ROOT, "mathgraph_solver")), "make did not build mathgraph_solver"
    assert os.access(os.path.join(ROOT, "mathgraph_solver"), os.X_OK)
    assert os.path.isfile(EXE), "make did not build mathgraph_cli"
    assert os.access(EXE, os.X_OK)


def test_status_file():
    path = "/home/user/status.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert "READY" in content, f"Expected 'READY' in {path}, but found: '{content}'"


def test_executable_exists():
    assert os.path.isfile(EXE), f"Executable {EXE} is missing. Did the build succeed?"
    assert os.access(EXE, os.X_OK), f"File {EXE} exists but is not executable."


def test_executable_is_static_elf():
    hdr = run(["readelf", "-h", EXE], timeout=10)
    assert hdr.returncode == 0 and "ELF Header" in hdr.stdout, "mathgraph_cli is not an ELF executable"
    program_headers = run(["readelf", "-l", EXE], timeout=10)
    assert program_headers.returncode == 0
    assert "INTERP" not in program_headers.stdout, "mathgraph_cli has a dynamic interpreter and is not statically linked"
    dynamic = run(["readelf", "-d", EXE], timeout=10)
    assert dynamic.returncode == 0
    assert "NEEDED" not in dynamic.stdout, "mathgraph_cli has dynamic library dependencies"


def test_solver_result_and_semver_on_unseen_graph():
    rows = []
    for i in range(73):
        count = secrets.randbelow(181)
        rows.append([secrets.randbelow(200001) - 100000 for _ in range(count)])
    expected = sum(math.sin(float(edge)) for edges in rows for edge in edges)

    with tempfile.TemporaryDirectory() as td:
        graph = os.path.join(td, "unseen_graph.txt")
        write_graph(graph, rows)

        compatible = run([EXE, ">=1.4.2", graph], timeout=10)
        assert compatible.returncode == 0, (
            f"Compatible version was rejected. stdout={compatible.stdout!r}, stderr={compatible.stderr!r}"
        )
        numbers = extract_result(compatible.stdout)
        assert any(math.isclose(value, expected, rel_tol=1e-7, abs_tol=2e-5) for value in numbers), (
            f"Expected graph result {expected}, but stdout was {compatible.stdout!r}"
        )

        incompatible = run([EXE, ">=1.4.3", graph], timeout=10)
        assert incompatible.returncode != 0, "Incompatible requirement >=1.4.3 was incorrectly accepted"

        semantic_not_lexical = run([EXE, ">=1.10.0", graph], timeout=10)
        assert semantic_not_lexical.returncode != 0, "Version comparison appears lexical rather than semantic"


def test_off_by_one_repair_under_asan():
    with tempfile.TemporaryDirectory() as td:
        harness = os.path.join(td, "harness.c")
        graph = os.path.join(td, "connected_graph.txt")
        binary = os.path.join(td, "asan_solver")
        rows = [list(range(4096)), [], [1, 2, 3, 4, 5]]
        write_graph(graph, rows)
        expected = sum(math.sin(float(edge)) for edges in rows for edge in edges)
        with open(harness, "w") as f:
            f.write(r'''#include <stdio.h>
#include "graph_solve.h"
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    Graph *g = load_graph(argv[1]);
    if (!g) return 3;
    printf("%.12f\n", solve_graph(g));
    free_graph(g);
    return 0;
}
''')
        compiled = run([
            "gcc", "-O1", "-g", "-fsanitize=address", "-fno-omit-frame-pointer",
            "-I", os.path.join(ROOT, "src"), harness,
            os.path.join(ROOT, "src", "graph_solve.c"), "-lm", "-o", binary
        ], timeout=30)
        assert compiled.returncode == 0, f"Could not instrument graph_solve.c:\n{compiled.stderr}"
        checked = run([binary, graph], timeout=15, env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1"})
        assert checked.returncode == 0, (
            "Instrumented graph traversal failed; the off-by-one or another memory error remains.\n"
            f"stdout={checked.stdout}\nstderr={checked.stderr}"
        )
        values = extract_result(checked.stdout)
        assert any(math.isclose(v, expected, rel_tol=1e-9, abs_tol=1e-8) for v in values)


def test_execution_time_and_correctness():
    data_path = "/app/test_data/large_graph.mtx"
    assert os.path.isfile(data_path), f"Test data {data_path} is missing."

    start_time = time.perf_counter()
    result = subprocess.run(
        [EXE, ">=1.4.0", data_path],
        capture_output=True,
        text=True
    )
    elapsed_time = time.perf_counter() - start_time

    assert result.returncode == 0, (
        f"Execution of {EXE} failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    extract_result(result.stdout)

    threshold = 0.5
    assert elapsed_time <= threshold, (
        f"Execution time metric failed: took {elapsed_time:.3f} seconds, "
        f"which exceeds the threshold of {threshold} seconds. "
        "Ensure -O3 optimization is used and the memory safety bug is fixed."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
