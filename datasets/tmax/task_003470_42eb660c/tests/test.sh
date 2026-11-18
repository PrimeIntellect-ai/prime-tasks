#!/bin/bash
mkdir -p /logs/verifier

verify_all() {
    PROJECT_DIR=/home/user/grpc_state_service

    # Ensure the checked-in protobuf modules really were regenerated from the
    # submitted proto, rather than merely containing matching keywords.
    local generated
    generated=$(mktemp -d) || return 1
    python3 -m grpc_tools.protoc \
        -I"$PROJECT_DIR" \
        --python_out="$generated" \
        --grpc_python_out="$generated" \
        "$PROJECT_DIR/service.proto" || return 1
    cmp -s "$PROJECT_DIR/service_pb2.py" "$generated/service_pb2.py" || return 1
    cmp -s "$PROJECT_DIR/service_pb2_grpc.py" "$generated/service_pb2_grpc.py" || return 1
    rm -rf "$generated"

    # Remove a possible leftover service, then independently start and exercise
    # the submitted server over gRPC using verifier-derived expectations.
    pkill -f '^python3 server.py$' 2>/dev/null || true
    cat << 'INTEGRATION_EOF' > /tmp/verify_grpc_service.py
import os
import random
import subprocess
import sys
import time

import grpc

PROJECT = "/home/user/grpc_state_service"
sys.path.insert(0, PROJECT)

import service_pb2
import service_pb2_grpc
import server as submitted_server

# Validate exact protobuf field placement, number, and type.
request_desc = service_pb2.ParseRequest.DESCRIPTOR
field = request_desc.fields_by_name.get("sequence_number")
assert field is not None, "ParseRequest lacks sequence_number"
assert field.number == 3, "sequence_number must use field number 3"
assert field.type == field.TYPE_INT32, "sequence_number must be int32"

# Exercise semantic-version comparison on values selected at verification time.
rng = random.SystemRandom()
servicer = submitted_server.LogParserServicer()
versions = [
    (1, 9, 0),
    (1, rng.randint(10, 100), rng.randint(0, 1000)),
    (rng.randint(2, 20), rng.randint(0, 100), rng.randint(0, 1000)),
    (1, rng.randint(0, 8), rng.randint(0, 1000)),
    (0, rng.randint(0, 100), rng.randint(0, 1000)),
]
for parts in versions:
    text = ".".join(map(str, parts))
    expected = parts >= (1, 9, 0)
    actual = servicer.check_version(text, "1.9.0")
    assert actual is expected, f"wrong semantic-version result for {text}: {actual}"

proc = subprocess.Popen(
    [sys.executable, "server.py"],
    cwd=PROJECT,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
channel = grpc.insecure_channel("127.0.0.1:50051")
try:
    grpc.channel_ready_future(channel).result(timeout=8)
    assert proc.poll() is None, "submitted server exited during startup"
    stub = service_pb2_grpc.LogParserStub(channel)

    # An old client must be rejected without advancing the state.
    response = stub.ParseEvent(service_pb2.ParseRequest(
        client_version="1.8.99", event_name="START", sequence_number=101
    ), timeout=3)
    assert not response.accepted
    assert response.current_state == "INIT"

    accepted_version = f"1.{rng.randint(10, 100)}.{rng.randint(0, 1000)}"
    cases = [
        (accepted_version, "START", rng.randint(1, 100000), "RUNNING"),
        ("2.0.0", "PAUSE", rng.randint(1, 100000), "PAUSED"),
        ("1.9.0", "RESUME", rng.randint(1, 100000), "RUNNING"),
        (accepted_version, "HALT", rng.randint(1, 100000), "STOPPED"),
    ]
    for version, event, sequence, expected_state in cases:
        response = stub.ParseEvent(service_pb2.ParseRequest(
            client_version=version,
            event_name=event,
            sequence_number=sequence,
        ), timeout=3)
        assert response.accepted, f"{event} was rejected: {response.error_message}"
        assert response.current_state == expected_state, (
            f"{event} produced {response.current_state}, expected {expected_state}"
        )
finally:
    channel.close()
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
INTEGRATION_EOF
    python3 /tmp/verify_grpc_service.py || return 1

    # Run the demanded client ourselves and require it to create a fresh result.
    rm -f /home/user/test_result.json
    (cd "$PROJECT_DIR" && timeout 25s python3 client_test.py) || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

RESULT_FILE = "/home/user/test_result.json"
PROJECT_DIR = "/home/user/grpc_state_service"

def test_result_file_exists():
    assert os.path.isfile(RESULT_FILE), f"The result file {RESULT_FILE} was not generated. Did you run client_test.py?"

def test_result_file_contents():
    with open(RESULT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULT_FILE} is not a valid JSON file.")

    assert "status" in data, "Result JSON missing 'status' key."
    assert "final_state" in data, "Result JSON missing 'final_state' key."

    assert data["status"] == "success", f"Expected status 'success', got '{data['status']}'."
    assert data["final_state"] == "STOPPED", f"Expected final_state 'STOPPED', got '{data['final_state']}'."

def test_service_proto_fixed():
    proto_file = os.path.join(PROJECT_DIR, "service.proto")
    assert os.path.isfile(proto_file), f"{proto_file} is missing."

    with open(proto_file, "r") as f:
        content = f.read()

    assert "sequence_number" in content, "service.proto is missing the 'sequence_number' field in ParseRequest."
    assert "int32" in content, "service.proto should define 'sequence_number' as an int32."

def test_server_py_fixed():
    server_file = os.path.join(PROJECT_DIR, "server.py")
    assert os.path.isfile(server_file), f"{server_file} is missing."

    with open(server_file, "r") as f:
        content = f.read()

    assert '"HALT":' in content or "'HALT':" in content, "server.py still contains the state machine bug (missing 'HALT' transition)."
    assert '"HLT":' not in content and "'HLT':" not in content, "server.py should not contain the 'HLT' typo."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if verify_all 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
