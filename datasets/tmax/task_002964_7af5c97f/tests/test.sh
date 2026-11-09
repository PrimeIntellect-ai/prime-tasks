#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import py_compile
import pytest

ORACLE_PATH = "/app/legacy_matcher"
AGENT_PATH = "/home/user/new_matcher.py"


def generate_test_case(seed):
    random.seed(seed)

    N = random.randint(10, 50)
    M = random.randint(20, 150)
    Q = random.randint(5, 20)
    edge_types = ["REL_A", "REL_B", "REL_C", "REL_D"]

    edges = []
    for _ in range(M):
        u = random.randint(0, N - 2)
        v = random.randint(u + 1, N - 1)
        weight = round(random.uniform(0.1, 5.0), 2)
        etype = random.choice(edge_types)
        edges.append(f"{u} {v} {weight:.2f} {etype}")

    queries = []
    for _ in range(Q):
        start = random.randint(0, N - 2)
        end = random.randint(start + 1, N - 1)
        seq_len = random.randint(1, 4)
        seq = ",".join(random.choices(edge_types, k=seq_len))
        queries.append(f"{start} {end} {seq}")

    return "\n".join([f"{N} {M} {Q}"] + edges + queries) + "\n"


def derived_output(input_data):
    lines = input_data.splitlines()
    n, m, q = map(int, lines[0].split())
    graph = [[] for _ in range(n)]

    for line in lines[1:1 + m]:
        u, v, weight, edge_type = line.split()
        graph[int(u)].append((int(v), float(weight), edge_type))

    output = []
    for line in lines[1 + m:1 + m + q]:
        start, end, sequence_text = line.split()
        start, end = int(start), int(end)
        sequence = sequence_text.split(",")

        def dfs(node, sequence_index):
            if sequence_index == len(sequence):
                return 1.0 if node == end else 0.0

            total = 0.0
            for destination, weight, edge_type in graph[node]:
                if edge_type == sequence[sequence_index]:
                    path_score = dfs(destination, sequence_index + 1)
                    if path_score > 0:
                        total += weight * path_score
            return total

        output.append(f"{dfs(start, 0):.4f}")

    return "\n".join(output) + "\n"


def run_program(cmd, input_data):
    try:
        result = subprocess.run(
            cmd,
            input=input_data,
            text=True,
            capture_output=True,
            timeout=5,
            check=True,
        )
        return result.stdout
    except subprocess.CalledProcessError as exc:
        return f"ERROR: {exc.stderr}"
    except subprocess.TimeoutExpired:
        return "TIMEOUT"


def test_fuzz_equivalence_without_oracle_access():
    assert os.path.isfile(ORACLE_PATH), f"Oracle {ORACLE_PATH} not found."
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} not found."
    assert not os.path.islink(AGENT_PATH), "Agent submission must be a Python file, not a symlink."
    py_compile.compile(AGENT_PATH, doraise=True)

    with open(ORACLE_PATH, "rb") as oracle_file, open(AGENT_PATH, "rb") as agent_file:
        assert oracle_file.read() != agent_file.read(), "Submission is byte-identical to the oracle."

    inputs = [generate_test_case(1000 + i) for i in range(100)]
    inputs.extend([
        "5 6 5\n0 1 2.00 A\n0 2 3.00 A\n1 3 4.00 B\n2 3 5.00 B\n3 4 0.50 C\n1 4 7.00 C\n0 3 A,B\n0 4 A,B,C\n0 4 A,C\n2 4 B,C\n4 4 A\n",
        "4 4 4\n0 1 -2.00 X\n0 2 3.00 X\n1 3 4.00 Y\n2 3 5.00 Y\n0 3 X,Y\n0 2 X\n1 3 Y\n3 0 X\n",
    ])

    # Obtain the original verifier's oracle results first, then permanently remove
    # the binary before the submitted program is ever started. A forwarding wrapper
    # therefore cannot use /app/legacy_matcher during verification.
    oracle_outputs = [run_program([ORACLE_PATH], data) for data in inputs]
    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH)

    for index, (input_data, oracle_out) in enumerate(zip(inputs, oracle_outputs)):
        expected_out = derived_output(input_data)
        assert oracle_out == expected_out, (
            f"Internal expected result disagrees with the legacy oracle on case {index}.\n"
            f"Input:\n{input_data}\nOracle:\n{oracle_out}\nDerived:\n{expected_out}"
        )

        agent_out = run_program(["python3", AGENT_PATH], input_data)
        assert agent_out == oracle_out, (
            f"Mismatch on test case {index}!\n\n"
            f"Input Data:\n{input_data}\n"
            f"Oracle Output:\n{oracle_out}\n"
            f"Agent Output:\n{agent_out}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
