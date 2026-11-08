#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
import pytest

ORACLE_BIN = "/app/dataset_analyzer"
AGENT_BIN = "/home/user/solution"
AGENT_SRC = "/home/user/solution.cpp"
REBUILT_BIN = "/tmp/solution-rebuilt"


def generate_random_graph_and_queries(seed):
    random.seed(seed)

    V = random.randint(10, 1000)
    max_edges = min(V * (V - 1), 10000)
    E = random.randint(min(V, max_edges), max_edges)

    edges = set()
    while len(edges) < E:
        u = random.randint(0, V - 1)
        v = random.randint(0, V - 1)
        if u != v:
            edges.add((u, v))

    Q = random.randint(50, 500)
    queries = []
    for _ in range(Q):
        q_type = random.choice(["CENTRALITY", "CO_CITE", "PATTERN"])
        if q_type == "CENTRALITY":
            queries.append(f"CENTRALITY {random.randint(0, V - 1)}")
        elif q_type == "CO_CITE":
            queries.append(
                f"CO_CITE {random.randint(0, V - 1)} {random.randint(0, V - 1)}"
            )
        else:
            queries.append(f"PATTERN {random.randint(0, V - 1)}")

    input_lines = [f"{V} {E}"]
    input_lines.extend(f"{u} {v}" for u, v in edges)
    input_lines.append(str(Q))
    input_lines.extend(queries)
    return "\n".join(input_lines) + "\n"


def copy_runtime_dependencies(binary, root):
    proc = subprocess.run(["ldd", binary], text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        return

    paths = set(re.findall(r"(?<!\S)(/[^\s()]+)", proc.stdout))
    for path in paths:
        if not os.path.isfile(path):
            continue
        destination = os.path.join(root, path.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(path, destination, follow_symlinks=True)


def make_chroot(candidates):
    root = tempfile.mkdtemp(prefix="solution-chroot-")
    os.chmod(root, 0o755)
    for name, binary in candidates.items():
        destination = os.path.join(root, name)
        shutil.copy2(binary, destination)
        os.chmod(destination, 0o755)
        copy_runtime_dependencies(binary, root)
    return root


def run_isolated(root, name, input_data):
    return subprocess.run(
        ["chroot", "--userspec=65534:65534", root, f"/{name}"],
        input=input_data,
        text=True,
        capture_output=True,
        check=False,
        timeout=15,
    )


def test_agent_binary_exists_and_source_rebuilds():
    assert os.path.exists(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.path.isfile(AGENT_BIN), f"Path {AGENT_BIN} is not a file"
    assert not os.path.islink(AGENT_BIN), f"Path {AGENT_BIN} must not be a symlink"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"

    assert os.path.exists(AGENT_SRC), f"Source file not found at {AGENT_SRC}"
    assert os.path.isfile(AGENT_SRC), f"Path {AGENT_SRC} is not a file"
    assert not os.path.islink(AGENT_SRC), f"Path {AGENT_SRC} must not be a symlink"
    assert stat.S_ISREG(os.stat(AGENT_SRC).st_mode), f"Path {AGENT_SRC} is not a regular file"

    compile_proc = subprocess.run(
        ["g++", "-O3", "-std=c++17", AGENT_SRC, "-o", REBUILT_BIN],
        text=True,
        capture_output=True,
        check=False,
        timeout=60,
    )
    assert compile_proc.returncode == 0, f"solution.cpp failed to compile: {compile_proc.stderr}"
    assert os.path.isfile(REBUILT_BIN) and os.access(REBUILT_BIN, os.X_OK)

    assert not filecmp.cmp(AGENT_BIN, ORACLE_BIN, shallow=False), \
        "Submitted executable is byte-identical to the oracle"
    assert not filecmp.cmp(REBUILT_BIN, ORACLE_BIN, shallow=False), \
        "Executable rebuilt from solution.cpp is byte-identical to the oracle"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BIN), f"Oracle binary missing at {ORACLE_BIN}"
    assert os.path.exists(REBUILT_BIN), "Rebuilt solution binary is missing"

    cases = []
    for i in range(100):
        input_data = generate_random_graph_and_queries(seed=42 + i)
        oracle_proc = subprocess.run(
            [ORACLE_BIN],
            input=input_data,
            text=True,
            capture_output=True,
            check=False,
            timeout=15,
        )
        assert oracle_proc.returncode == 0, \
            f"Oracle binary failed on iteration {i}: {oracle_proc.stderr}"
        cases.append((input_data, oracle_proc.stdout.strip()))

    # Neither executable can see /app, /home, or any pre-created forwarding target.
    root = make_chroot({"submitted": AGENT_BIN, "rebuilt": REBUILT_BIN})
    try:
        for candidate in ("submitted", "rebuilt"):
            for i, (input_data, expected) in enumerate(cases):
                try:
                    proc = run_isolated(root, candidate, input_data)
                except subprocess.TimeoutExpired:
                    pytest.fail(f"{candidate} timed out on iteration {i}")

                if proc.returncode != 0:
                    pytest.fail(
                        f"{candidate} crashed/failed on iteration {i}. "
                        f"Stderr: {proc.stderr}"
                    )

                actual = proc.stdout.strip()
                if actual != expected:
                    pytest.fail(
                        f"Output mismatch for {candidate} on iteration {i}.\n"
                        f"--- Input (first 10 lines) ---\n"
                        f"{chr(10).join(input_data.splitlines()[:10])}\n...\n"
                        f"--- Expected Output (Oracle) ---\n{expected}\n"
                        f"--- Actual Output (Agent) ---\n{actual}"
                    )
    finally:
        shutil.rmtree(root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
