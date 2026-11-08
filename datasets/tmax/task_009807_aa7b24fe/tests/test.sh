#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess
import uuid


def read_signal(path):
    assert os.path.isfile(path), f"{path} is missing"
    with open(path, "r") as f:
        lines = f.read().strip().splitlines()
    assert len(lines) == 100, f"Expected exactly 100 lines in {path}, got {len(lines)}"
    try:
        values = [float(line) for line in lines]
    except ValueError as exc:
        raise AssertionError(f"Could not parse {path} as numeric signal values") from exc
    assert all(math.isfinite(v) for v in values), f"Non-finite value found in {path}"
    return values


def reference_signal(edges):
    num_nodes = 5
    adj = [[0.0] * num_nodes for _ in range(num_nodes)]
    deg = [0.0] * num_nodes
    for a, b in edges:
        adj[a][b] = 1.0
        adj[b][a] = 1.0
        deg[a] += 1.0
        deg[b] += 1.0

    state = [1.0, 0.0, 0.0, 0.0, 0.0]
    signal = []
    for _ in range(100):
        signal.append(state[0])
        next_state = [0.0] * num_nodes
        for i in range(num_nodes):
            for j in range(num_nodes):
                next_state[j] += state[i] * (adj[i][j] / deg[i])
        state = next_state
    return signal


def write_graph(path, edges):
    with open(path, "w") as f:
        for a, b in sorted(edges):
            f.write(f"{a} {b}\n")


def parse_graph(data):
    edges = []
    for line in data.decode().splitlines():
        if line.strip():
            a, b = map(int, line.split())
            edges.append((min(a, b), max(a, b)))
    return edges


def assert_matches_reference(actual, expected):
    assert len(actual) == len(expected) == 100
    for step, (got, want) in enumerate(zip(actual, expected), start=1):
        assert abs(got - want) <= 0.000051, (
            f"Signal mismatch at line {step}: got {got}, expected {want:.4f}"
        )


def random_connected_graph(rng):
    order = list(range(5))
    rng.shuffle(order)
    edges = set()
    for i in range(1, 5):
        a = order[i]
        b = order[rng.randrange(i)]
        edges.add((min(a, b), max(a, b)))
    for a in range(5):
        for b in range(a + 1, 5):
            if (a, b) not in edges and rng.random() < 0.45:
                edges.add((a, b))
    return edges


def test_complete_solution():
    project = "/home/user/sim_project"
    main_rs_path = project + "/src/main.rs"
    signal_path = project + "/signal.txt"
    molecule_path = "/home/user/molecule.txt"
    script_path = "/home/user/run_regression.sh"
    result_path = "/home/user/regression_result.txt"

    assert os.path.isfile(main_rs_path), f"{main_rs_path} is missing"
    with open(main_rs_path, "r") as f:
        content = f.read()
    assert "adj[i][j] * 1.5" not in content, "The bug 'adj[i][j] * 1.5' is still present in main.rs"
    assert "deg[i]" in content, "The fix using 'deg[i]' is not present in main.rs"

    assert os.path.isfile(script_path), f"{script_path} is missing"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    with open(main_rs_path, "rb") as f:
        original_source = f.read()
    with open(molecule_path, "rb") as f:
        original_molecule = f.read()

    marker_path = None
    try:
        # Execute the submitted Rust project against graphs generated at verification
        # time and compare every output line with an independently computed walk.
        rng = random.SystemRandom()
        for _ in range(4):
            edges = random_connected_graph(rng)
            write_graph(molecule_path, edges)
            if os.path.exists(signal_path):
                os.remove(signal_path)
            run = subprocess.run(
                ["cargo", "run", "--quiet"],
                cwd=project,
                capture_output=True,
                text=True,
                timeout=90,
            )
            assert run.returncode == 0, (
                f"Rust project failed to build or run: {run.stderr[-2000:]}"
            )
            actual = read_signal(signal_path)
            assert_matches_reference(actual, reference_signal(edges))

        # Restore the specified input and instrument main with a random marker. By
        # deleting target first, the regression script must compile and execute the
        # current Rust project rather than merely manufacturing PASS and signal.txt.
        with open(molecule_path, "wb") as f:
            f.write(original_molecule)
        nonce = uuid.uuid4().hex
        marker_path = f"/tmp/sim_project_executed_{nonce}"
        source_text = original_source.decode()
        match = re.search(r"fn\s+main\s*\(\s*\)\s*\{", source_text)
        assert match is not None, "Could not locate the Rust main function"
        marker_code = (
            f'\n    let _verifier_marker = std::fs::write("{marker_path}", "{nonce}");'
        )
        instrumented = source_text[:match.end()] + marker_code + source_text[match.end():]
        with open(main_rs_path, "w") as f:
            f.write(instrumented)

        shutil.rmtree(project + "/target", ignore_errors=True)
        for path in (signal_path, result_path, marker_path):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            [script_path], cwd="/home/user", capture_output=True, text=True, timeout=120
        )
        assert result.returncode == 0, (
            f"run_regression.sh exited with code {result.returncode}, expected 0"
        )
        assert os.path.isfile(marker_path), (
            "run_regression.sh did not execute the freshly compiled Rust project"
        )
        with open(marker_path, "r") as f:
            assert f.read() == nonce, "Invalid Rust execution marker"

        assert os.path.isfile(result_path), f"{result_path} was not created by the script"
        with open(result_path, "r") as f:
            result_content = f.read().strip()
        assert result_content == "PASS", f"Expected 'PASS' in {result_path}, got '{result_content}'"

        values = read_signal(signal_path)
        assert_matches_reference(values, reference_signal(parse_graph(original_molecule)))
        last_val = values[-1]
        assert 0.1 <= last_val <= 0.5, (
            f"Expected last signal value to be between 0.1 and 0.5, got {last_val}"
        )
    finally:
        with open(main_rs_path, "wb") as f:
            f.write(original_source)
        with open(molecule_path, "wb") as f:
            f.write(original_molecule)
        shutil.rmtree(project + "/target", ignore_errors=True)
        if marker_path and os.path.exists(marker_path):
            os.remove(marker_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
