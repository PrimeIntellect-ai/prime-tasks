#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any service the agent may have left listening on the required port so the
# verifier exercises the submitted server process it launches itself.
python3 - <<'CLEANUP_EOF'
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(":")[-1].upper() == "C383" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for pid in os.listdir("/proc"):
    if not pid.isdigit():
        continue
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except OSError:
        pass
if inodes:
    time.sleep(0.5)
CLEANUP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import time
import uuid

import grpc
import pytest
from google.protobuf import descriptor_pb2

ROOT = "/home/user/math_port"
SCRIPT = "/home/user/version_check.py"
CONFIG = "/home/user/config.json"
SERVER = os.path.join(ROOT, "server.py")
CLIENT = os.path.join(ROOT, "client.py")
RESULT = "/home/user/result.json"


def run_version_check():
    return subprocess.run(["python3", SCRIPT], capture_output=True, timeout=10)


def test_version_check_script():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(CONFIG, "rb") as f:
        original = f.read()
    try:
        # Preserve the original assertion for the task's default configuration.
        with open(CONFIG, "w") as f:
            json.dump({"engine_version": "1.7.4"}, f)
        result = run_version_check()
        assert result.returncode == 0, result.stderr.decode(errors="replace")

        # Boundary and multi-digit cases ensure this is semantic, not lexical,
        # comparison and that both required bounds are implemented.
        cases = {
            "1.5.0": 0,
            "1.10.0": 0,
            "1.99.99": 0,
            "1.4.99": 1,
            "0.99.99": 1,
            "2.0.0": 1,
            "2.0.1": 1,
            "10.0.0": 1,
        }
        for version, expected in cases.items():
            with open(CONFIG, "w") as f:
                json.dump({"engine_version": version}, f)
            result = run_version_check()
            assert result.returncode == expected, (
                f"engine_version={version}: expected exit {expected}, got "
                f"{result.returncode}; stderr={result.stderr.decode(errors='replace')}"
            )
    finally:
        with open(CONFIG, "wb") as f:
            f.write(original)


def test_proto_files_exist_and_define_required_api():
    expected_files = [
        os.path.join(ROOT, "math_dag.proto"),
        os.path.join(ROOT, "math_dag_pb2.py"),
        os.path.join(ROOT, "math_dag_pb2_grpc.py"),
    ]
    for path in expected_files:
        assert os.path.isfile(path), f"Expected file {path} does not exist."
        assert os.path.getsize(path) > 0, f"Expected file {path} is empty."

    # Compile the submitted source independently, producing a descriptor set.
    with tempfile.TemporaryDirectory() as td:
        desc_path = os.path.join(td, "api.pb")
        proc = subprocess.run([
            sys.executable, "-m", "grpc_tools.protoc",
            f"-I{ROOT}", f"--descriptor_set_out={desc_path}",
            os.path.join(ROOT, "math_dag.proto"),
        ], capture_output=True, timeout=20)
        assert proc.returncode == 0, proc.stderr.decode(errors="replace")
        descriptor_set = descriptor_pb2.FileDescriptorSet()
        with open(desc_path, "rb") as f:
            descriptor_set.ParseFromString(f.read())

    files = [x for x in descriptor_set.file if x.name == "math_dag.proto"]
    assert len(files) == 1
    fd = files[0]
    assert fd.syntax == "proto3"
    messages = {m.name: m for m in fd.message_type}
    assert {"Node", "GraphRequest", "GraphResponse"}.issubset(messages)

    node_fields = {f.name: f for f in messages["Node"].field}
    assert set(node_fields) == {"id", "operation", "value", "dependencies"}
    assert node_fields["id"].type == descriptor_pb2.FieldDescriptorProto.TYPE_STRING
    assert node_fields["operation"].type == descriptor_pb2.FieldDescriptorProto.TYPE_STRING
    assert node_fields["value"].type == descriptor_pb2.FieldDescriptorProto.TYPE_DOUBLE
    assert node_fields["dependencies"].type == descriptor_pb2.FieldDescriptorProto.TYPE_STRING
    assert node_fields["dependencies"].label == descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED

    request_fields = {f.name: f for f in messages["GraphRequest"].field}
    assert set(request_fields) == {"nodes"}
    assert request_fields["nodes"].label == descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED
    assert request_fields["nodes"].type == descriptor_pb2.FieldDescriptorProto.TYPE_MESSAGE
    assert request_fields["nodes"].type_name.endswith(".Node")

    response_fields = {f.name: f for f in messages["GraphResponse"].field}
    assert set(response_fields) == {"results"}
    results_field = response_fields["results"]
    assert results_field.label == descriptor_pb2.FieldDescriptorProto.LABEL_REPEATED
    assert results_field.type == descriptor_pb2.FieldDescriptorProto.TYPE_MESSAGE
    map_name = results_field.type_name.rsplit(".", 1)[-1]
    map_entry = next(m for m in messages["GraphResponse"].nested_type if m.name == map_name)
    assert map_entry.options.map_entry
    map_fields = {f.name: f for f in map_entry.field}
    assert map_fields["key"].type == descriptor_pb2.FieldDescriptorProto.TYPE_STRING
    assert map_fields["value"].type == descriptor_pb2.FieldDescriptorProto.TYPE_DOUBLE

    services = {s.name: s for s in fd.service}
    assert "MathResolver" in services
    methods = {m.name: m for m in services["MathResolver"].method}
    assert set(methods) == {"ResolveGraph"}
    assert methods["ResolveGraph"].input_type.endswith(".GraphRequest")
    assert methods["ResolveGraph"].output_type.endswith(".GraphResponse")

    sys.path.insert(0, ROOT)
    import math_dag_pb2
    import math_dag_pb2_grpc
    assert hasattr(math_dag_pb2, "Node")
    assert hasattr(math_dag_pb2, "GraphRequest")
    assert hasattr(math_dag_pb2, "GraphResponse")
    assert hasattr(math_dag_pb2_grpc, "MathResolverStub")
    assert hasattr(math_dag_pb2_grpc, "MathResolverServicer")
    assert hasattr(math_dag_pb2_grpc, "add_MathResolverServicer_to_server")


def test_server_and_client_scripts_exist_and_are_executable():
    for path in (SERVER, CLIENT):
        assert os.path.isfile(path), f"Expected file {path} does not exist."
        assert os.path.getsize(path) > 0, f"Expected file {path} is empty."
        assert os.access(path, os.X_OK), f"Script {path} is not executable."


def start_submitted_server():
    proc = subprocess.Popen(
        [sys.executable, SERVER], cwd=ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
    except Exception:
        proc.terminate()
        try:
            out, err = proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, err = proc.communicate()
        channel.close()
        pytest.fail(f"Submitted server did not listen on port 50051. stdout={out!r}, stderr={err!r}")
    assert proc.poll() is None, "Submitted server exited during startup"
    return proc, channel


def stop_submitted_server(proc, channel):
    channel.close()
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
    time.sleep(0.3)


def assert_json_file(expected):
    assert os.path.isfile(RESULT), f"Result file {RESULT} does not exist. Did you run the client?"
    with open(RESULT) as f:
        data = json.load(f)
    assert data == expected, f"Expected {expected}, got {data}"
    with open(RESULT) as f:
        raw = f.read()
    positions = [raw.find(json.dumps(k)) for k in sorted(expected)]
    assert all(p >= 0 for p in positions)
    assert positions == sorted(positions), "Keys in result.json are not sorted alphabetically."


def test_live_grpc_server_graph_traversal_and_client_rpc():
    sys.path.insert(0, ROOT)
    import math_dag_pb2 as pb2
    import math_dag_pb2_grpc as pb2_grpc

    proc, channel = start_submitted_server()
    try:
        stub = pb2_grpc.MathResolverStub(channel)

        # Runtime-generated identifiers and values prevent a fixed response from
        # satisfying the service test. Nodes are deliberately sent out of order.
        rng = random.SystemRandom()
        prefix = uuid.uuid4().hex
        a, b, c = (f"{prefix}_{x}" for x in ("a", "b", "c"))
        add, product, final = (f"{prefix}_{x}" for x in ("sum", "product", "final"))
        x = rng.uniform(-9.0, -0.5)
        y = rng.uniform(0.5, 8.0)
        z = rng.uniform(1.1, 4.0)
        nodes = [
            pb2.Node(id=final, operation="ADD", dependencies=[product, add, a]),
            pb2.Node(id=product, operation="MULTIPLY", dependencies=[add, c]),
            pb2.Node(id=b, operation="VALUE", value=y),
            pb2.Node(id=add, operation="ADD", dependencies=[a, b]),
            pb2.Node(id=c, operation="VALUE", value=z),
            pb2.Node(id=a, operation="VALUE", value=x),
        ]
        response = stub.ResolveGraph(pb2.GraphRequest(nodes=nodes), timeout=10)
        expected = {
            a: x,
            b: y,
            c: z,
            add: x + y,
            product: (x + y) * z,
            final: ((x + y) * z) + (x + y) + x,
        }
        assert set(response.results) == set(expected)
        for key, value in expected.items():
            assert response.results[key] == pytest.approx(value, rel=1e-12, abs=1e-12)
        assert proc.poll() is None, "Submitted server exited after handling an RPC"

        # Preserve the original end-to-end assertion using the submitted client.
        if os.path.exists(RESULT):
            os.unlink(RESULT)
        client_run = subprocess.run([sys.executable, CLIENT], cwd=ROOT, capture_output=True, timeout=15)
        assert client_run.returncode == 0, client_run.stderr.decode(errors="replace")
        original_expected = {"A": 3.5, "B": 2.0, "C": 5.5, "D": 19.25, "E": 21.25}
        assert_json_file(original_expected)
    finally:
        stop_submitted_server(proc, channel)

    # Run the client against a verifier-controlled service with unpredictable
    # returned values. This proves it makes the RPC and serializes its response,
    # rather than merely writing the five known constants.
    calls = []
    offset = random.SystemRandom().uniform(50.0, 100.0)
    controlled_results = {
        "A": 3.5 + offset,
        "B": 2.0 + offset,
        "C": 5.5 + offset,
        "D": 19.25 + offset,
        "E": 21.25 + offset,
    }

    class Controlled(pb2_grpc.MathResolverServicer):
        def ResolveGraph(self, request, context):
            calls.append(request)
            return pb2.GraphResponse(results=controlled_results)

    control_server = grpc.server(concurrent.futures.ThreadPoolExecutor(max_workers=2))
    pb2_grpc.add_MathResolverServicer_to_server(Controlled(), control_server)
    assert control_server.add_insecure_port("localhost:50051") != 0
    control_server.start()
    try:
        if os.path.exists(RESULT):
            os.unlink(RESULT)
        client_run = subprocess.run([sys.executable, CLIENT], cwd=ROOT, capture_output=True, timeout=15)
        assert client_run.returncode == 0, client_run.stderr.decode(errors="replace")
        assert len(calls) == 1, "Client did not call ResolveGraph exactly once"
        request_nodes = {n.id: n for n in calls[0].nodes}
        assert set(request_nodes) == {"A", "B", "C", "D", "E"}
        assert request_nodes["A"].operation == "VALUE" and request_nodes["A"].value == 3.5
        assert request_nodes["B"].operation == "VALUE" and request_nodes["B"].value == 2.0
        assert request_nodes["C"].operation == "ADD" and list(request_nodes["C"].dependencies) == ["A", "B"]
        assert request_nodes["D"].operation == "MULTIPLY" and list(request_nodes["D"].dependencies) == ["C", "A"]
        assert request_nodes["E"].operation == "ADD" and list(request_nodes["E"].dependencies) == ["D", "B"]
        assert_json_file(controlled_results)
    finally:
        control_server.stop(0).wait()
        time.sleep(0.3)

    # Leave result.json in the task-requested final state and recheck it.
    proc, channel = start_submitted_server()
    try:
        client_run = subprocess.run([sys.executable, CLIENT], cwd=ROOT, capture_output=True, timeout=15)
        assert client_run.returncode == 0, client_run.stderr.decode(errors="replace")
        assert_json_file({"A": 3.5, "B": 2.0, "C": 5.5, "D": 19.25, "E": 21.25})
    finally:
        stop_submitted_server(proc, channel)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
