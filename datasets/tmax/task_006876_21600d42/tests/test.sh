#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any server left running by the agent so the submitted server can be
# launched and tested against a verifier-controlled manifest.
pkill -9 -f 'python[^ ]* .*server\.py|python[^ ]* server\.py' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import struct
import subprocess
import sys
import tempfile
import time

import grpc
from google.protobuf import descriptor_pb2

HOME = "/home/user"


def test_proto_file_exists():
    proto_path = "/home/user/shim.proto"
    assert os.path.isfile(proto_path), f"File {proto_path} is missing."

    with open(proto_path, 'r') as f:
        content = f.read()

    assert "package pipeline;" in content, "Proto file does not define package 'pipeline'."
    assert "service ShimBuilder" in content, "Proto file does not define service 'ShimBuilder'."
    assert "ShimRequest" in content, "Proto file does not define message 'ShimRequest'."
    assert "ShimResponse" in content, "Proto file does not define message 'ShimResponse'."


def test_proto_generated_files_exist():
    pb2_path = "/home/user/shim_pb2.py"
    pb2_grpc_path = "/home/user/shim_pb2_grpc.py"

    assert os.path.isfile(pb2_path), f"Generated file {pb2_path} is missing."
    assert os.path.isfile(pb2_grpc_path), f"Generated file {pb2_grpc_path} is missing."


def test_server_and_client_exist():
    assert os.path.isfile("/home/user/server.py"), "server.py is missing."
    assert os.path.isfile("/home/user/client.py"), "client.py is missing."


def test_output_bin_exists_and_executable():
    bin_path = "/home/user/output_bin"
    assert os.path.isfile(bin_path), f"Output binary {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"Output binary {bin_path} is not executable."


def test_output_bin_execution():
    bin_path = "/home/user/output_bin"
    assert os.path.isfile(bin_path), f"Output binary {bin_path} is missing."

    result = subprocess.run([bin_path], capture_output=True)
    assert result.returncode == 105, f"Expected exit code 105, got {result.returncode}."


def _validate_file_descriptor(fd):
    assert fd.package == "pipeline"

    messages = {m.name: m for m in fd.message_types_by_name.values()}
    assert "ShimRequest" in messages
    assert "ShimResponse" in messages

    request = messages["ShimRequest"]
    response = messages["ShimResponse"]
    assert len(request.fields) == 1
    assert request.fields[0].name == "job_id"
    assert request.fields[0].number == 1
    assert request.fields[0].type == request.fields[0].TYPE_STRING
    assert len(response.fields) == 1
    assert response.fields[0].name == "executable_payload"
    assert response.fields[0].number == 1
    assert response.fields[0].type == response.fields[0].TYPE_BYTES

    assert "ShimBuilder" in fd.services_by_name
    service = fd.services_by_name["ShimBuilder"]
    assert len(service.methods) == 1
    method = service.methods[0]
    assert method.name == "BuildShim"
    assert method.input_type.full_name == "pipeline.ShimRequest"
    assert method.output_type.full_name == "pipeline.ShimResponse"
    assert not method.client_streaming
    assert not method.server_streaming


def test_complete_proto_schema_and_generated_modules():
    descriptor_path = "/tmp/shim_descriptor.pb"
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "grpc_tools.protoc",
            "-I/home/user",
            f"--descriptor_set_out={descriptor_path}",
            "/home/user/shim.proto",
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr

    descriptor_set = descriptor_pb2.FileDescriptorSet()
    with open(descriptor_path, "rb") as f:
        descriptor_set.ParseFromString(f.read())
    assert len(descriptor_set.file) == 1
    source_fd = descriptor_set.file[0]
    assert source_fd.package == "pipeline"
    source_messages = {m.name: m for m in source_fd.message_type}
    assert set(source_messages) == {"ShimRequest", "ShimResponse"}
    req_fields = source_messages["ShimRequest"].field
    resp_fields = source_messages["ShimResponse"].field
    assert len(req_fields) == 1
    assert (req_fields[0].name, req_fields[0].number, req_fields[0].type) == (
        "job_id", 1, descriptor_pb2.FieldDescriptorProto.TYPE_STRING)
    assert len(resp_fields) == 1
    assert (resp_fields[0].name, resp_fields[0].number, resp_fields[0].type) == (
        "executable_payload", 1, descriptor_pb2.FieldDescriptorProto.TYPE_BYTES)
    assert len(source_fd.service) == 1
    service = source_fd.service[0]
    assert service.name == "ShimBuilder"
    assert len(service.method) == 1
    method = service.method[0]
    assert method.name == "BuildShim"
    assert method.input_type == ".pipeline.ShimRequest"
    assert method.output_type == ".pipeline.ShimResponse"
    assert not method.client_streaming and not method.server_streaming

    sys.path.insert(0, HOME)
    import shim_pb2
    import shim_pb2_grpc

    _validate_file_descriptor(shim_pb2.DESCRIPTOR)
    assert hasattr(shim_pb2_grpc, "ShimBuilderStub")
    assert hasattr(shim_pb2_grpc, "ShimBuilderServicer")
    assert hasattr(shim_pb2_grpc, "add_ShimBuilderServicer_to_server")


def _assembly(marker, exit_code):
    encoded = ", ".join(f"0x{b:02x}" for b in marker)
    return f"""global _start
section .data
msg: db {encoded}
msg_len equ $-msg
section .text
_start:
  mov rax, 1
  mov rdi, 1
  mov rsi, msg
  mov rdx, msg_len
  syscall
  mov rax, 60
  mov rdi, {exit_code}
  syscall
"""


def _check_elf_and_run(payload, marker, exit_code):
    assert isinstance(payload, bytes)
    assert payload[:4] == b"\x7fELF", "Service did not return an ELF file"
    assert payload[4] == 2, "Returned ELF is not 64-bit"
    assert struct.unpack_from("<H", payload, 16)[0] == 2, "ELF is not an executable"
    assert struct.unpack_from("<H", payload, 18)[0] == 62, "ELF is not x86_64"

    fd, path = tempfile.mkstemp(prefix="returned_shim_")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(payload)
        os.chmod(path, 0o755)
        result = subprocess.run([path], capture_output=True, timeout=5)
        assert result.returncode == exit_code
        assert result.stdout == marker
    finally:
        if os.path.exists(path):
            os.unlink(path)


def test_running_server_manifest_compilation_and_client():
    sys.path.insert(0, HOME)
    import shim_pb2
    import shim_pb2_grpc

    manifest_path = os.path.join(HOME, "build_manifest.json")
    with open(manifest_path, "rb") as f:
        original_manifest = f.read()

    token = secrets.token_hex(8).encode("ascii")
    target_marker = b"target-" + token + b"\n"
    other_marker = b"other-" + token + b"\n"
    target_code = 40 + secrets.randbelow(50)
    other_code = 120 + secrets.randbelow(50)
    if target_code == 105:
        target_code = 104

    manifest = [
        {
            "job_id": "unrelated-random-job",
            "status": "failed",
            "assembly_code": _assembly(other_marker, other_code),
        },
        {
            "job_id": "rust-fallback-44",
            "status": "failed",
            "assembly_code": _assembly(target_marker, target_code),
        },
    ]

    server = None
    channel = None
    try:
        with open(manifest_path, "w") as f:
            json.dump(manifest, f)

        if os.path.exists("/home/user/output_bin"):
            os.unlink("/home/user/output_bin")

        server = subprocess.Popen(
            [sys.executable, "/home/user/server.py"],
            cwd=HOME,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )

        # An [::] listener must be reachable over IPv6.
        channel = grpc.insecure_channel("[::1]:50051")
        try:
            grpc.channel_ready_future(channel).result(timeout=12)
        except Exception:
            stderr = server.stderr.read() if server.poll() is not None else ""
            raise AssertionError(f"Submitted server did not listen on [::]:50051: {stderr}")

        stub = shim_pb2_grpc.ShimBuilderStub(channel)
        other_response = stub.BuildShim(
            shim_pb2.ShimRequest(job_id="unrelated-random-job"), timeout=15)
        _check_elf_and_run(other_response.executable_payload, other_marker, other_code)

        target_response = stub.BuildShim(
            shim_pb2.ShimRequest(job_id="rust-fallback-44"), timeout=15)
        _check_elf_and_run(target_response.executable_payload, target_marker, target_code)

        client_result = subprocess.run(
            [sys.executable, "/home/user/client.py"],
            cwd=HOME,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert client_result.returncode == 0, client_result.stderr
        assert os.path.isfile("/home/user/output_bin")
        assert os.access("/home/user/output_bin", os.X_OK)
        result = subprocess.run(["/home/user/output_bin"], capture_output=True, timeout=5)
        assert result.returncode == target_code
        assert result.stdout == target_marker
    finally:
        if channel is not None:
            channel.close()
        if server is not None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
        with open(manifest_path, "wb") as f:
            f.write(original_manifest)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
