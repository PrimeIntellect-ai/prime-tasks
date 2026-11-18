#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

EXECUTABLE_PATH = "/home/user/deadlock_detector"
SOURCE_PATH = "/home/user/deadlock_detector.cpp"
CSV_HEADER = "/app/csv-parser/include/csv.hpp"
CSV_INCLUDE_DIR = "/app/csv-parser/include"
CLEAN_CORPUS_DIR = "/home/user/corpora/clean"
EVIL_CORPUS_DIR = "/home/user/corpora/evil"


def run_detector(executable, csv_path, *extra_args):
    return subprocess.run(
        [str(executable), str(csv_path), *map(str, extra_args)],
        capture_output=True,
        timeout=5,
    )


def test_executable_exists_and_is_executable():
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "deadlock_detector must be a compiled executable"


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    assert len(clean_files) > 0, f"No clean CSV files found in {CLEAN_CORPUS_DIR}"

    failed_files = []
    for csv_file in clean_files:
        result = run_detector(EXECUTABLE_PATH, csv_file)
        if result.returncode != 0:
            failed_files.append(os.path.basename(csv_file))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (expected exit code 0): {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))
    assert len(evil_files) > 0, f"No evil CSV files found in {EVIL_CORPUS_DIR}"

    failed_files = []
    for csv_file in evil_files:
        result = run_detector(EXECUTABLE_PATH, csv_file)
        if result.returncode != 1:
            failed_files.append(f"{os.path.basename(csv_file)} (status {result.returncode})")

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files returned the wrong status (expected exactly 1): {', '.join(failed_files)}")


@pytest.fixture(scope="session")
def rebuilt_executable(tmp_path_factory):
    assert os.path.isfile(SOURCE_PATH), f"Source not found at {SOURCE_PATH}"
    assert os.path.isfile(CSV_HEADER), f"Vendored CSV header not found at {CSV_HEADER}"

    source = Path(SOURCE_PATH).read_text(errors="replace")
    assert re.search(r"^\s*#\s*include\s*[<\"][^>\"]*csv\.hpp[>\"]", source, re.MULTILINE), \
        "deadlock_detector.cpp must include the vendored csv.hpp library"
    assert re.search(r"\bcsv\s*::|\busing\s+namespace\s+csv\b|\busing\s+csv\s*::", source), \
        "deadlock_detector.cpp must use the csv library namespace"

    build_dir = tmp_path_factory.mktemp("build")
    probe = build_dir / "header_probe.cpp"
    probe.write_text('#include "csv.hpp"\nint main() { return 0; }\n')
    probe_out = build_dir / "header_probe"
    probe_result = subprocess.run(
        ["g++", "-std=c++17", "-pthread", "-I", CSV_INCLUDE_DIR, str(probe), "-o", str(probe_out)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert probe_result.returncode == 0, \
        f"The vendored csv.hpp header is still broken:\n{probe_result.stdout}\n{probe_result.stderr}"

    rebuilt = build_dir / "deadlock_detector_rebuilt"
    build_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-pthread", "-I", CSV_INCLUDE_DIR, SOURCE_PATH, "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build_result.returncode == 0, \
        f"deadlock_detector.cpp could not be rebuilt with the vendored library:\n{build_result.stdout}\n{build_result.stderr}"
    return rebuilt


def graph_has_cycle(edges):
    graph = {}
    nodes = set()
    for source, target in edges:
        nodes.add(source)
        nodes.add(target)
        graph.setdefault(source, []).append(target)

    state = {}

    def visit(node):
        if state.get(node) == 1:
            return True
        if state.get(node) == 2:
            return False
        state[node] = 1
        for neighbor in graph.get(node, []):
            if visit(neighbor):
                return True
        state[node] = 2
        return False

    return any(visit(node) for node in nodes if state.get(node, 0) == 0)


def make_cases(rng):
    cases = [
        [],
        [(0, 1)],
        [(0, 1), (1, 2), (2, 3)],
        [(0, 1), (0, 2), (1, 3), (2, 3)],
        [(0, 1), (2, 3), (4, 5)],
        [(0, 0)],
        [(0, 1), (1, 0)],
        [(0, 1), (1, 2), (2, 0)],
        [(0, 1), (2, 3), (3, 4), (4, 2), (5, 6)],
    ]

    for index in range(24):
        count = rng.randint(5, 14)
        order = list(range(count))
        rng.shuffle(order)
        edges = []
        for i in range(count):
            for j in range(i + 1, count):
                if rng.random() < 0.18:
                    edges.append((order[i], order[j]))
        if index % 2:
            length = rng.randint(2, min(6, count))
            cycle_nodes = rng.sample(range(count), length)
            edges.extend((cycle_nodes[i], cycle_nodes[(i + 1) % length]) for i in range(length))
        cases.append(edges)
    return cases


def test_generated_unpredictable_graphs(rebuilt_executable):
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    executables = [Path(EXECUTABLE_PATH), rebuilt_executable]

    with tempfile.TemporaryDirectory(prefix="wf_inputs_") as directory:
        paths_and_expected = []
        for edges in make_cases(rng):
            node_ids = {}
            for node in {value for edge in edges for value in edge}:
                node_ids[node] = rng.randint(10**8, 10**12)
            rendered_edges = [(node_ids[a], node_ids[b]) for a, b in edges]
            rng.shuffle(rendered_edges)

            path = Path(directory) / f"{secrets.token_hex(16)}.csv"
            with path.open("w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(["tx_id", "waiting_for_tx_id"])
                writer.writerows(rendered_edges)
            paths_and_expected.append((path, 1 if graph_has_cycle(rendered_edges) else 0))

        rng.shuffle(paths_and_expected)
        for executable in executables:
            for path, expected in paths_and_expected:
                result = run_detector(executable, path)
                assert result.returncode == expected, \
                    f"{executable} returned {result.returncode} for {path}; expected {expected}"


def test_requires_exactly_one_argument(rebuilt_executable):
    sample = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))[0]
    for executable in (EXECUTABLE_PATH, str(rebuilt_executable)):
        no_arg = subprocess.run([executable], capture_output=True, timeout=5)
        assert no_arg.returncode != 0, f"{executable} accepted no input argument"
        extra_arg = subprocess.run([executable, sample, sample], capture_output=True, timeout=5)
        assert extra_arg.returncode != 0, f"{executable} accepted more than one input argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
