#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import random
import string
import subprocess
import pytest

ORACLE_PATH = "/app/dataset_lineage_oracle"
PROJECT_PATH = "/home/user/lineage_solver"
AGENT_PATH = "/home/user/lineage_solver/target/release/lineage_solver"
FUZZ_N = 200


def generate_random_graph():
    num_nodes = random.randint(10, 100)

    def random_id():
        length = random.randint(2, 5)
        return "".join(random.choices(string.ascii_letters + string.digits, k=length))

    nodes = list(set(random_id() for _ in range(num_nodes)))
    while len(nodes) < num_nodes:
        nodes.append(random_id())
        nodes = list(set(nodes))

    graph = {}
    for node in nodes:
        num_deps = random.randint(0, min(10, len(nodes) - 1))
        deps = {}
        target_nodes = random.sample([n for n in nodes if n != node], num_deps)
        for target in target_nodes:
            deps[target] = random.randint(1, 100)
        graph[node] = {"deps": deps}

    return graph, random.choice(nodes), random.choice(nodes)


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected an ELF executable at {path}"


def test_fuzz_equivalence():
    # Preserve the original final-artifact assertions.
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable at {AGENT_PATH}"
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"

    # The requested artifact must be a Rust project and not a shell forwarding script
    # or a byte-for-byte copy of the reference executable.
    assert os.path.isfile(os.path.join(PROJECT_PATH, "Cargo.toml")), "Cargo.toml is missing"
    assert os.path.isfile(os.path.join(PROJECT_PATH, "src", "main.rs")), "src/main.rs is missing"
    assert_elf(AGENT_PATH)
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), \
        "Submission is byte-identical to the oracle"

    random.seed(42)
    cases = []

    # Obtain all expected outputs before making the oracle unavailable to the
    # submitted program.
    for i in range(FUZZ_N):
        graph, source, target = generate_random_graph()
        input_json = json.dumps(graph)
        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH, source, target],
                input=input_json,
                text=True,
                capture_output=True,
                timeout=5,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {source} -> {target}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {source} -> {target}.")
        cases.append((i, source, target, input_json, oracle_proc.stdout))

    os.unlink(ORACLE_PATH)

    # Rebuild from the submitted Rust source after removing the oracle, so the
    # tested executable cannot merely be a script left at the requested path.
    try:
        subprocess.run(
            ["cargo", "clean", "--manifest-path", os.path.join(PROJECT_PATH, "Cargo.toml")],
            text=True,
            capture_output=True,
            timeout=60,
            check=True,
        )
        build_proc = subprocess.run(
            ["cargo", "build", "--release", "--offline", "--manifest-path", os.path.join(PROJECT_PATH, "Cargo.toml")],
            text=True,
            capture_output=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Rust release build timed out")

    if build_proc.returncode != 0:
        pytest.fail(f"Rust release build failed. Stderr: {build_proc.stderr}")

    assert os.path.exists(AGENT_PATH), f"Agent binary not found after release build at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable after release build at {AGENT_PATH}"
    assert_elf(AGENT_PATH)

    for i, source, target, input_json, oracle_out in cases:
        try:
            agent_proc = subprocess.run(
                [AGENT_PATH, source, target],
                input=input_json,
                text=True,
                capture_output=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on input {source} -> {target}.")

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent failed with return code {agent_proc.returncode}. Stderr: {agent_proc.stderr}")

        if agent_proc.stdout != oracle_out:
            pytest.fail(
                f"Mismatch on iteration {i}!\n"
                f"Source: {source}, Target: {target}\n"
                f"Input JSON: {input_json}\n"
                f"Oracle output: {repr(oracle_out)}\n"
                f"Agent output: {repr(agent_proc.stdout)}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
