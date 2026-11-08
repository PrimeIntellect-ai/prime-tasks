#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from collections import defaultdict
from pathlib import Path

import pytest

SOURCE = "/home/user/graph_analyzer.c"
EXECUTABLE = "/home/user/graph_analyzer"
INPUT = "/home/user/etl_edges.txt"
OUTPUT = Path("/home/user/critical_nodes.log")


def expected_lines(edges, min_degree, offset, page_size, include_all_present=True):
    degrees = defaultdict(int)
    present = set()
    for source, target in edges:
        degrees[source] += 1
        present.add(source)
        present.add(target)

    nodes = present if include_all_present else set(degrees)
    filtered = [(node, degrees[node]) for node in nodes if degrees[node] >= min_degree]
    filtered.sort(key=lambda item: (-item[1], item[0]))
    return [f"{node}: {degree}" for node, degree in filtered[offset:offset + page_size]]


def run_case(executable, input_path, edges, min_degree, offset, page_size, timeout=10):
    with open(input_path, "w") as stream:
        for source, target in edges:
            stream.write(f"{source} {target}\n")

    if OUTPUT.exists():
        OUTPUT.unlink()

    result = subprocess.run(
        [executable, str(input_path), str(min_degree), str(offset), str(page_size)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert OUTPUT.exists(), f"{executable} did not create {OUTPUT}"

    actual = OUTPUT.read_text().splitlines()
    expected = expected_lines(edges, min_degree, offset, page_size)
    assert actual == expected, f"Expected {expected}, got {actual}"


def test_source_file_exists():
    """Test that the C source file exists."""
    assert os.path.exists(SOURCE), "The source file /home/user/graph_analyzer.c does not exist."


def test_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.exists(EXECUTABLE), f"The executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as stream:
        assert stream.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable."


def test_output_file_exists():
    """Test that the output log file exists."""
    assert OUTPUT.exists(), f"The output file {OUTPUT} does not exist."


def test_source_compiles_and_rebuilt_program_works(tmp_path):
    rebuilt = tmp_path / "graph_analyzer_rebuilt"
    result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Submitted C source does not compile:\n{result.stderr}"

    edges = [
        (3, 10), (3, 11), (2, 10), (2, 12),
        (7, 2), (7, 3), (7, 3), (15, 16),
    ]
    run_case(str(rebuilt), tmp_path / "rebuilt_edges.txt", edges, 0, 1, 6)


def test_exact_argument_count_is_enforced():
    for arguments in (
        [],
        [INPUT, "10", "5"],
        [INPUT, "10", "5", "10", "extra"],
    ):
        result = subprocess.run(
            [EXECUTABLE, *arguments],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert result.returncode != 0, (
            f"Program accepted an invalid argument count: {len(arguments)}"
        )


def test_executable_graph_analysis_on_derived_cases(tmp_path):
    # This case checks duplicate edges, tie-breaking, target-only nodes,
    # filtering, offset, and page size.
    fixed_edges = [
        (40, 1), (40, 2), (40, 2),
        (5, 40), (5, 9), (5, 10),
        (8, 5), (8, 6),
        (3, 50), (60, 3),
    ]
    run_case(EXECUTABLE, tmp_path / "fixed_edges.txt", fixed_edges, 0, 2, 7)
    run_case(EXECUTABLE, tmp_path / "paged_edges.txt", fixed_edges, 2, 1, 3)

    # Generate an unpredictable fixture at verification time so a fixed answer
    # cannot pass. Answers are independently derived from the generated edges.
    rng = random.Random(secrets.randbits(128))
    random_edges = []
    for _ in range(2500):
        source = rng.randint(1, 180)
        if rng.randrange(5) == 0:
            source = rng.randint(1, 15)
        target = rng.randint(1, 50000)
        random_edges.append((source, target))

    min_degree = rng.randint(8, 14)
    offset = rng.randint(2, 12)
    page_size = rng.randint(10, 30)
    run_case(
        EXECUTABLE,
        tmp_path / "random_edges.txt",
        random_edges,
        min_degree,
        offset,
        page_size,
    )


def test_required_invocation_runs_successfully():
    result = subprocess.run(
        [EXECUTABLE, INPUT, "10", "5", "10"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Required invocation failed with {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_output_contents():
    """Test that the output file contains the correctly computed, sorted, and paginated results."""
    edges_path = INPUT
    log_path = str(OUTPUT)

    assert os.path.exists(edges_path), f"Input file {edges_path} is missing."
    assert os.path.exists(log_path), f"Output file {log_path} is missing."

    out_degrees = defaultdict(int)
    with open(edges_path, "r") as stream:
        for line in stream:
            parts = line.strip().split()
            if len(parts) == 2:
                source = int(parts[0])
                out_degrees[source] += 1

    min_degree = 10
    offset = 5
    page_size = 10
    filtered = [(node, degree) for node, degree in out_degrees.items() if degree >= min_degree]
    filtered.sort(key=lambda item: (-item[1], item[0]))
    paginated = filtered[offset:offset + page_size]
    expected = [f"{node}: {degree}" for node, degree in paginated]

    with open(log_path, "r") as stream:
        actual = [line.strip() for line in stream if line.strip()]

    assert actual == expected, (
        f"Contents of {log_path} do not match the expected output.\n"
        f"Expected: {expected}\nActual: {actual}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
