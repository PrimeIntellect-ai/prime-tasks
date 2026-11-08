#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import importlib
import os
import random
import re
import secrets
import socket
import subprocess
import sys
import time

import grpc
import pytest

PROJECT = "/home/user/graph_service"


def port_is_open():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.2)
    try:
        return sock.connect_ex(("127.0.0.1", 50051)) == 0
    finally:
        sock.close()


def expected_topological_sort(edges):
    adjacency = {}
    in_degree = {}
    nodes = set()
    for source, target in edges:
        nodes.add(source)
        nodes.add(target)
        adjacency.setdefault(source, []).append(target)
        in_degree[target] = in_degree.get(target, 0) + 1
        in_degree.setdefault(source, in_degree.get(source, 0))

    queue = [node for node in nodes if in_degree.get(node, 0) == 0]
    heapq.heapify(queue)
    result = []
    while queue:
        node = heapq.heappop(queue)
        result.append(node)
        for neighbor in adjacency.get(node, []):
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                heapq.heappush(queue, neighbor)

    assert len(result) == len(nodes), "Verifier generated a cyclic graph"
    return result


def test_graph_proto_fixed():
    proto_path = "/home/user/graph_service/graph.proto"
    assert os.path.isfile(proto_path), f"{proto_path} is missing"

    with open(proto_path, "r") as f:
        content = f.read()

    assert "repeated Edge edges" in content, "graph.proto does not contain the fixed 'repeated Edge edges = 1;' syntax"
    assert "repeated edges = 1;" not in content, "graph.proto still contains the syntax error"


def test_protobuf_compiled():
    pb2_path = "/home/user/graph_service/graph_pb2.py"
    pb2_grpc_path = "/home/user/graph_service/graph_pb2_grpc.py"

    assert os.path.isfile(pb2_path), f"Compiled protobuf file {pb2_path} is missing"
    assert os.path.isfile(pb2_grpc_path), f"Compiled gRPC stub file {pb2_grpc_path} is missing"

    sys.path.insert(0, PROJECT)
    try:
        graph_pb2 = importlib.import_module("graph_pb2")
        graph_pb2_grpc = importlib.import_module("graph_pb2_grpc")
    finally:
        if sys.path[0] == PROJECT:
            sys.path.pop(0)

    edge_field = graph_pb2.GraphRequest.DESCRIPTOR.fields_by_name.get("edges")
    assert edge_field is not None
    assert edge_field.is_repeated
    assert edge_field.message_type.full_name == graph_pb2.Edge.DESCRIPTOR.full_name

    service = graph_pb2.DESCRIPTOR.services_by_name.get("GraphService")
    assert service is not None, "GraphService is missing from the compiled descriptor"
    method = service.methods_by_name.get("TopologicalSort")
    assert method is not None, "TopologicalSort RPC is missing"
    assert method.input_type.full_name == graph_pb2.GraphRequest.DESCRIPTOR.full_name
    assert method.output_type.full_name == graph_pb2.GraphResponse.DESCRIPTOR.full_name
    assert hasattr(graph_pb2_grpc, "GraphServiceStub")
    assert hasattr(graph_pb2_grpc, "GraphServiceServicer")


def test_e2e_script_exists():
    e2e_path = "/home/user/graph_service/test_e2e.py"
    assert os.path.isfile(e2e_path), f"End-to-end test script {e2e_path} is missing"


def test_e2e_script_runs_and_recreates_result():
    e2e_path = os.path.join(PROJECT, "test_e2e.py")
    result_path = os.path.join(PROJECT, "result.txt")
    assert not port_is_open(), "Port 50051 is already occupied before the end-to-end test"
    if os.path.exists(result_path):
        os.unlink(result_path)

    completed = subprocess.run(
        [sys.executable, e2e_path],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, "test_e2e.py failed:\n" + completed.stdout
    assert os.path.isfile(result_path), "test_e2e.py did not recreate result.txt"

    deadline = time.time() + 5
    while port_is_open() and time.time() < deadline:
        time.sleep(0.1)
    assert not port_is_open(), "test_e2e.py did not shut down the server on port 50051"


def test_result_txt_content():
    result_path = "/home/user/graph_service/result.txt"
    assert os.path.isfile(result_path), f"Result file {result_path} is missing"

    with open(result_path, "r") as f:
        content = f.read().strip()

    # Extract just the numbers to ignore formatting differences like spaces
    numbers = re.findall(r'\d+', content)
    expected_numbers = ['1', '2', '4', '3', '5', '6']

    assert numbers == expected_numbers, f"result.txt content is incorrect. Expected {expected_numbers}, got {numbers}"


def test_live_grpc_server_and_deterministic_algorithm():
    sys.path.insert(0, PROJECT)
    try:
        graph_pb2 = importlib.import_module("graph_pb2")
        graph_pb2_grpc = importlib.import_module("graph_pb2_grpc")
    finally:
        if sys.path[0] == PROJECT:
            sys.path.pop(0)

    assert not port_is_open(), "Port 50051 is occupied before starting server.py"
    process = subprocess.Popen(
        [sys.executable, os.path.join(PROJECT, "server.py")],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    channel = grpc.insecure_channel("127.0.0.1:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
        assert process.poll() is None, "server.py exited before serving requests"
        stub = graph_pb2_grpc.GraphServiceStub(channel)

        cases = [
            [(1, 2), (2, 3), (4, 3), (5, 6)],
            [(10, 40), (-5, 40), (2, 10), (2, 30), (30, 40), (-5, 7)],
            [(9, 20), (1, 20), (3, 8), (8, 20), (1, 3)],
        ]

        rng = random.Random(secrets.randbits(64))
        node_ids = rng.sample(range(-1000000, 1000000), 12)
        hidden_order = node_ids[:]
        rng.shuffle(hidden_order)
        random_edges = []
        for i in range(len(hidden_order) - 1):
            random_edges.append((hidden_order[i], hidden_order[i + 1]))
        for i in range(len(hidden_order)):
            for j in range(i + 2, len(hidden_order)):
                if rng.random() < 0.22:
                    random_edges.append((hidden_order[i], hidden_order[j]))
        rng.shuffle(random_edges)
        cases.append(random_edges)

        for edges in cases:
            request = graph_pb2.GraphRequest(
                edges=[graph_pb2.Edge(source=s, target=t) for s, t in edges]
            )
            response = stub.TopologicalSort(request, timeout=5)
            expected = expected_topological_sort(edges)
            assert list(response.sorted_nodes) == expected, (
                f"Incorrect deterministic topological sort for {edges}: "
                f"expected {expected}, got {list(response.sorted_nodes)}"
            )
    finally:
        channel.close()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
