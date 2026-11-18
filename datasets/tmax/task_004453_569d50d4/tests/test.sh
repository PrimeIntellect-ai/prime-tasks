#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import sys
import time

import grpc
import pytest
from packaging.version import Version

PROJECT = "/home/user/project"
LOG_PATH = os.path.join(PROJECT, "proxy_results.log")


def test_generated_files_exist():
    """Verify that the protobuf files were successfully compiled."""
    assert os.path.isfile(os.path.join(PROJECT, "service_pb2.py")), "service_pb2.py was not generated. Did you compile the protobuf schema?"
    assert os.path.isfile(os.path.join(PROJECT, "service_pb2_grpc.py")), "service_pb2_grpc.py was not generated. Did you compile the protobuf schema?"


def test_generated_stubs_are_valid():
    """Import the generated modules and verify that they describe the required schema and service."""
    sys.path.insert(0, PROJECT)
    import service_pb2
    import service_pb2_grpc

    request = service_pb2.MessageRequest.DESCRIPTOR
    assert request.fields_by_name["content"].number == 1
    assert request.fields_by_name["content"].type == request.fields_by_name["content"].TYPE_STRING
    assert request.fields_by_name["client_version"].number == 2
    assert request.fields_by_name["client_version"].type == request.fields_by_name["client_version"].TYPE_STRING

    response = service_pb2.MessageResponse.DESCRIPTOR
    assert response.fields_by_name["success"].number == 1
    assert response.fields_by_name["success"].type == response.fields_by_name["success"].TYPE_BOOL

    service = service_pb2.DESCRIPTOR.services_by_name["ProxyService"]
    method = service.methods_by_name["SendMessage"]
    assert method.input_type.full_name == "proxy.MessageRequest"
    assert method.output_type.full_name == "proxy.MessageResponse"
    assert hasattr(service_pb2_grpc, "ProxyServiceStub")
    assert hasattr(service_pb2_grpc, "ProxyServiceServicer")
    assert callable(service_pb2_grpc.add_ProxyServiceServicer_to_server)


@pytest.fixture(scope="module")
def running_server():
    # Stop any server left running by the agent so the verifier executes the submitted ws_server.py.
    subprocess.run(
        ["pkill", "-f", r"(^|/)python3? .*ws_server\.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.3)

    open(LOG_PATH, "w").close()
    proc = subprocess.Popen(
        [sys.executable, "ws_server.py"],
        cwd=PROJECT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )

    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=8)
    except Exception:
        proc.terminate()
        try:
            _, stderr = proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, stderr = proc.communicate()
        pytest.fail(f"Submitted ws_server.py did not start a gRPC server: {stderr}")
    finally:
        channel.close()

    try:
        yield proc
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)


def test_proxy_results_log(running_server):
    """Run the provided client and verify its two required outcomes."""
    open(LOG_PATH, "w").close()
    result = subprocess.run(
        [sys.executable, "test_client.py"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"test_client.py failed:\n{result.stdout}\n{result.stderr}"

    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Expected at least 2 lines in proxy_results.log, found {len(lines)}. Did you run the test client?"
    last_two_lines = lines[-2:]
    assert last_two_lines[0] == "REJECTED: Version too low", f"Expected first request to be rejected, but got: {last_two_lines[0]}"
    assert last_two_lines[1] == "SUCCESS: Forwarded message to WS", f"Expected second request to be accepted (2.10.0 > 2.2.0), but got: {last_two_lines[1]}"


def test_server_uses_semantic_version_ordering(running_server):
    """Exercise the submitted server on independently generated semantic versions."""
    sys.path.insert(0, PROJECT)
    import service_pb2
    import service_pb2_grpc

    n = secrets.randbelow(500) + 10
    cases = [
        "2.2.0",
        f"2.1.{n}",
        f"2.{n}.0",
        f"1.{n}.{n}",
        f"3.0.{n}",
        f"2.2.0rc{secrets.randbelow(20) + 1}",
    ]
    random.SystemRandom().shuffle(cases)

    open(LOG_PATH, "w").close()
    expected_lines = []
    with grpc.insecure_channel("localhost:50051") as channel:
        stub = service_pb2_grpc.ProxyServiceStub(channel)
        for version_text in cases:
            expected = Version(version_text) >= Version("2.2.0")
            response = stub.SendMessage(
                service_pb2.MessageRequest(content="verifier", client_version=version_text),
                timeout=5,
            )
            assert response.success is expected, (
                f"Incorrect decision for semantic version {version_text}: "
                f"expected success={expected}, got {response.success}"
            )
            expected_lines.append(
                "SUCCESS: Forwarded message to WS" if expected
                else "REJECTED: Version too low"
            )

    with open(LOG_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == expected_lines, f"Server log did not match the RPC decisions: {lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
