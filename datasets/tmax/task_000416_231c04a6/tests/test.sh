#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import gc
import json
import os
import random
import secrets
import socket
import sys
import time
import weakref

import grpc
import websockets
from google.protobuf.descriptor import FieldDescriptor
from websockets.exceptions import ConnectionClosed

sys.path.insert(0, "/home/user")


def assert_topological(order, artifacts):
    names = [a["name"] for a in artifacts]
    assert len(order) == len(names), f"Expected {len(names)} build steps, got {order!r}"
    assert len(set(order)) == len(order), f"Build order contains duplicates: {order!r}"
    assert set(order) == set(names), f"Build order has incorrect artifacts: {order!r}"
    positions = {name: i for i, name in enumerate(order)}
    for artifact in artifacts:
        for dependency in artifact["depends_on"]:
            assert positions[dependency] < positions[artifact["name"]], \
                f"Dependency {dependency!r} was not built before {artifact['name']!r}: {order!r}"


def random_dag(size=10):
    names = [f"artifact_{secrets.token_hex(6)}" for _ in range(size)]
    artifacts = []
    rng = random.SystemRandom()
    for i, name in enumerate(names):
        dependencies = []
        if i:
            dependencies.append(names[i - 1])
            dependencies.extend(
                names[j] for j in range(i - 1)
                if rng.random() < 0.25
            )
        artifacts.append({"name": name, "depends_on": list(dict.fromkeys(dependencies))})
    rng.shuffle(artifacts)
    return artifacts


def test_memory_fix_log_exists():
    """Check if the memory fix log was created."""
    log_path = "/home/user/memory_fix_log.txt"
    assert os.path.isfile(log_path), f"{log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"{log_path} is empty."


def test_artifact_graph_leak_fixed():
    """Check both the original source assertion and actual release of a populated DAG."""
    graph_path = "/home/user/artifact_graph.py"
    assert os.path.isfile(graph_path), f"{graph_path} is missing."
    with open(graph_path, "r") as f:
        content = f.read()
    assert "node.dependents.append(self)" not in content or "weakref" in content, \
        "The circular reference in artifact_graph.py does not appear to be fixed (e.g., using weakref)."

    import artifact_graph

    gc.collect()
    was_enabled = gc.isenabled()
    gc.disable()
    try:
        bg = artifact_graph.BuildGraph()
        for i in range(40):
            bg.add_artifact(f"n{i}", [] if i == 0 else [f"n{i - 1}"])

        node_values = list(bg.nodes.values())
        node_ids = {id(node) for node in node_values}
        refs = []
        for node in node_values:
            try:
                refs.append(weakref.ref(node))
            except TypeError:
                pass
        del node
        del node_values
        del bg

        if refs:
            assert all(ref() is None for ref in refs), \
                "DAG nodes remain alive without cyclic garbage collection; strong circular references remain"
        else:
            lingering = [obj for obj in gc.get_objects()
                         if id(obj) in node_ids and obj.__class__.__module__ == "artifact_graph"]
            assert not lingering, \
                "DAG nodes remain alive without cyclic garbage collection; strong circular references remain"
    finally:
        if was_enabled:
            gc.enable()
        gc.collect()


def test_artifact_graph_logic():
    """Check if BuildGraph still computes correct orders for general DAGs and cycles."""
    import artifact_graph

    bg = artifact_graph.BuildGraph()
    bg.add_artifact("A", [])
    bg.add_artifact("B", ["A"])
    bg.add_artifact("C", ["A"])
    bg.add_artifact("D", ["B", "C"])
    order = bg.get_build_order()
    assert order[0] == "A", "Build order must start with A"
    assert "D" == order[-1], "Build order must end with D"
    assert set(order) == {"A", "B", "C", "D"}, "Build order must contain all artifacts"

    artifacts = random_dag(14)
    bg = artifact_graph.BuildGraph()
    for artifact in artifacts:
        bg.add_artifact(artifact["name"], artifact["depends_on"])
    assert_topological(bg.get_build_order(), artifacts)

    cyclic = artifact_graph.BuildGraph()
    cyclic.add_artifact("cycle_a", ["cycle_b"])
    cyclic.add_artifact("cycle_b", ["cycle_c"])
    cyclic.add_artifact("cycle_c", ["cycle_a"])
    assert cyclic.get_build_order() == [], "A cycle must produce an empty build order"


def test_protobuf_files_exist_and_descriptors_match():
    """Retain source checks and verify the compiled protobuf schema exactly."""
    proto_path = "/home/user/build_service.proto"
    assert os.path.isfile(proto_path), f"{proto_path} is missing."
    with open(proto_path, "r") as f:
        content = f.read()
    assert 'syntax = "proto3";' in content, "Proto file must use proto3 syntax."
    assert "message Artifact" in content, "Proto file must define Artifact message."
    assert "message GraphRequest" in content, "Proto file must define GraphRequest message."
    assert "message OrderResponse" in content, "Proto file must define OrderResponse message."
    assert "service BuildResolver" in content, "Proto file must define BuildResolver service."

    pb2_path = "/home/user/build_service_pb2.py"
    pb2_grpc_path = "/home/user/build_service_pb2_grpc.py"
    assert os.path.isfile(pb2_path), f"Compiled protobuf file {pb2_path} is missing."
    assert os.path.isfile(pb2_grpc_path), f"Compiled gRPC file {pb2_grpc_path} is missing."

    import build_service_pb2 as pb2
    import build_service_pb2_grpc as pb2_grpc

    descriptor = pb2.DESCRIPTOR
    assert set(descriptor.message_types_by_name) == {"Artifact", "GraphRequest", "OrderResponse"}
    artifact = descriptor.message_types_by_name["Artifact"]
    request = descriptor.message_types_by_name["GraphRequest"]
    response = descriptor.message_types_by_name["OrderResponse"]

    assert [(f.name, f.number, f.type, f.label) for f in artifact.fields] == [
        ("name", 1, FieldDescriptor.TYPE_STRING, FieldDescriptor.LABEL_OPTIONAL),
        ("depends_on", 2, FieldDescriptor.TYPE_STRING, FieldDescriptor.LABEL_REPEATED),
    ]
    assert len(request.fields) == 1
    assert request.fields[0].name == "artifacts" and request.fields[0].number == 1
    assert request.fields[0].label == FieldDescriptor.LABEL_REPEATED
    assert request.fields[0].message_type is artifact
    assert len(response.fields) == 1
    assert response.fields[0].name == "build_order" and response.fields[0].number == 1
    assert response.fields[0].type == FieldDescriptor.TYPE_STRING
    assert response.fields[0].label == FieldDescriptor.LABEL_REPEATED

    assert set(descriptor.services_by_name) == {"BuildResolver"}
    service = descriptor.services_by_name["BuildResolver"]
    assert len(service.methods) == 1
    method = service.methods[0]
    assert method.name == "Resolve"
    assert method.input_type is request and method.output_type is response
    assert not method.client_streaming and not method.server_streaming
    assert hasattr(pb2_grpc, "BuildResolverStub")
    assert hasattr(pb2_grpc, "BuildResolverServicer")
    assert hasattr(pb2_grpc, "add_BuildResolverServicer_to_server")


def test_server_pid_and_ports():
    """Retain PID and TCP checks and ensure the requested executable exists."""
    server_path = "/home/user/server.py"
    assert os.path.isfile(server_path), f"{server_path} is missing."
    assert os.access(server_path, os.X_OK), f"{server_path} is not executable."

    pid_path = "/home/user/server.pid"
    assert os.path.isfile(pid_path), f"{pid_path} is missing. Server might not be running in the background."
    with open(pid_path, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex(("127.0.0.1", 50051))
        assert result == 0, "gRPC server is not listening on port 50051."
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        result = s.connect_ex(("127.0.0.1", 8765))
        assert result == 0, "WebSocket server is not listening on port 8765."


def test_grpc_resolve_protocol_and_results():
    import build_service_pb2 as pb2
    import build_service_pb2_grpc as pb2_grpc

    channel = grpc.insecure_channel("127.0.0.1:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=4)
        stub = pb2_grpc.BuildResolverStub(channel)

        for size in (7, 13):
            artifacts = random_dag(size)
            request = pb2.GraphRequest(artifacts=[
                pb2.Artifact(name=a["name"], depends_on=a["depends_on"])
                for a in artifacts
            ])
            response = stub.Resolve(request, timeout=4)
            assert isinstance(response, pb2.OrderResponse)
            assert_topological(list(response.build_order), artifacts)

        prefix = secrets.token_hex(7)
        cyclic = [
            {"name": prefix + "_a", "depends_on": [prefix + "_b"]},
            {"name": prefix + "_b", "depends_on": [prefix + "_c"]},
            {"name": prefix + "_c", "depends_on": [prefix + "_a"]},
        ]
        response = stub.Resolve(pb2.GraphRequest(artifacts=[
            pb2.Artifact(name=a["name"], depends_on=a["depends_on"])
            for a in cyclic
        ]), timeout=4)
        assert list(response.build_order) == [], "gRPC Resolve must return an empty order for a cycle"
    finally:
        channel.close()


async def websocket_exchange(payload):
    messages = []
    times = []
    async with websockets.connect("ws://127.0.0.1:8765", open_timeout=4, close_timeout=2) as ws:
        await ws.send(json.dumps(payload))
        while True:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=4)
            except ConnectionClosed:
                break
            messages.append(json.loads(raw))
            times.append(time.monotonic())
    return messages, times


def test_websocket_streaming_protocol_timing_and_cycle():
    prefix = secrets.token_hex(8)
    names = [prefix + suffix for suffix in ("_first", "_second", "_third", "_fourth")]
    artifacts = [
        {"name": names[2], "depends_on": [names[1]]},
        {"name": names[0], "depends_on": []},
        {"name": names[3], "depends_on": [names[2]]},
        {"name": names[1], "depends_on": [names[0]]},
    ]
    messages, times = asyncio.run(websocket_exchange({"artifacts": artifacts}))
    assert messages == [{"step": name} for name in names], \
        f"WebSocket returned an incorrect streamed build order: {messages!r}"
    assert len(times) == len(names)
    for earlier, later in zip(times, times[1:]):
        assert later - earlier >= 0.075, "WebSocket build steps were not delayed by approximately 0.1 seconds"

    cycle_prefix = secrets.token_hex(8)
    cycle = {
        "artifacts": [
            {"name": cycle_prefix + "_x", "depends_on": [cycle_prefix + "_y"]},
            {"name": cycle_prefix + "_y", "depends_on": [cycle_prefix + "_x"]},
        ]
    }
    messages, _ = asyncio.run(websocket_exchange(cycle))
    assert messages == [], "WebSocket cycle handling must stream no build steps"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
