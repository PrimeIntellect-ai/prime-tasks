#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import stat
import string
import subprocess
import tempfile
import time

import pytest

CLI = "/home/user/cli.py"
LIB = "/home/user/libgraph.so"
ORACLE = "/app/graph_oracle"


def random_string(length):
    return ''.join(random.choices(string.ascii_letters, k=length))


def generate_random_dag(num_nodes):
    lines = []
    for _ in range(random.randint(0, 5)):
        lines.append(f"# {random_string(10)}")
    for _ in range(random.randint(0, 5)):
        lines.append("")

    nodes = [f"V{i}" for i in range(num_nodes)]
    weights = {node: random.randint(1, 1000) for node in nodes}
    for node in nodes:
        lines.append(f"N {node} {weights[node]}")

    num_edges = random.randint(0, num_nodes * 2)
    for _ in range(num_edges):
        if num_nodes < 2:
            break
        src_idx = random.randint(0, num_nodes - 2)
        dst_idx = random.randint(src_idx + 1, num_nodes - 1)
        lines.append(f"E {nodes[src_idx]} {nodes[dst_idx]}")

    random.shuffle(lines)
    return "\n".join(lines) + "\n"


def run_cmd(cmd, input_file, timeout=5):
    try:
        result = subprocess.run(
            cmd + [input_file], capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return None, "Timeout", -1


def expected_from_text(text):
    order = []
    index = {}
    weights = []
    edges = []

    def get_node(name):
        if name not in index:
            index[name] = len(order)
            order.append(name)
            weights.append(0)
            edges.append([])
        return index[name]

    for line in text.splitlines():
        if not line or line[0] in "#\n\r":
            continue
        parts = line.split()
        if line[0] == 'N' and len(parts) >= 3 and parts[0] == 'N':
            try:
                weight = int(parts[2], 10)
            except ValueError:
                continue
            weights[get_node(parts[1])] = weight
        elif line[0] == 'E' and len(parts) >= 3 and parts[0] == 'E':
            src = get_node(parts[1])
            dst = get_node(parts[2])
            edges[src].append(dst)

    indegree = [0] * len(order)
    for outgoing in edges:
        for dst in outgoing:
            indegree[dst] += 1

    queue = []
    dp = [0] * len(order)
    for i, degree in enumerate(indegree):
        if degree == 0:
            queue.append(i)
            dp[i] = weights[i]

    answer = 0
    head = 0
    while head < len(queue):
        src = queue[head]
        head += 1
        answer = max(answer, dp[src])
        for dst in edges[src]:
            candidate = dp[src] + weights[dst]
            if candidate > dp[dst]:
                dp[dst] = candidate
            indegree[dst] -= 1
            if indegree[dst] == 0:
                queue.append(dst)
    return answer


def load_library():
    lib = ctypes.CDLL(LIB)
    fn = lib.calculate_critical_path
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_long
    return lib, fn


def test_artifacts_and_exported_function():
    assert os.path.isfile(CLI), "Agent CLI script missing."
    assert os.path.isfile(LIB), "Agent shared library missing."
    assert stat.S_ISREG(os.stat(LIB).st_mode)

    elf = subprocess.run(
        ["readelf", "-h", LIB], capture_output=True, text=True, timeout=5
    )
    assert elf.returncode == 0, f"libgraph.so is not a readable ELF file: {elf.stderr}"
    assert "DYN (Shared object file)" in elf.stdout, "libgraph.so is not a shared object"

    symbols = subprocess.run(
        ["nm", "-D", "--defined-only", LIB], capture_output=True, text=True, timeout=5
    )
    assert symbols.returncode == 0, symbols.stderr
    assert any(line.split()[-1] == "calculate_critical_path"
               for line in symbols.stdout.splitlines() if line.split()), \
        "calculate_critical_path is not exported"

    load_library()


def test_library_direct_behavior_on_derived_cases():
    _, calculate = load_library()
    cases = [
        "",
        "# only a comment\n\n",
        "N A 7\n",
        "N A 4\nN B 9\nE A B\n",
        "E A B\nN B 8\nN A 3\n",
        "N A -5\nN B -2\nE A B\n",
        "N A 2\nN B 5\nN C 11\nE A C\nE B C\n",
        "N A 1\nN B 2\nE A B\nE A B\n",
        " ignored because it is indented\nN A 13\n",
    ]

    rng = random.Random(81723)
    for case_id in range(80):
        count = rng.randint(1, 180)
        lines = ["# generated test", ""]
        names = [f"D{case_id}_{i}" for i in range(count)]
        for name in names:
            lines.append(f"N {name} {rng.randint(-20, 1000)}")
        for _ in range(rng.randint(0, count * 3)):
            if count < 2:
                break
            src = rng.randrange(count - 1)
            dst = rng.randrange(src + 1, count)
            lines.append(f"E {names[src]} {names[dst]}")
        rng.shuffle(lines)
        cases.append("\n".join(lines) + "\n")

    for i, graph in enumerate(cases):
        expected = expected_from_text(graph)
        actual = calculate(graph.encode())
        assert actual == expected, (
            f"Direct library mismatch on case {i}: expected {expected}, got {actual}\n{graph}"
        )


def test_cli_declares_ctypes_and_argument_contract():
    source = open(CLI, "r", encoding="utf-8").read()
    tree = ast.parse(source, CLI)
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    assert imports_ctypes, "cli.py does not import ctypes"

    no_arg = subprocess.run(["python3", CLI], capture_output=True, text=True, timeout=5)
    assert no_arg.returncode != 0, "CLI must reject a missing positional argument"
    two_args = subprocess.run(
        ["python3", CLI, "/dev/null", "/dev/null"],
        capture_output=True, text=True, timeout=5
    )
    assert two_args.returncode != 0, "CLI must accept exactly one positional argument"


def test_cli_output_is_driven_by_shared_library():
    probe_c = "/tmp/libgraph_probe.c"
    probe_so = "/tmp/libgraph_probe.so"
    backup = "/tmp/libgraph_agent_backup.so"
    with open(probe_c, "w") as f:
        f.write("long calculate_critical_path(const char *graph_data) { (void)graph_data; return 424242; }\n")
    build = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", probe_c, "-o", probe_so],
        capture_output=True, text=True, timeout=10
    )
    assert build.returncode == 0, build.stderr

    with tempfile.NamedTemporaryFile("w", delete=False) as graph_file:
        graph_file.write("N A 7\n")
        graph_path = graph_file.name

    os.replace(LIB, backup)
    try:
        os.replace(probe_so, LIB)
        result = subprocess.run(
            ["python3", CLI, graph_path], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "MAX_PATH: 424242", (
            "CLI output is not obtained from calculate_critical_path in libgraph.so"
        )
    finally:
        if os.path.exists(LIB):
            os.unlink(LIB)
        os.replace(backup, LIB)
        os.unlink(graph_path)


def test_fuzz_equivalence():
    oracle_cmd = [ORACLE]
    agent_cmd = ["python3", CLI]

    assert os.path.exists(CLI), "Agent CLI script missing."
    assert os.path.exists(LIB), "Agent shared library missing."

    random.seed(42)
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(200):
            num_nodes = random.randint(10, 1000)
            dag_str = generate_random_dag(num_nodes)
            input_file = os.path.join(tmpdir, f"graph_{i}.txt")
            with open(input_file, "w") as f:
                f.write(dag_str)

            oracle_out, oracle_err, oracle_rc = run_cmd(oracle_cmd, input_file)
            agent_out, agent_err, agent_rc = run_cmd(agent_cmd, input_file)

            assert oracle_rc == 0, f"Oracle failed on input {i}: {oracle_err}"
            assert agent_rc == 0, f"Agent failed on input {i}: {agent_err}\nInput:\n{dag_str}"
            assert oracle_out == agent_out, (
                f"Mismatch on iteration {i} (nodes: {num_nodes})\n"
                f"Oracle output: {oracle_out}\n"
                f"Agent output:  {agent_out}\n"
                f"Input graph:\n{dag_str}"
            )


def test_library_outperforms_legacy_on_stress_graph():
    _, calculate = load_library()
    count = 9000
    lines = [f"N P{i} 1" for i in range(count)]
    lines.extend(f"E P{i} P{i+1}" for i in range(count - 1))
    graph = ("\n".join(lines) + "\n").encode()

    with tempfile.NamedTemporaryFile("wb", delete=False) as f:
        f.write(graph)
        path = f.name
    try:
        assert calculate(graph) == count
        warmup = subprocess.run([ORACLE, path], capture_output=True, text=True, timeout=10)
        assert warmup.returncode == 0
        assert warmup.stdout.strip() == f"MAX_PATH: {count}"

        start = time.perf_counter()
        for _ in range(3):
            assert calculate(graph) == count
        library_time = time.perf_counter() - start

        start = time.perf_counter()
        for _ in range(3):
            result = subprocess.run([ORACLE, path], capture_output=True, text=True, timeout=10)
            assert result.returncode == 0
            assert result.stdout.strip() == f"MAX_PATH: {count}"
        oracle_time = time.perf_counter() - start

        assert library_time < oracle_time, (
            f"Shared library was not faster than the legacy implementation: "
            f"library={library_time:.4f}s oracle={oracle_time:.4f}s"
        )
    finally:
        os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
