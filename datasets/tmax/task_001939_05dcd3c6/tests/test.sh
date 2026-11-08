#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import importlib
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import grpc
import pytest
from google.protobuf.message import Message

PROJECT = Path("/home/user/math_dag")


def stop_existing_servers():
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            argv = (entry / "cmdline").read_bytes().split(b"\0")
            args = [item.decode(errors="ignore") for item in argv if item]
            if args and any(os.path.basename(arg) == "server.py" for arg in args[1:]):
                os.kill(int(entry.name), signal.SIGTERM)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)


def derived_instructions(nodes):
    node_ids = {node_id for node_id, _, _ in nodes}
    assert len(node_ids) == len(nodes)
    adjacency = {node_id: [] for node_id in node_ids}
    indegree = {node_id: 0 for node_id in node_ids}
    operations = {node_id: operation for node_id, operation, _ in nodes}

    for node_id, _, dependencies in nodes:
        for dependency in dependencies:
            assert dependency in node_ids
            adjacency[dependency].append(node_id)
            indegree[node_id] += 1

    ready = [node_id for node_id, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    ordered = []
    while ready:
        current = heapq.heappop(ready)
        ordered.append(current)
        for neighbor in adjacency[current]:
            indegree[neighbor] -= 1
            if indegree[neighbor] == 0:
                heapq.heappush(ready, neighbor)

    if len(ordered) != len(nodes):
        return None
    return [f"EXEC {operations[node_id]} {node_id}" for node_id in ordered]


@pytest.fixture(scope="session", autouse=True)
def built_running_project():
    pb2_path = PROJECT / "math_graph_pb2.py"
    grpc_pb2_path = PROJECT / "math_graph_pb2_grpc.py"

    # Ensure the submitted build target itself regenerates both artifacts.
    pb2_path.unlink(missing_ok=True)
    grpc_pb2_path.unlink(missing_ok=True)
    result = subprocess.run(
        ["make", "build"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, f"make build failed:\n{result.stdout}"
    assert pb2_path.is_file(), f"Build artifact missing: {pb2_path}. Did you run make build?"
    assert grpc_pb2_path.is_file(), f"Build artifact missing: {grpc_pb2_path}. Did you fix the Makefile and run make build?"

    sys.path.insert(0, str(PROJECT))
    importlib.invalidate_caches()
    pb2 = importlib.import_module("math_graph_pb2")
    pb2_grpc = importlib.import_module("math_graph_pb2_grpc")

    # Confirm these are usable protobuf/gRPC stubs for the supplied schema.
    assert issubclass(pb2.Node, Message)
    assert issubclass(pb2.Graph, Message)
    assert issubclass(pb2.InstructionSet, Message)
    assert "ExecutionEngine" in pb2.DESCRIPTOR.services_by_name
    assert hasattr(pb2_grpc, "ExecutionEngineStub")
    assert hasattr(pb2_grpc, "ExecutionEngineServicer")
    assert callable(pb2_grpc.add_ExecutionEngineServicer_to_server)

    stop_existing_servers()
    server = subprocess.Popen(
        [sys.executable, "server.py"], cwd=PROJECT,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=8)
        assert server.poll() is None, "server.py exited before serving requests"

        # Exercise the provided client against the submitted running server.
        client = subprocess.run(
            [sys.executable, "client.py"], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
        )
        assert client.returncode == 0, f"client.py failed:\n{client.stdout}"
        yield {"pb2": pb2, "pb2_grpc": pb2_grpc, "channel": channel}
    finally:
        channel.close()
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=3)


def test_build_artifacts_exist():
    pb2_path = "/home/user/math_dag/math_graph_pb2.py"
    grpc_pb2_path = "/home/user/math_dag/math_graph_pb2_grpc.py"

    assert os.path.isfile(pb2_path), f"Build artifact missing: {pb2_path}. Did you run make build?"
    assert os.path.isfile(grpc_pb2_path), f"Build artifact missing: {grpc_pb2_path}. Did you fix the Makefile and run make build?"


def test_makefile_fixed():
    makefile_path = "/home/user/math_dag/Makefile"
    assert os.path.isfile(makefile_path), f"{makefile_path} is missing"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "--grpc_python_out" in content, "Makefile does not seem to contain the fix for generating gRPC stubs."


def test_server_py_fixed():
    server_path = "/home/user/math_dag/server.py"
    assert os.path.isfile(server_path), f"{server_path} is missing"
    with open(server_path, "r") as f:
        content = f.read()
    assert "in_degree[curr] -= 1" not in content, "server.py still contains the bug 'in_degree[curr] -= 1'."


def test_compile_varied_dags(built_running_project):
    pb2 = built_running_project["pb2"]
    stub = built_running_project["pb2_grpc"].ExecutionEngineStub(
        built_running_project["channel"]
    )

    cases = [
        [
            ("finish", "STORE", ["left", "right"]),
            ("right", "DIV", ["root"]),
            ("root", "LOAD", []),
            ("left", "NEG", ["root"]),
        ],
        [
            ("z", "ADD", ["a", "m"]),
            ("q", "CONST", []),
            ("m", "MUL", ["b"]),
            ("b", "LOAD", []),
            ("a", "LOAD", []),
        ],
        [
            ("n4", "POW", ["n3"]),
            ("n2", "SUB", ["n1"]),
            ("n1", "LOAD", []),
            ("n3", "MUL", ["n2"]),
        ],
    ]

    for nodes in cases:
        graph = pb2.Graph(nodes=[
            pb2.Node(id=node_id, operation=operation, dependencies=dependencies)
            for node_id, operation, dependencies in nodes
        ])
        response = stub.Compile(graph, timeout=5)
        assert list(response.instructions) == derived_instructions(nodes)


def test_compile_rejects_cycle(built_running_project):
    pb2 = built_running_project["pb2"]
    stub = built_running_project["pb2_grpc"].ExecutionEngineStub(
        built_running_project["channel"]
    )
    graph = pb2.Graph(nodes=[
        pb2.Node(id="x", operation="ADD", dependencies=["z"]),
        pb2.Node(id="y", operation="MUL", dependencies=["x"]),
        pb2.Node(id="z", operation="SUB", dependencies=["y"]),
    ])
    with pytest.raises(grpc.RpcError) as caught:
        stub.Compile(graph, timeout=5)
    assert caught.value.code() == grpc.StatusCode.INVALID_ARGUMENT


def test_output_matches_expected():
    output_path = "/home/user/math_dag/output.txt"
    expected_path = "/home/user/math_dag/expected.txt"

    assert os.path.isfile(output_path), f"{output_path} is missing. Did you run the client?"
    assert os.path.isfile(expected_path), f"{expected_path} is missing."

    with open(output_path, "r") as f:
        output_content = f.read().strip()

    with open(expected_path, "r") as f:
        expected_content = f.read().strip()

    assert output_content == expected_content, "The generated output.txt does not match expected.txt. The topological sort might still be incorrect."


def test_diff_result_empty():
    diff_path = "/home/user/math_dag/diff_result.txt"
    assert os.path.isfile(diff_path), f"{diff_path} is missing. Did you run the diff command and save the output?"

    with open(diff_path, "r") as f:
        diff_content = f.read().strip()

    assert diff_content == "", f"{diff_path} is not empty. There are differences between output.txt and expected.txt."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
