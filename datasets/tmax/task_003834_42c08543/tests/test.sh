#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import string
import subprocess
import pytest

AGENT_EXE = "/home/user/exposure_calculator"
MAKEFILE_PATH = "/app/libgraphcsv-1.2.0/Makefile"
FUZZ_RUNS = 100


def test_executable_exists():
    assert os.path.isfile(AGENT_EXE), f"Agent executable not found at {AGENT_EXE}"
    assert os.access(AGENT_EXE, os.X_OK), f"Agent file at {AGENT_EXE} is not executable"


def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile not found at {MAKEFILE_PATH}"
    with open(MAKEFILE_PATH, "r") as f:
        content = f.read()
    assert "-DMAX_RECURSION_DEPTH=3" not in content, "The deliberate perturbation in the Makefile was not fixed."


def test_executable_links_to_graphcsv():
    result = subprocess.run(["readelf", "-d", AGENT_EXE], capture_output=True, text=True)
    assert result.returncode == 0, f"Agent artifact is not a readable ELF executable: {result.stderr}"
    assert re.search(r"\(NEEDED\).*\[libgraphcsv\.so(?:\.[^]]*)?\]", result.stdout), (
        "Agent executable is not dynamically linked against libgraphcsv."
    )

    linked = subprocess.run(["ldd", AGENT_EXE], capture_output=True, text=True)
    assert linked.returncode == 0, f"Unable to inspect runtime library linkage: {linked.stderr}"
    graphcsv_lines = [line for line in linked.stdout.splitlines() if "libgraphcsv" in line]
    assert graphcsv_lines, "libgraphcsv is absent from the executable's runtime dependencies."
    assert all("not found" not in line for line in graphcsv_lines), "Linked libgraphcsv cannot be resolved at runtime."


def generate_random_node_id():
    prefix = ''.join(random.choices(string.ascii_uppercase, k=3))
    suffix = ''.join(random.choices(string.digits, k=3))
    return f"{prefix}_{suffix}"


def generate_fuzz_graph(num_nodes):
    nodes = list({generate_random_node_id() for _ in range(num_nodes)})
    num_nodes = len(nodes)
    edges = []
    types = ["ACCOUNT", "COMPANY", "OTHER"]

    for i in range(1, num_nodes):
        src = random.choice(nodes[:i])
        tgt = nodes[i]
        tgt_type = random.choice(types)
        weight = random.randint(1, 1000)
        edges.append((src, tgt, tgt_type, weight))

    for _ in range(num_nodes * 3):
        src = random.choice(nodes)
        tgt = random.choice(nodes)
        if src != tgt:
            tgt_type = random.choice(types)
            weight = random.randint(1, 1000)
            edges.append((src, tgt, tgt_type, weight))

    return nodes, edges


def int32(value):
    value &= 0xffffffff
    return value if value < 0x80000000 else value - 0x100000000


def expected_total(edges, start_node):
    adjacency = collections.defaultdict(list)
    for src, tgt, tgt_type, weight in edges:
        adjacency[src].append((tgt, tgt_type, weight))

    path = {start_node}

    def dfs(current, expected_type):
        total = 0
        required = "ACCOUNT" if expected_type == 0 else "COMPANY"
        for target, target_type, weight in adjacency.get(current, ()):
            if target_type == required and target not in path:
                path.add(target)
                subtotal = dfs(target, 1 - expected_type)
                path.remove(target)
                total = int32(total + weight + subtotal)
        return total

    return dfs(start_node, 0)


def run_agent(csv_path, start_node, timeout=5):
    try:
        result = subprocess.run(
            [AGENT_EXE, str(csv_path), start_node],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Agent executable timed out.")
    except Exception as exc:
        pytest.fail(f"Agent executable failed to run: {exc}")

    assert result.returncode == 0, (
        f"Agent executable returned non-zero exit code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )
    return result.stdout.strip()


def test_traversal_exceeds_original_three_hop_limit(tmp_path):
    edges = []
    for i in range(100):
        target_type = "ACCOUNT" if i % 2 == 0 else "COMPANY"
        edges.append((f"N{i}", f"N{i + 1}", target_type, 1))

    csv_path = tmp_path / "deep_graph.csv"
    with open(csv_path, "w") as f:
        for src, tgt, tgt_type, weight in edges:
            f.write(f"{src},{tgt},{tgt_type},{weight}\n")

    assert run_agent(csv_path, "N0") == "100"


@pytest.mark.parametrize("run_idx", range(FUZZ_RUNS))
def test_fuzz_equivalence(run_idx, tmp_path):
    random.seed(42 + run_idx)
    num_nodes = random.randint(50, 500)
    nodes, edges = generate_fuzz_graph(num_nodes)

    csv_path = tmp_path / f"fuzz_graph_{run_idx}.csv"
    with open(csv_path, "w") as f:
        for src, tgt, tgt_type, weight in edges:
            f.write(f"{src},{tgt},{tgt_type},{weight}\n")

    start_node = random.choice(nodes)
    expected = str(expected_total(edges, start_node))
    actual = run_agent(csv_path, start_node)

    assert actual == expected, (
        f"Output mismatch on fuzz run {run_idx}.\n"
        f"Start Node: {start_node}\n"
        f"Graph Size: {len(nodes)} nodes, {len(edges)} edges\n"
        f"Expected Output: '{expected}'\n"
        f"Agent Output: '{actual}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
