#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import subprocess
import tempfile
import pytest

EXE_PATH = "/home/user/detector"
SOURCE_PATH = "/home/user/detector.cpp"


def run_detector(exe_path, csv_path):
    result = subprocess.run(
        [exe_path, csv_path], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, (
        f"{exe_path} exited with status {result.returncode} for {csv_path}; "
        f"stderr: {result.stderr!r}"
    )
    return result.stdout.strip()


def test_red_frame_count_file():
    count_file = "/home/user/red_frame_count.txt"
    assert os.path.isfile(count_file), f"Expected file {count_file} does not exist."

    with open(count_file, "r") as f:
        content = f.read().strip()

    assert content == "45", f"Expected red frame count to be '45', but got '{content}'."


def test_detector_executable():
    assert os.path.isfile(EXE_PATH), f"Executable missing at {EXE_PATH}."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    mode = os.stat(EXE_PATH).st_mode
    assert stat.S_ISREG(mode), f"{EXE_PATH} is not a regular file."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE_PATH} is not a compiled ELF executable."


def test_detector_source_exists_compiles_and_contains_recursion():
    assert os.path.isfile(SOURCE_PATH), f"C++ source missing at {SOURCE_PATH}."
    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert source.strip(), f"C++ source at {SOURCE_PATH} is empty."

    # Remove comments and literals before looking for a direct recursive function call.
    cleaned = re.sub(
        r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        " ", source, flags=re.DOTALL
    )
    definition = re.compile(
        r'\b(?:[A-Za-z_]\w*(?:::\w+)*(?:\s*<[^;{}()]*>)?[\s*&]+)+'
        r'([A-Za-z_]\w*)\s*\([^;{}]*\)\s*(?:const\s*)?(?:noexcept\s*)?\{'
    )
    recursive = False
    for match in definition.finditer(cleaned):
        name = match.group(1)
        depth = 1
        pos = match.end()
        while pos < len(cleaned) and depth:
            if cleaned[pos] == '{':
                depth += 1
            elif cleaned[pos] == '}':
                depth -= 1
            pos += 1
        body = cleaned[match.end():pos - 1]
        if re.search(r'\b' + re.escape(name) + r'\s*\(', body):
            recursive = True
            break
    assert recursive, "detector.cpp does not contain a recursive function implementation."

    with tempfile.TemporaryDirectory(prefix="build_") as td:
        rebuilt = os.path.join(td, "detector_rebuilt")
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", rebuilt],
            capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"detector.cpp failed to compile: {result.stderr}"
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)


def test_adversarial_corpus_evaluation():
    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".csv")]
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".csv")]

    assert len(evil_files) > 0, "No CSV files found in evil corpus."
    assert len(clean_files) > 0, "No CSV files found in clean corpus."

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        full_path = os.path.join(evil_dir, f)
        try:
            if run_detector(EXE_PATH, full_path) != "REJECT":
                evil_bypassed.append(f)
        except Exception:
            evil_bypassed.append(f)

    for f in clean_files:
        full_path = os.path.join(clean_dir, f)
        try:
            if run_detector(EXE_PATH, full_path) != "ACCEPT":
                clean_modified.append(f)
        except Exception:
            clean_modified.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if errors:
        pytest.fail(" | ".join(errors))


def graph_has_cycle(nodes, edges):
    graph = {node: [] for node in nodes}
    for src, dst in edges:
        graph[src].append(dst)
    state = {node: 0 for node in nodes}

    def visit(node):
        if state[node] == 1:
            return True
        if state[node] == 2:
            return False
        state[node] = 1
        for nxt in graph[node]:
            if visit(nxt):
                return True
        state[node] = 2
        return False

    return any(visit(node) for node in nodes if state[node] == 0)


def write_graph_csv(path, nodes, edges, rng):
    # Give every transaction a distinct held resource. An edge A->B is encoded
    # by making A wait for B's resource.
    resources = {node: "R" + secrets.token_hex(6) for node in nodes}
    rows = []
    timestamp = 1
    for node in nodes:
        rows.append([str(timestamp), node, "HOLD", resources[node]])
        timestamp += 1
    for src, dst in edges:
        rows.append([str(timestamp), src, "WAIT", resources[dst]])
        timestamp += 1
    rng.shuffle(rows)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write("timestamp,tx_id,action,resource_id\n")
        for row in rows:
            f.write(",".join(row) + "\n")


def test_generated_unpredictable_graphs():
    rng = secrets.SystemRandom()
    cases = []

    for index in range(32):
        count = rng.randint(3, 10)
        nodes = ["T" + secrets.token_hex(5) for _ in range(count)]
        edges = set()

        if index % 2 == 0:
            # DAG: all edges point toward a higher position.
            for src in range(count):
                for dst in range(src + 1, count):
                    if rng.random() < 0.30:
                        edges.add((nodes[src], nodes[dst]))
        else:
            # Force a cycle, then add arbitrary extra dependencies.
            cycle_size = rng.randint(2, count)
            cycle_nodes = rng.sample(nodes, cycle_size)
            for i, node in enumerate(cycle_nodes):
                edges.add((node, cycle_nodes[(i + 1) % cycle_size]))
            for src in nodes:
                for dst in nodes:
                    if src != dst and rng.random() < 0.12:
                        edges.add((src, dst))

        cases.append((nodes, list(edges)))

    with tempfile.TemporaryDirectory(prefix="csv_inputs_") as td:
        rebuilt = os.path.join(td, "program")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", rebuilt],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, compile_result.stderr

        for index, (nodes, edges) in enumerate(cases):
            csv_path = os.path.join(td, secrets.token_hex(12) + ".csv")
            write_graph_csv(csv_path, nodes, edges, rng)
            expected = "REJECT" if graph_has_cycle(nodes, edges) else "ACCEPT"
            for executable in (EXE_PATH, rebuilt):
                actual = run_detector(executable, csv_path)
                assert actual == expected, (
                    f"Generated case {index} expected {expected}, got {actual} "
                    f"from {executable}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
