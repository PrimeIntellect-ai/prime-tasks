#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess


def parse_features(data, expected_nodes):
    lines = data.strip().splitlines()
    assert len(lines) == expected_nodes, f"Expected {expected_nodes} output lines, got {len(lines)}."
    result = {}
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Expected 2 columns in line: '{line}'"
        node = int(parts[0])
        value = float(parts[1])
        assert node not in result, f"Duplicate node {node} in output."
        assert math.isfinite(value), f"Non-finite value for node {node}: {parts[1]}"
        result[node] = value
    assert set(result) == set(range(expected_nodes)), "Output does not contain each expected node exactly once."
    return result


def expected_features(num_nodes, edges):
    adj = [[] for _ in range(num_nodes)]
    degree = [0] * num_nodes
    for u, v in edges:
        adj[u].append(v)
        degree[u] += 1
    return {
        node: (sum(degree[v] for v in adj[node]) / degree[node] if degree[node] else 0.0)
        for node in range(num_nodes)
    }


def run_extractor(path, num_nodes, edges):
    graph_path = f"/tmp/graph-{secrets.token_hex(12)}.txt"
    try:
        with open(graph_path, "w") as f:
            f.write(f"{num_nodes}\n")
            for u, v in edges:
                f.write(f"{u} {v}\n")
        proc = subprocess.run([path, graph_path], text=True, capture_output=True, timeout=10)
        assert proc.returncode == 0, f"{path} failed: {proc.stderr}"
        return proc.stdout
    finally:
        if os.path.exists(graph_path):
            os.remove(graph_path)


def assert_extractor_case(path, num_nodes, edges):
    actual = parse_features(run_extractor(path, num_nodes, edges), num_nodes)
    expected = expected_features(num_nodes, edges)
    for node in range(num_nodes):
        assert math.isclose(actual[node], expected[node], rel_tol=1e-5, abs_tol=1e-8), (
            f"Incorrect mean neighbor degree for node {node}: "
            f"expected {expected[node]}, got {actual[node]}"
        )


def test_extract_executable_exists():
    path = "/home/user/extract"
    assert os.path.isfile(path), f"Executable {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_fixed_source_and_executable_behavior():
    source = "/home/user/extract.cpp"
    rebuilt = f"/tmp/extract-rebuilt-{secrets.token_hex(12)}"
    assert os.path.isfile(source), f"Source {source} is missing."
    compile_proc = subprocess.run(
        ["g++", "-std=c++17", "-O2", source, "-o", rebuilt],
        text=True, capture_output=True, timeout=30
    )
    assert compile_proc.returncode == 0, f"The repaired source does not compile: {compile_proc.stderr}"

    rng = secrets.SystemRandom()
    cases = [
        (1, []),
        (6, [(0, 1), (0, 2), (1, 2), (2, 0), (3, 3)]),
    ]
    for _ in range(4):
        n = rng.randint(7, 24)
        edges = []
        for u in range(n - 2):
            for v in range(n):
                if rng.random() < 0.17:
                    edges.append((u, v))
            if rng.random() < 0.35:
                edges.append((u, rng.randrange(n)))
        cases.append((n, edges))

    try:
        for n, edges in cases:
            assert_extractor_case(rebuilt, n, edges)
            assert_extractor_case("/home/user/extract", n, edges)
    finally:
        if os.path.exists(rebuilt):
            os.remove(rebuilt)


def test_features_txt_exists_and_correct():
    path = "/home/user/features.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip().split("\n")

    assert len(content) == 10, f"Expected 10 lines in {path}, got {len(content)}."

    # Check for NaNs
    for line in content:
        parts = line.split()
        assert len(parts) == 2, f"Expected 2 columns in line: '{line}'"
        assert parts[1].lower() != "nan", f"Found NaN in {path}, the bug was not fixed correctly."

    # Isolated nodes 8 and 9 should have mean neighbor degree 0
    node_8 = [line for line in content if line.startswith("8 ")]
    node_9 = [line for line in content if line.startswith("9 ")]

    assert node_8, "Node 8 missing from features.txt"
    assert node_9, "Node 9 missing from features.txt"

    assert float(node_8[0].split()[1]) == 0.0, "Node 8 should have mean neighbor degree 0."
    assert float(node_9[0].split()[1]) == 0.0, "Node 9 should have mean neighbor degree 0."

    with open(path, "rb") as f:
        saved = f.read()
    proc = subprocess.run(
        ["/home/user/extract", "/home/user/graph.txt"],
        capture_output=True, timeout=10
    )
    assert proc.returncode == 0, f"extract failed on graph.txt: {proc.stderr.decode(errors='replace')}"
    assert saved == proc.stdout, "features.txt is not the raw output produced by extract on graph.txt."
    actual = parse_features(proc.stdout.decode(), 10)
    edges = [(0,1),(1,0),(1,2),(2,1),(3,4),(4,3),(4,5),(5,4),(6,7),(7,6)]
    expected = expected_features(10, edges)
    for node in range(10):
        assert math.isclose(actual[node], expected[node], rel_tol=1e-5, abs_tol=1e-8)


def test_density_sh_exists():
    path = "/home/user/density.sh"
    assert os.path.isfile(path), f"Script {path} is missing."
    # It should be executable, but we can just check if it exists and has content
    st = os.stat(path)
    assert st.st_size > 0, f"Script {path} is empty."


def test_density_log_correct():
    path = "/home/user/density.log"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()

    expected = "Bin 0: 2\nBin 1: 4\nBin 2: 4\nBin 3: 0"
    assert content == expected, f"Content of {path} does not match expected output.\nExpected:\n{expected}\nActual:\n{content}"


def test_density_script_executes_and_bins_dynamic_input():
    features_path = "/home/user/features.txt"
    log_path = "/home/user/density.log"
    with open(features_path, "rb") as f:
        old_features = f.read()
    old_log = None
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            old_log = f.read()

    rng = secrets.SystemRandom()
    values = []
    counts = []
    choices = [
        [0.0],
        [0.125, 0.5, 0.999, 1.0],
        [1.001, 1.25, 1.75, 2.0],
        [2.001, 2.5, 3.75, 9.0],
    ]
    for bin_values in choices:
        count = rng.randint(2, 9)
        counts.append(count)
        values.extend(rng.choice(bin_values) for _ in range(count))
    rng.shuffle(values)

    try:
        with open(features_path, "w") as f:
            for node, value in enumerate(values):
                f.write(f"{node} {value:.6f}\n")
        if os.path.exists(log_path):
            os.remove(log_path)
        proc = subprocess.run(
            ["bash", "/home/user/density.sh"],
            cwd="/home/user", text=True, capture_output=True, timeout=10
        )
        assert proc.returncode == 0, f"density.sh failed: {proc.stderr}"
        assert os.path.isfile(log_path), "density.sh did not create /home/user/density.log."
        with open(log_path, "r") as f:
            actual = f.read().strip()
        expected = "\n".join(f"Bin {i}: {counts[i]}" for i in range(4))
        assert actual == expected, f"density.sh binned dynamic input incorrectly.\nExpected:\n{expected}\nActual:\n{actual}"
    finally:
        with open(features_path, "wb") as f:
            f.write(old_features)
        if old_log is None:
            if os.path.exists(log_path):
                os.remove(log_path)
        else:
            with open(log_path, "wb") as f:
                f.write(old_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
