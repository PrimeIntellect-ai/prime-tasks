#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import subprocess
import sys

import pytest

PROJECT = "/home/user/project"


def test_shared_library_exists_and_valid():
    so_path = os.path.join(PROJECT, "libfastparser.so")
    makefile_path = os.path.join(PROJECT, "Makefile")

    assert os.path.isfile(makefile_path), f"{makefile_path} does not exist."
    with open(makefile_path, "r") as f:
        makefile = f.read()
    assert "-fPIC" in makefile, "The Makefile does not enable position-independent code with -fPIC."
    assert "-shared" in makefile, "The Makefile does not link libfastparser.so as a shared object."

    # Require a clean invocation of the requested default `make` target to create
    # the library, rather than trusting a pre-existing ELF file.
    if os.path.lexists(so_path):
        os.remove(so_path)
    build = subprocess.run(
        ["make"], cwd=PROJECT, text=True, capture_output=True, timeout=30
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"

    assert os.path.isfile(so_path), f"{so_path} does not exist. Did you run make?"

    # Preserve the original ELF shared-object assertions.
    with open(so_path, "rb") as f:
        magic = f.read(4)
        assert magic == b"\x7fELF", f"{so_path} is not a valid ELF file."
        f.seek(16)
        e_type = f.read(2)
        assert e_type in (b"\x03\x00", b"\x00\x03"), \
            f"{so_path} is not compiled as a shared object. Did you add -shared and -fPIC?"

    # Load and exercise the symbol implemented by fast_parser.c.
    lib = ctypes.CDLL(so_path)
    assert hasattr(lib, "parse_magic"), "libfastparser.so does not export parse_magic."
    lib.parse_magic.argtypes = [ctypes.c_char_p]
    lib.parse_magic.restype = ctypes.c_int
    assert lib.parse_magic(None) == 0
    for value in (b"", b"abc", b"different input"):
        assert lib.parse_magic(value) == 42


def test_grpc_files_generated():
    pb2_path = os.path.join(PROJECT, "service_pb2.py")
    pb2_grpc_path = os.path.join(PROJECT, "service_pb2_grpc.py")

    assert os.path.isfile(pb2_path), f"{pb2_path} does not exist. Did you generate the protobuf files?"
    assert os.path.isfile(pb2_grpc_path), f"{pb2_grpc_path} does not exist. Did you generate the gRPC protobuf files?"

    sys.path.insert(0, PROJECT)
    import service_pb2
    import service_pb2_grpc
    from google.protobuf import descriptor_pb2

    descriptor = descriptor_pb2.FileDescriptorProto()
    descriptor.ParseFromString(service_pb2.DESCRIPTOR.serialized_pb)
    assert descriptor.name == "service.proto"
    assert descriptor.syntax == "proto3"

    messages = {message.name: message for message in descriptor.message_type}
    assert set(messages) == {"Request", "Response"}

    request_fields = list(messages["Request"].field)
    assert len(request_fields) == 1
    assert request_fields[0].name == "payload"
    assert request_fields[0].number == 1
    assert request_fields[0].type == descriptor_pb2.FieldDescriptorProto.TYPE_STRING

    response_fields = list(messages["Response"].field)
    assert len(response_fields) == 1
    assert response_fields[0].name == "result"
    assert response_fields[0].number == 1
    assert response_fields[0].type == descriptor_pb2.FieldDescriptorProto.TYPE_INT32

    assert len(descriptor.service) == 1
    service = descriptor.service[0]
    assert service.name == "DataService"
    assert len(service.method) == 1
    method = service.method[0]
    assert method.name == "ProcessData"
    assert method.input_type == ".Request"
    assert method.output_type == ".Response"
    assert not method.client_streaming and not method.server_streaming

    assert hasattr(service_pb2_grpc, "DataServiceStub")
    assert hasattr(service_pb2_grpc, "DataServiceServicer")
    assert hasattr(service_pb2_grpc, "add_DataServiceServicer_to_server")


def test_server_rpc_and_result_log():
    # Exercise the generated bindings, shared library, and server together.
    sys.path.insert(0, PROJECT)
    import grpc
    import server
    import service_pb2
    import service_pb2_grpc

    grpc_server = server.serve()
    channel = grpc.insecure_channel("localhost:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=5)
        stub = service_pb2_grpc.DataServiceStub(channel)
        response = stub.ProcessData(service_pb2.Request(payload="runtime check"), timeout=5)
        assert response.result == 42
    finally:
        channel.close()
        grpc_server.stop(0).wait()

    log_path = "/home/user/result.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you run the test script and redirect output?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "SERVER_STARTED_SUCCESSFULLY" in content, \
        "The result.log does not contain the expected success message."

    # Actually run the demanded test script and require the saved log to match
    # its standard output, so a marker alone cannot substitute for a runnable server.
    run = subprocess.run(
        ["python3", os.path.join(PROJECT, "test_server.py")],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert run.returncode == 0, f"test_server.py failed:\n{run.stdout}\n{run.stderr}"
    assert "SERVER_STARTED_SUCCESSFULLY" in run.stdout
    assert content == run.stdout.strip(), \
        "result.log does not match the standard output of test_server.py."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
