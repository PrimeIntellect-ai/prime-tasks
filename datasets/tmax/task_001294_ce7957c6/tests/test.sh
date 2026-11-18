#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PROBE_EOF' > /tmp/verifier_probe_bridge.py
#!/usr/bin/env python3
import asyncio
import os
import signal

import grpc
import websockets

MARKER = "/tmp/pipeline_probe_events.log"
clients = set()


def mark(text):
    with open(MARKER, "a", encoding="utf-8") as f:
        f.write(text + "\n")


def decode_message(data):
    fields = {}
    pos = 0
    while pos < len(data):
        key = data[pos]
        pos += 1
        field = key >> 3
        wire = key & 7
        if wire != 2:
            raise ValueError("unexpected protobuf wire type")
        length = 0
        shift = 0
        while True:
            b = data[pos]
            pos += 1
            length |= (b & 0x7f) << shift
            if not b & 0x80:
                break
            shift += 7
        value = data[pos:pos + length].decode("utf-8")
        pos += length
        fields[field] = value
    return fields


async def broadcast_log(request, context):
    fields = decode_message(request)
    level = fields.get(1, "")
    payload = fields.get(2, "")
    mark("GRPC:" + level + ":" + payload)
    for ws in list(clients):
        await ws.send(payload)
    return b""


class Handler(grpc.GenericRpcHandler):
    def service(self, details):
        if details.method != "/monitor.PipelineMonitor/BroadcastLog":
            return None
        return grpc.unary_unary_rpc_method_handler(
            broadcast_log,
            request_deserializer=lambda value: value,
            response_serializer=lambda value: value,
        )


async def websocket_handler(ws, path=None):
    clients.add(ws)
    mark("WEBSOCKET_CONNECTED")
    try:
        await ws.wait_closed()
    finally:
        clients.discard(ws)


async def main():
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass

    grpc_server = grpc.aio.server()
    grpc_server.add_generic_rpc_handlers((Handler(),))
    grpc_server.add_insecure_port("localhost:50051")
    await grpc_server.start()
    websocket_server = await websockets.serve(websocket_handler, "localhost", 8765)
    mark("BRIDGE_STARTED:" + str(os.getpid()))
    try:
        await stop.wait()
    finally:
        websocket_server.close()
        await websocket_server.wait_closed()
        await grpc_server.stop(0)
        mark("BRIDGE_STOPPED")


asyncio.run(main())
PROBE_EOF
chmod +x /tmp/verifier_probe_bridge.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import importlib
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid

import grpc
import pytest
import websockets

HOME = "/home/user"
LOG_FILE = "/home/user/dashboard_output.log"
MARKER = "/tmp/pipeline_probe_events.log"


def port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        return sock.connect_ex(("localhost", port)) == 0


def run_pipeline(timeout=30):
    proc = subprocess.Popen(
        ["/home/user/test_pipeline.sh"],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(f"test_pipeline.sh timed out. stdout: {stdout} stderr: {stderr}")
    return proc.returncode, stdout, stderr


def assert_dashboard_output():
    assert os.path.isfile(LOG_FILE), f"{LOG_FILE} was not created by test_pipeline.sh."
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "CI_BUILD_SUCCESS", (
        f"Expected 'CI_BUILD_SUCCESS' in {LOG_FILE}, got '{content}'."
    )


def test_files_exist_and_executable():
    assert os.path.isfile("/home/user/bridge.py"), "/home/user/bridge.py does not exist."
    assert os.path.isfile("/home/user/test_pipeline.sh"), "/home/user/test_pipeline.sh does not exist."
    assert os.access("/home/user/test_pipeline.sh", os.X_OK), "/home/user/test_pipeline.sh is not executable."
    assert os.path.isfile("/home/user/monitor_pb2.py"), "Generated monitor_pb2.py is missing."
    assert os.path.isfile("/home/user/monitor_pb2_grpc.py"), "Generated monitor_pb2_grpc.py is missing."


def test_generated_protobuf_code():
    sys.path.insert(0, HOME)
    try:
        pb2 = importlib.import_module("monitor_pb2")
        pb2_grpc = importlib.import_module("monitor_pb2_grpc")
    finally:
        sys.path.pop(0)

    descriptor = pb2.DESCRIPTOR
    assert descriptor.package == "monitor"
    assert set(descriptor.message_types_by_name) == {"LogMessage", "Empty"}
    log_message = descriptor.message_types_by_name["LogMessage"]
    assert [(f.name, f.number, f.type) for f in log_message.fields] == [
        ("level", 1, f.TYPE_STRING),
        ("payload", 2, f.TYPE_STRING),
    ]
    service = descriptor.services_by_name["PipelineMonitor"]
    assert len(service.methods) == 1
    method = service.methods[0]
    assert method.name == "BroadcastLog"
    assert method.input_type.full_name == "monitor.LogMessage"
    assert method.output_type.full_name == "monitor.Empty"
    assert hasattr(pb2_grpc, "PipelineMonitorStub")
    assert hasattr(pb2_grpc, "PipelineMonitorServicer")
    assert hasattr(pb2_grpc, "add_PipelineMonitorServicer_to_server")


def test_pipeline_script_execution():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    returncode, stdout, stderr = run_pipeline()
    assert returncode == 0, (
        f"test_pipeline.sh failed with return code {returncode}. "
        f"Stdout: {stdout} Stderr: {stderr}"
    )
    assert_dashboard_output()


def encode_varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7f
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def encode_log_message(level, payload):
    level_bytes = level.encode("utf-8")
    payload_bytes = payload.encode("utf-8")
    return (
        b"\x0a" + encode_varint(len(level_bytes)) + level_bytes
        + b"\x12" + encode_varint(len(payload_bytes)) + payload_bytes
    )


def raw_grpc_call(payload):
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=5)
        call = channel.unary_unary(
            "/monitor.PipelineMonitor/BroadcastLog",
            request_serializer=lambda value: value,
            response_deserializer=lambda value: value,
        )
        response = call(encode_log_message("INFO", payload), timeout=5)
        assert response == b""
    finally:
        channel.close()


async def exercise_actual_bridge():
    proc = subprocess.Popen(
        [sys.executable, "/home/user/bridge.py"],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        first = None
        deadline = time.monotonic() + 10
        last_error = None
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                stdout, stderr = proc.communicate()
                pytest.fail(f"bridge.py exited early. stdout: {stdout} stderr: {stderr}")
            try:
                first = await websockets.connect("ws://localhost:8765")
                break
            except Exception as exc:
                last_error = exc
                await asyncio.sleep(0.1)
        assert first is not None, f"Could not connect to bridge WebSocket server: {last_error}"

        second = await asyncio.wait_for(websockets.connect("ws://localhost:8765"), timeout=5)
        try:
            payloads = [
                "verify-" + uuid.uuid4().hex,
                "verify-" + uuid.uuid4().hex,
            ]
            for payload in payloads:
                await asyncio.to_thread(raw_grpc_call, payload)
                received = await asyncio.gather(
                    asyncio.wait_for(first.recv(), timeout=5),
                    asyncio.wait_for(second.recv(), timeout=5),
                )
                assert received == [payload, payload]

            with pytest.raises(asyncio.TimeoutError):
                await asyncio.wait_for(first.recv(), timeout=0.4)
            with pytest.raises(asyncio.TimeoutError):
                await asyncio.wait_for(second.recv(), timeout=0.4)
        finally:
            await first.close()
            await second.close()
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=5)
        proc.communicate()


def test_bridge_independent_grpc_to_websocket_broadcast():
    assert not port_in_use(50051), "Port 50051 was occupied before independent bridge test."
    assert not port_in_use(8765), "Port 8765 was occupied before independent bridge test."
    asyncio.run(exercise_actual_bridge())


def test_pipeline_really_uses_bridge_grpc_and_websocket():
    backup = "/tmp/agent_bridge_backup.py"
    shutil.copy2("/home/user/bridge.py", backup)
    if os.path.exists(MARKER):
        os.remove(MARKER)
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    try:
        shutil.copyfile("/tmp/verifier_probe_bridge.py", "/home/user/bridge.py")
        os.chmod("/home/user/bridge.py", 0o755)
        returncode, stdout, stderr = run_pipeline()
    finally:
        shutil.copy2(backup, "/home/user/bridge.py")

    assert returncode == 0, (
        f"test_pipeline.sh failed against the protocol probe with return code {returncode}. "
        f"Stdout: {stdout} Stderr: {stderr}"
    )
    assert_dashboard_output()
    assert os.path.isfile(MARKER), "test_pipeline.sh never started /home/user/bridge.py."
    with open(MARKER, "r", encoding="utf-8") as f:
        events = [line.strip() for line in f if line.strip()]
    assert any(event.startswith("BRIDGE_STARTED:") for event in events), (
        "test_pipeline.sh did not start the bridge."
    )
    assert "WEBSOCKET_CONNECTED" in events, (
        "test_pipeline.sh did not connect a WebSocket client to the bridge."
    )
    assert "GRPC:INFO:CI_BUILD_SUCCESS" in events, (
        "test_pipeline.sh did not make the required BroadcastLog gRPC call."
    )


def test_ports_cleaned_up():
    time.sleep(1)
    assert not port_in_use(50051), "Port 50051 is still in use. bridge.py was not properly cleaned up."
    assert not port_in_use(8765), "Port 8765 is still in use. bridge.py was not properly cleaned up."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
