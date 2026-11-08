#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import os
import random
import string
import subprocess
import sys
import uuid

import pytest

PROJECT = "/home/user/project"
PROTO = os.path.join(PROJECT, "proto")
SRC = os.path.join(PROJECT, "src")
BUILD = os.path.join(PROJECT, "ci", "build.py")

SECURE_PROTO = '''// Version: 2.1.2
syntax = "proto3";
package auth;
service AuthService {
  rpc VerifyToken (TokenRequest) returns (TokenResponse);
}
message TokenRequest {
  string token = 1;
}
message TokenResponse {
  bool valid = 1;
}
'''


def test_ci_report():
    report_path = "/home/user/ci_report.txt"
    assert os.path.isfile(report_path), f"Log file {report_path} does not exist."
    with open(report_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 1, f"Expected exactly 1 line in ci_report.txt, got {len(content)}"
    assert "secure_service.proto" in content[0], "ci_report.txt does not contain 'secure_service.proto'."
    assert "vulnerable_service.proto" not in content[0], "ci_report.txt should not contain 'vulnerable_service.proto'."


def test_vulnerable_service_deleted():
    path = "/home/user/project/proto/vulnerable_service.proto"
    assert not os.path.exists(path), f"Vulnerable service file {path} should have been deleted."


def test_secure_service_exists_and_unchanged():
    path = "/home/user/project/proto/secure_service.proto"
    assert os.path.isfile(path), f"Secure service file {path} should exist."
    with open(path, "r") as f:
        assert f.read() == SECURE_PROTO, "secure_service.proto definitions were changed."
    assert not os.path.exists("/home/user/legacy_project/secure_service.proto"), "secure_service.proto was not moved."
    assert not os.path.exists("/home/user/legacy_project/vulnerable_service.proto"), "vulnerable_service.proto was not moved."


def test_compiled_protobufs_exist():
    pb2_path = "/home/user/project/src/secure_service_pb2.py"
    pb2_grpc_path = "/home/user/project/src/secure_service_pb2_grpc.py"
    assert os.path.isfile(pb2_path), f"Compiled protobuf file {pb2_path} does not exist."
    assert os.path.isfile(pb2_grpc_path), f"Compiled protobuf file {pb2_grpc_path} does not exist."


def test_server_pid_running():
    pid_path = "/home/user/server.pid"
    assert os.path.isfile(pid_path), f"PID file {pid_path} does not exist."
    with open(pid_path, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file {pid_path} does not contain a valid integer."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} is not running.")


def expected_token_result(token):
    return bool(token) and token.startswith("SECURE-") and len(token) >= 15 and "DROP" not in token


def test_grpc_server_logic_on_dynamic_inputs():
    try:
        import grpc
    except ImportError:
        pytest.fail("grpcio library is not installed.")

    sys.path.insert(0, SRC)
    try:
        import secure_service_pb2
        import secure_service_pb2_grpc
    except ImportError as e:
        pytest.fail(f"Failed to import generated protobuf modules: {e}")

    suffix = ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(24))
    tokens = [
        "SECURE-1234567890",
        "SECURE-SHORT",
        "SECURE-12345DROP",
        "INVALID-1234567890",
        "",
        "SECURE-" + suffix,
        "SECURE-" + suffix[:7],
        "SECURE-" + suffix[:8],
        "XSECURE-" + suffix,
        "SECURE-" + suffix[:5] + "DROP" + suffix[5:],
        "SECURE-" + suffix.lower().replace("drop", "dr0p"),
        "SECURE-" + suffix[:8] + "drop",
    ]

    channel = grpc.insecure_channel('localhost:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=5)
        stub = secure_service_pb2_grpc.AuthServiceStub(channel)
        for token in tokens:
            response = stub.VerifyToken(secure_service_pb2.TokenRequest(token=token), timeout=5)
            assert response.valid is expected_token_result(token), f"Wrong result for dynamically selected token {token!r}"
    except grpc.RpcError as e:
        pytest.fail(f"gRPC call failed: {e}")
    finally:
        channel.close()


def test_build_script_actually_scans_deletes_compiles_and_reports():
    assert os.path.isfile(BUILD), f"CI build script {BUILD} does not exist."
    assert set(name for name in os.listdir(PROTO) if name.endswith('.proto')) == {"secure_service.proto"}

    nonce = uuid.uuid4().hex
    low_name = f"below_{nonce}.proto"
    edge_name = f"edge_{nonce}.proto"
    high_name = f"high_{nonce}.proto"
    package = f"probe_{nonce}"

    def proto_text(version, message, service):
        return f'''// Version: {version}
syntax = "proto3";
package {package};
service {service} {{
  rpc Echo ({message}) returns ({message});
}}
message {message} {{
  string value = 1;
}}
'''

    fixtures = {
        low_name: proto_text("2.0.999", "LowMessage", "LowProbe"),
        edge_name: proto_text("2.1.0", "EdgeMessage", "EdgeProbe"),
        high_name: proto_text("12.4.3", "HighMessage", "HighProbe"),
    }
    generated_bases = [os.path.splitext(edge_name)[0], os.path.splitext(high_name)[0]]

    for name, content in fixtures.items():
        with open(os.path.join(PROTO, name), "w") as f:
            f.write(content)

    try:
        result = subprocess.run(
            [sys.executable, BUILD],
            cwd=os.path.dirname(BUILD),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"build.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

        assert not os.path.exists(os.path.join(PROTO, low_name)), "A dynamically named proto below 2.1.0 was not deleted."
        assert os.path.isfile(os.path.join(PROTO, edge_name)), "Version 2.1.0 must pass the version check."
        assert os.path.isfile(os.path.join(PROTO, high_name)), "A version above 2.1.0 must pass the version check."

        with open("/home/user/ci_report.txt", "r") as f:
            report_lines = [line.strip() for line in f if line.strip()]
        assert len(report_lines) == 3, f"Expected three compiled protos in report, got {report_lines!r}"
        assert set(report_lines) == {"secure_service.proto", edge_name, high_name}, "Report does not match dynamically scanned protos."

        sys.path.insert(0, SRC)
        importlib.invalidate_caches()
        for base, message, service in [
            (generated_bases[0], "EdgeMessage", "EdgeProbe"),
            (generated_bases[1], "HighMessage", "HighProbe"),
        ]:
            pb2_path = os.path.join(SRC, base + "_pb2.py")
            grpc_path = os.path.join(SRC, base + "_pb2_grpc.py")
            assert os.path.isfile(pb2_path), f"grpc_tools output {pb2_path} is missing."
            assert os.path.isfile(grpc_path), f"grpc_tools output {grpc_path} is missing."
            with open(pb2_path, "r", errors="replace") as f:
                assert "Generated by the protocol buffer compiler" in f.read(), f"{pb2_path} is not protoc-generated output."

            pb2 = importlib.import_module(base + "_pb2")
            pb2_grpc = importlib.import_module(base + "_pb2_grpc")
            descriptor = pb2.DESCRIPTOR
            assert descriptor.package == package
            assert message in descriptor.message_types_by_name
            assert descriptor.message_types_by_name[message].fields_by_name["value"].type == 9
            assert service in descriptor.services_by_name
            method = descriptor.services_by_name[service].methods_by_name["Echo"]
            assert method.input_type.full_name == f"{package}.{message}"
            assert method.output_type.full_name == f"{package}.{message}"
            assert hasattr(pb2_grpc, service + "Stub")
            assert hasattr(pb2_grpc, service + "Servicer")
            assert hasattr(pb2_grpc, "add_" + service + "Servicer_to_server")
    finally:
        for name in fixtures:
            path = os.path.join(PROTO, name)
            if os.path.exists(path):
                os.remove(path)
        for base in generated_bases:
            for suffix in ("_pb2.py", "_pb2_grpc.py"):
                path = os.path.join(SRC, base + suffix)
                if os.path.exists(path):
                    os.remove(path)
        if os.path.isfile(BUILD):
            subprocess.run([sys.executable, BUILD], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
