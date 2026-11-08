#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import random
import tempfile
import pytest

ORACLE_PATH = "/app/bin/dep_solver_oracle"
AGENT_PATH = "/home/user/workspace/dep_solver"
LIB_PATH = "/home/user/workspace/libdepsolver.so"
SCHEMA_PATH = "/app/schema/deps.proto"

@pytest.fixture(scope="session", autouse=True)
def compile_protobuf():
    assert os.path.exists(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable {AGENT_PATH} is not executable"
    assert os.path.exists(LIB_PATH), f"Shared library not found at {LIB_PATH}"

    # Compile protobuf to python so we can generate test inputs
    proto_out = tempfile.mkdtemp()
    subprocess.check_call([
        "protoc",
        f"--python_out={proto_out}",
        "--proto_path=/app/schema",
        SCHEMA_PATH
    ])
    sys.path.insert(0, proto_out)

def generate_graph_proto(seed, is_dag):
    import deps_pb2
    random.seed(seed)

    graph = deps_pb2.Graph()
    num_nodes = random.randint(5, 50)

    # Generate unique node IDs
    node_ids = random.sample(range(1, 1001), num_nodes)

    nodes_dict = {}
    for nid in node_ids:
        node = graph.nodes.add()
        node.id = nid
        nodes_dict[nid] = node

    if is_dag:
        # To ensure DAG, only allow dependencies from earlier in a topological sort order
        for i in range(1, num_nodes):
            num_deps = random.randint(0, min(3, i))
            deps = random.sample(node_ids[:i], num_deps)
            nodes_dict[node_ids[i]].dependencies.extend(deps)
    else:
        # Guarantee a cycle
        cycle_len = random.randint(2, num_nodes)
        cycle_nodes = random.sample(node_ids, cycle_len)
        for i in range(cycle_len):
            u = cycle_nodes[i]
            v = cycle_nodes[(i + 1) % cycle_len]
            # u depends on v
            nodes_dict[u].dependencies.append(v)

        # Add some random edges
        for i in range(num_nodes):
            num_deps = random.randint(0, 2)
            deps = random.sample(node_ids, num_deps)
            for d in deps:
                if d not in nodes_dict[node_ids[i]].dependencies:
                    nodes_dict[node_ids[i]].dependencies.append(d)

    return graph.SerializeToString()

def run_binary(binary_path, input_file):
    result = subprocess.run(
        [binary_path, input_file],
        capture_output=True,
        text=True
    )
    return result.stdout.strip()

@pytest.mark.parametrize("seed", range(200))
def test_fuzz_equivalence(seed):
    is_dag = seed < 100
    proto_data = generate_graph_proto(seed, is_dag)

    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        tmp.write(proto_data)
        tmp_path = tmp.name

    try:
        oracle_out = run_binary(ORACLE_PATH, tmp_path)
        agent_out = run_binary(AGENT_PATH, tmp_path)

        assert oracle_out == agent_out, (
            f"Output mismatch on seed {seed} (is_dag={is_dag}).\n"
            f"Input file path: {tmp_path} (deleted after test unless running manually)\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
    finally:
        os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
