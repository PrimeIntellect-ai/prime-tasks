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
import shutil
import subprocess
import tempfile

import pytest

DETECTOR_PATH = "/home/user/detector"
SOURCE_PATH = "/home/user/detector.c"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_detector(path):
    return subprocess.run(
        [DETECTOR_PATH, path],
        capture_output=True,
        timeout=5,
    ).returncode


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_PATH), f"Detector binary not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector binary at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled ELF executable"

    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    source = open(SOURCE_PATH, encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]csv\.h[>\"]", source), "detector.c must include libcsv's csv.h"
    assert re.search(r"\bcsv_parse\s*\(", source), "detector.c must use libcsv to parse CSV input"


def test_detector_dynamically_links_libcsv():
    dynamic = subprocess.run(
        ["readelf", "-d", DETECTOR_PATH],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert re.search(r"NEEDED.*libcsv\.so", dynamic), "Detector is not dynamically linked against libcsv"

    symbols = subprocess.run(
        ["readelf", "-Ws", DETECTOR_PATH],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    assert re.search(r"UND.*\bcsv_parse(?:@|\b)", symbols), "Detector does not import libcsv's csv_parse"

    linked = subprocess.run(
        ["ldd", DETECTOR_PATH],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    libcsv_lines = [line for line in linked.splitlines() if "libcsv.so" in line]
    assert libcsv_lines, "libcsv is absent from the detector's runtime dependencies"
    assert all("not found" not in line for line in libcsv_lines), "The dynamically linked libcsv cannot be loaded"


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    evil_bypassed = []

    for c_file in clean_files:
        if run_detector(c_file) != 0:
            clean_failed.append(os.path.basename(c_file))

    for e_file in evil_files:
        if run_detector(e_file) != 1:
            evil_bypassed.append(os.path.basename(e_file))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def connected(edges):
    adjacency = {}
    for left, right in edges:
        adjacency.setdefault(left, set()).add(right)
        adjacency.setdefault(right, set()).add(left)
    if not adjacency:
        return True
    start = next(iter(adjacency))
    seen = {start}
    stack = [start]
    while stack:
        node = stack.pop()
        for neighbor in adjacency[node]:
            if neighbor not in seen:
                seen.add(neighbor)
                stack.append(neighbor)
    return len(seen) == len(adjacency)


def make_connected_graph(rng, new_node):
    nodes = [new_node() for _ in range(rng.randint(2, 7))]
    edges = []
    for index in range(1, len(nodes)):
        edges.append((nodes[index], nodes[rng.randrange(index)]))
    possible = [(nodes[i], nodes[j]) for i in range(len(nodes)) for j in range(i + 1, len(nodes))]
    rng.shuffle(possible)
    for edge in possible[:rng.randint(0, min(3, len(possible)))]:
        if edge not in edges and (edge[1], edge[0]) not in edges:
            edges.append(edge)
    rng.shuffle(edges)
    return edges


def make_disconnected_graph(rng, new_node):
    components = []
    for _ in range(rng.randint(2, 3)):
        nodes = [new_node() for _ in range(rng.randint(2, 4))]
        edges = []
        for index in range(1, len(nodes)):
            edges.append((nodes[index], nodes[rng.randrange(index)]))
        components.extend(edges)
    rng.shuffle(components)
    return components


def test_generated_batches_on_label_neutral_paths():
    rng = random.Random(secrets.randbits(128))
    root = tempfile.mkdtemp(prefix="qb-" + secrets.token_hex(6) + "-")
    node_counter = [0]

    def new_node():
        value = node_counter[0]
        node_counter[0] += 1
        return f"N{value:03d}"

    cases = []
    try:
        # Generate both outcomes, randomize their order, and place all files in the
        # same neutral directory so neither pathname nor invocation order reveals it.
        desired = [False] * 12 + [True] * 12
        rng.shuffle(desired)
        for should_reject in desired:
            queries = []
            count = rng.randint(1, 5)
            bad_index = rng.randrange(count) if should_reject else -1
            for index in range(count):
                if index == bad_index:
                    edges = make_disconnected_graph(rng, new_node)
                else:
                    edges = make_connected_graph(rng, new_node)
                queries.append(edges)

            # Expected status is independently derived from graph connectivity.
            expected = 1 if any(not connected(edges) for edges in queries) else 0
            path = os.path.join(root, secrets.token_hex(12) + ".csv")
            with open(path, "w", newline="", encoding="ascii") as output:
                writer = csv.writer(output, lineterminator="\n")
                writer.writerow(["query_id", "edge_pattern"])
                for index, edges in enumerate(queries):
                    pattern = ";".join(f"{left}:{right}" for left, right in edges)
                    writer.writerow([f"q{index + 1}", pattern])
            cases.append((path, expected))

        rng.shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = run_detector(path)
            if actual != expected:
                failures.append(f"{os.path.basename(path)} expected {expected}, got {actual}")
        assert not failures, "Generated batch failures: " + " | ".join(failures)
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_libcsv_compilation():
    so_path = "/app/libcsv-3.0.3/libcsv.so"
    a_path = "/app/libcsv-3.0.3/libcsv.a"
    assert os.path.isdir("/app/libcsv-3.0.3"), "libcsv directory missing"

    obj_files = glob.glob("/app/libcsv-3.0.3/*.o") + glob.glob("/app/libcsv-3.0.3/.libs/*.o")
    assert len(obj_files) > 0, "libcsv does not appear to have been compiled (no .o files found)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
