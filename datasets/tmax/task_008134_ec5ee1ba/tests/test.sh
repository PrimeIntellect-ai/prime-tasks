#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /tmp/grpc_probe

cat << 'PROBE_EOF' > /tmp/grpc_probe/sitecustomize.py
import json
import os
import grpc

_EVENT_FILE = os.environ.get("GRPC_PROBE_EVENTS")

def _record(kind, **values):
    if not _EVENT_FILE:
        return
    with open(_EVENT_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps({"kind": kind, **values}, sort_keys=True) + "\n")

_real_server = grpc.server
_real_insecure_channel = grpc.insecure_channel

class _ServerProxy:
    def __init__(self, inner):
        self._inner = inner

    def add_insecure_port(self, address):
        result = self._inner.add_insecure_port(address)
        _record("add_port", address=str(address), result=result)
        return result

    def add_generic_rpc_handlers(self, handlers):
        handlers = tuple(handlers)
        names = []
        for handler in handlers:
            try:
                names.append(handler.service_name())
            except Exception:
                names.append(None)
        _record("add_generic_rpc_handlers", services=names)
        return self._inner.add_generic_rpc_handlers(handlers)

    def add_registered_method_handlers(self, service_name, method_handlers):
        _record("add_registered_method_handlers", service=str(service_name))
        return self._inner.add_registered_method_handlers(service_name, method_handlers)

    def start(self):
        _record("server_start")
        return self._inner.start()

    def stop(self, grace):
        _record("server_stop")
        return self._inner.stop(grace)

    def __getattr__(self, name):
        return getattr(self._inner, name)

class _UnaryUnaryProxy:
    def __init__(self, inner, method):
        self._inner = inner
        self._method = method.decode() if isinstance(method, bytes) else str(method)

    def __call__(self, request, *args, **kwargs):
        response = self._inner(request, *args, **kwargs)
        _record(
            "rpc",
            method=self._method,
            request_user_id=getattr(request, "user_id", None),
            response_token=getattr(response, "token", None),
        )
        return response

    def __getattr__(self, name):
        return getattr(self._inner, name)

class _ChannelProxy:
    def __init__(self, inner):
        self._inner = inner

    def unary_unary(self, method, *args, **kwargs):
        return _UnaryUnaryProxy(self._inner.unary_unary(method, *args, **kwargs), method)

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)

def _server(*args, **kwargs):
    _record("server_created")
    return _ServerProxy(_real_server(*args, **kwargs))

def _insecure_channel(target, *args, **kwargs):
    _record("channel", target=str(target))
    return _ChannelProxy(_real_insecure_channel(target, *args, **kwargs))

grpc.server = _server
grpc.insecure_channel = _insecure_channel
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import hashlib
import importlib
import json
import os
import subprocess
import sys
import uuid
from concurrent import futures

import grpc
import pytest

SCRIPT_PATH = "/home/user/test_gateway.py"
LOG_PATH = "/home/user/test_result.log"
EVENT_PATH = "/tmp/test_gateway_grpc_events.jsonl"

@pytest.fixture(scope="session", autouse=True)
def execute_test_gateway():
    """Run the submitted integration test with a fresh result log and observe its gRPC operations."""
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."
    for path in (LOG_PATH, EVENT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    existing = env.get("PYTHONPATH")
    env["PYTHONPATH"] = "/tmp/grpc_probe" + (os.pathsep + existing if existing else "")
    env["GRPC_PROBE_EVENTS"] = EVENT_PATH
    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"{SCRIPT_PATH} did not exit gracefully within 30 seconds: {exc}")

    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(EVENT_PATH), "The integration test performed no observed gRPC operations."
    with open(EVENT_PATH, "r", encoding="utf-8") as f:
        events = [json.loads(line) for line in f if line.strip()]

    assert any(e.get("kind") == "server_created" for e in events), "The test did not create a gRPC server."
    assert any(
        e.get("kind") == "add_port"
        and str(e.get("address", "")).endswith(":50051")
        and e.get("result") == 50051
        for e in events
    ), "The test did not successfully bind its server to port 50051."
    assert any(e.get("kind") == "server_start" for e in events), "The test did not start its gRPC server."
    assert any(
        e.get("kind") in ("add_generic_rpc_handlers", "add_registered_method_handlers")
        and (
            "api.v1.Gateway" in e.get("services", [])
            or e.get("service") == "api.v1.Gateway"
        )
        for e in events
    ), "The generated Gateway service was not registered with the server."
    assert any(
        e.get("kind") == "channel" and e.get("target") == "localhost:50051"
        for e in events
    ), "The test did not create an insecure channel to localhost:50051."
    assert any(
        e.get("kind") == "rpc"
        and e.get("method") == "/api.v1.Gateway/GetUserToken"
        and e.get("request_user_id") == "test_user"
        and e.get("response_token") == "granted_token_123"
        for e in events
    ), "The test did not complete the required GetUserToken RPC with the required request and response."


def test_missing_dep_txt():
    """Check that missing_dep.txt contains the correct missing dependency."""
    file_path = "/home/user/missing_dep.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "common/v2/types.proto", f"Expected 'common/v2/types.proto' in {file_path}, but got '{content}'"


def test_patch_applied():
    """Check that the patch was applied successfully to token.proto."""
    token_proto_path = "/home/user/proto_deps/auth/v2/token.proto"
    assert os.path.isfile(token_proto_path), f"File {token_proto_path} does not exist."
    with open(token_proto_path, "r") as f:
        content = f.read()
    assert 'import "common/v1/types.proto";' in content, f"Expected patched import 'common/v1/types.proto' in {token_proto_path}."
    assert 'import "common/v2/types.proto";' not in content, f"Buggy import 'common/v2/types.proto' is still present in {token_proto_path}."


def test_gen_directory_contents():
    """Check that the generated python gRPC files exist in the gen directory."""
    gen_dir = "/home/user/gen"
    assert os.path.isdir(gen_dir), f"Directory {gen_dir} does not exist."

    expected_files = [
        "api/v1/gateway_pb2.py",
        "api/v1/gateway_pb2_grpc.py"
    ]

    for f in expected_files:
        file_path = os.path.join(gen_dir, f)
        assert os.path.isfile(file_path), f"Expected generated file {file_path} does not exist."


def test_all_proto_files_were_compiled():
    gen_dir = "/home/user/gen"
    expected_files = [
        "core/v1/user_pb2.py",
        "core/v1/user_pb2_grpc.py",
        "auth/v2/token_pb2.py",
        "auth/v2/token_pb2_grpc.py",
        "common/v1/types_pb2.py",
        "common/v1/types_pb2_grpc.py",
    ]
    for relative_path in expected_files:
        path = os.path.join(gen_dir, relative_path)
        assert os.path.isfile(path), f"Expected generated file {path} does not exist."


def test_script_exists():
    """Check that the test_gateway.py script exists."""
    script_path = "/home/user/test_gateway.py"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."


def test_result_log():
    """Check that test_result.log contains exactly 'TEST_PASSED'."""
    log_path = "/home/user/test_result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. The test script might not have run or failed."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "TEST_PASSED", f"Expected 'TEST_PASSED' in {log_path}, but got '{content}'"


def test_generated_modules_and_gateway_rpc_are_functional():
    """Import the generated artifacts, validate their descriptors, and exercise a verifier-derived RPC."""
    gen_dir = "/home/user/gen"
    sys.path.insert(0, gen_dir)
    importlib.invalidate_caches()

    user_pb2 = importlib.import_module("core.v1.user_pb2")
    token_pb2 = importlib.import_module("auth.v2.token_pb2")
    types_pb2 = importlib.import_module("common.v1.types_pb2")
    gateway_pb2 = importlib.import_module("api.v1.gateway_pb2")
    gateway_pb2_grpc = importlib.import_module("api.v1.gateway_pb2_grpc")

    assert user_pb2.UserRequest.DESCRIPTOR.full_name == "core.v1.UserRequest"
    assert token_pb2.TokenResponse.DESCRIPTOR.full_name == "auth.v2.TokenResponse"
    assert types_pb2.Status.DESCRIPTOR.full_name == "common.v1.Status"
    service = gateway_pb2.DESCRIPTOR.services_by_name["Gateway"]
    method = service.methods_by_name["GetUserToken"]
    assert method.input_type.full_name == "core.v1.UserRequest"
    assert method.output_type.full_name == "auth.v2.TokenResponse"
    assert hasattr(gateway_pb2_grpc, "GatewayStub")
    assert hasattr(gateway_pb2_grpc, "GatewayServicer")
    assert hasattr(gateway_pb2_grpc, "add_GatewayServicer_to_server")

    requested_user = "verify_" + uuid.uuid4().hex
    expected_token = hashlib.sha256(requested_user.encode("utf-8")).hexdigest()

    class VerifierGateway(gateway_pb2_grpc.GatewayServicer):
        def GetUserToken(self, request, context):
            assert isinstance(request, user_pb2.UserRequest)
            return token_pb2.TokenResponse(
                token=hashlib.sha256(request.user_id.encode("utf-8")).hexdigest()
            )

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=2))
    gateway_pb2_grpc.add_GatewayServicer_to_server(VerifierGateway(), server)
    port = server.add_insecure_port("127.0.0.1:0")
    assert port > 0
    server.start()
    channel = grpc.insecure_channel(f"127.0.0.1:{port}")
    try:
        grpc.channel_ready_future(channel).result(timeout=5)
        stub = gateway_pb2_grpc.GatewayStub(channel)
        response = stub.GetUserToken(user_pb2.UserRequest(user_id=requested_user), timeout=5)
        assert isinstance(response, token_pb2.TokenResponse)
        assert response.token == expected_token
    finally:
        channel.close()
        server.stop(0).wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
