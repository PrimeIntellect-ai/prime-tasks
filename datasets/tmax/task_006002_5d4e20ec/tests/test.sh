#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import socket
import subprocess
import sys
import time
import uuid

import pytest


def port_is_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def wait_for_ports_closed(timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not port_is_open(50051) and not port_is_open(8765):
            return True
        time.sleep(0.1)
    return not port_is_open(50051) and not port_is_open(8765)


def test_scorer_translation():
    """Verify that the ReadinessScorer has been correctly translated to Python."""
    scorer_path = "/home/user/scorer.py"
    assert os.path.isfile(scorer_path), f"Missing file: {scorer_path}"

    sys.path.insert(0, "/home/user")
    try:
        import scorer
    except ImportError as e:
        pytest.fail(f"Failed to import scorer.py: {e}")

    assert hasattr(scorer, "ReadinessScorer"), "ReadinessScorer class missing in scorer.py"

    # Test the logic based on the legacy JS implementation
    window_size = 3
    s = scorer.ReadinessScorer(window_size)
    assert s.get_score() == 100, "Initial score should be 100"

    metrics = [80, 60, 50]
    for m in metrics:
        s.add_metric(m)
    assert s.get_score() == 63, f"Expected score 63, got {s.get_score()}"

    s.add_metric(30)
    assert s.get_score() == 46, f"Expected score 46, got {s.get_score()}"

    s.add_metric(90)
    assert s.get_score() == 56, f"Expected score 56, got {s.get_score()}"

    s.add_metric(10)
    assert s.get_score() == 43, f"Expected score 43, got {s.get_score()}"


def test_scorer_additional_sequences():
    import scorer

    for window_size in (1, 2, 4, 7):
        values = [secrets.randbelow(241) - 120 for _ in range(15)]
        instance = scorer.ReadinessScorer(window_size)
        assert instance.get_score() == 100
        active = []
        for value in values:
            instance.add_metric(value)
            active.append(value)
            active = active[-window_size:]
            expected = math.floor(sum(active) / len(active))
            assert instance.get_score() == expected


def test_protobuf_files_exist():
    """Verify that the Protobuf definition and compiled files exist."""
    assert os.path.isfile("/home/user/deployment.proto"), "Missing deployment.proto"
    assert os.path.isfile("/home/user/deployment_pb2.py"), "Missing compiled deployment_pb2.py"
    assert os.path.isfile("/home/user/deployment_pb2_grpc.py"), "Missing compiled deployment_pb2_grpc.py"


def test_protobuf_schema():
    sys.path.insert(0, "/home/user")
    import deployment_pb2

    metric = deployment_pb2.Metric.DESCRIPTOR
    assert [(f.name, f.number, f.type) for f in metric.fields] == [
        ("service_name", 1, 9),
        ("health_value", 2, 5),
    ]

    response = deployment_pb2.DeployResponse.DESCRIPTOR
    assert [(f.name, f.number, f.type) for f in response.fields] == [
        ("approved", 1, 8),
    ]

    service = deployment_pb2.DESCRIPTOR.services_by_name.get("ReleaseManager")
    assert service is not None
    assert len(service.methods) == 1
    method = service.methods[0]
    assert method.name == "SendMetric"
    assert method.input_type.full_name == metric.full_name
    assert method.output_type.full_name == response.full_name


def test_server_script_exists():
    """Verify that the server script exists."""
    assert os.path.isfile("/home/user/server.py"), "Missing server.py"


def test_e2e_orchestration():
    """Run the end-to-end bash script and verify it exits cleanly and creates the correct alerts.log."""
    script_path = "/home/user/run_e2e.sh"
    assert os.path.isfile(script_path), f"Missing orchestration script: {script_path}"

    alerts_log = "/home/user/alerts.log"
    if os.path.exists(alerts_log):
        os.remove(alerts_log)

    # Run the script
    result = subprocess.run(["bash", script_path], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"run_e2e.sh failed with exit code {result.returncode}.\nstdout: {result.stdout}\nstderr: {result.stderr}"

    # Check if alerts.log was created
    assert os.path.isfile(alerts_log), "alerts.log was not created by the orchestration script"

    with open(alerts_log, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 alerts in alerts.log, found {len(lines)}: {lines}"

    try:
        alert1 = json.loads(lines[0])
        alert2 = json.loads(lines[1])
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON from alerts.log: {e}")

    expected_alert1 = {"alert": "deployment halted", "service": "auth-svc", "score": 46}
    expected_alert2 = {"alert": "deployment halted", "service": "payment-svc", "score": 43}

    assert alert1 == expected_alert1, f"First alert mismatch. Expected {expected_alert1}, got {alert1}"
    assert alert2 == expected_alert2, f"Second alert mismatch. Expected {expected_alert2}, got {alert2}"
    assert wait_for_ports_closed(), "run_e2e.sh did not terminate its server processes"


def test_e2e_with_dynamic_metrics_and_rpc_responses():
    """Exercise the submitted orchestration, gRPC service, and WebSocket broadcast with fresh inputs."""
    assert wait_for_ports_closed(), "Required ports were already occupied before the dynamic test"

    nonce = uuid.uuid4().hex
    values = [
        secrets.randbelow(10) + 90,
        secrets.randbelow(10) + 80,
        secrets.randbelow(10) + 70,
        secrets.randbelow(11),
        secrets.randbelow(11),
        secrets.randbelow(11),
        secrets.randbelow(31) + 70,
        secrets.randbelow(16),
    ]
    sequence = [(f"svc-{nonce}-{index}", value) for index, value in enumerate(values)]

    rolling = []
    expected_approvals = []
    expected_alerts = []
    for service_name, value in sequence:
        rolling.append(value)
        rolling = rolling[-3:]
        score = math.floor(sum(rolling) / len(rolling))
        approved = score >= 50
        expected_approvals.append(approved)
        if not approved:
            expected_alerts.append({
                "alert": "deployment halted",
                "service": service_name,
                "score": score,
            })
    assert expected_alerts

    client_path = "/home/user/tests/grpc_client.py"
    listener_path = "/home/user/tests/ws_listener.py"
    responses_path = f"/tmp/grpc_responses_{nonce}.json"
    alerts_path = "/home/user/alerts.log"

    with open(client_path, "rb") as f:
        original_client = f.read()
    with open(listener_path, "rb") as f:
        original_listener = f.read()

    client_source = f'''import json
import time
import grpc
import deployment_pb2
import deployment_pb2_grpc

SEQUENCE = {sequence!r}
RESPONSES_PATH = {responses_path!r}

channel = grpc.insecure_channel("localhost:50051")
grpc.channel_ready_future(channel).result(timeout=8)
stub = deployment_pb2_grpc.ReleaseManagerStub(channel)
time.sleep(1.0)
responses = []
for service_name, value in SEQUENCE:
    response = stub.SendMetric(
        deployment_pb2.Metric(service_name=service_name, health_value=value),
        timeout=5,
    )
    responses.append(bool(response.approved))
    time.sleep(0.2)
with open(RESPONSES_PATH, "w") as output:
    json.dump(responses, output)
time.sleep(1.0)
channel.close()
'''

    listener_source = '''import asyncio
import websockets

async def listen():
    try:
        async with websockets.connect("ws://localhost:8765") as websocket:
            with open("/home/user/alerts.log", "a") as output:
                while True:
                    message = await websocket.recv()
                    output.write(message + "\\n")
                    output.flush()
    except Exception:
        pass

asyncio.run(listen())
'''

    try:
        with open(client_path, "w") as f:
            f.write(client_source)
        with open(listener_path, "w") as f:
            f.write(listener_source)
        if os.path.exists(alerts_path):
            os.remove(alerts_path)
        if os.path.exists(responses_path):
            os.remove(responses_path)

        result = subprocess.run(
            ["bash", "/home/user/run_e2e.sh"],
            capture_output=True,
            text=True,
            timeout=35,
        )
    finally:
        with open(client_path, "wb") as f:
            f.write(original_client)
        with open(listener_path, "wb") as f:
            f.write(original_listener)

    assert result.returncode == 0, (
        f"dynamic run_e2e.sh failed with exit code {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(responses_path), "The provided gRPC client was not run"
    with open(responses_path) as f:
        approvals = json.load(f)
    assert approvals == expected_approvals

    assert os.path.isfile(alerts_path), "The WebSocket listener did not receive any alerts"
    with open(alerts_path) as f:
        alert_lines = [line.strip() for line in f if line.strip()]
    actual_alerts = [json.loads(line) for line in alert_lines]
    assert actual_alerts == expected_alerts
    assert wait_for_ports_closed(), "run_e2e.sh did not terminate its background processes"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
