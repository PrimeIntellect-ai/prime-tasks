#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import socket
import hashlib
import pytest
import glob

def test_storage_directory_exists():
    storage_dir = "/home/user/upload_service/storage"
    assert os.path.isdir(storage_dir), f"Directory {storage_dir} does not exist."

def test_required_files_exist():
    base_dir = "/home/user/upload_service"
    required_files = ["upload.proto", "server.py", "client.py", "test.bin", "result.txt"]
    for f in required_files:
        path = os.path.join(base_dir, f)
        assert os.path.isfile(path), f"Required file {path} is missing."

def test_test_bin_size_and_checksum():
    test_bin_path = "/home/user/upload_service/test.bin"
    size = os.path.getsize(test_bin_path)
    # The spec says "generate a 5MB random binary file". We check if it's roughly 5MB.
    # 5MB could be 5,000,000 or 5,242,880 bytes.
    assert size >= 5000000, f"{test_bin_path} is smaller than 5MB."

    # Read client output
    result_path = "/home/user/upload_service/result.txt"
    with open(result_path, "r") as f:
        result_content = f.read().strip()

    # Extract the SHA-256 hex digest (64 hex characters)
    # It might be embedded in some text, so let's look for a 64-char hex string
    import re
    match = re.search(r'[a-fA-F0-9]{64}', result_content)
    assert match is not None, f"Could not find a valid SHA-256 checksum in {result_path}."
    client_sha256 = match.group(0).lower()

    # Compute actual SHA-256 of test.bin
    hasher = hashlib.sha256()
    with open(test_bin_path, "rb") as f:
        while chunk := f.read(8192):
            hasher.update(chunk)
    actual_sha256 = hasher.hexdigest()

    assert client_sha256 == actual_sha256, f"Checksum in {result_path} ({client_sha256}) does not match actual SHA-256 of {test_bin_path} ({actual_sha256})."

def test_server_listening():
    # Check if port 50051 is open
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1)
    try:
        result = s.connect_ex(('127.0.0.1', 50051))
        assert result == 0, "Server is not listening on port 50051."
    finally:
        s.close()

def test_uploaded_file_in_storage():
    storage_dir = "/home/user/upload_service/storage"
    test_bin_path = "/home/user/upload_service/test.bin"

    hasher = hashlib.sha256()
    with open(test_bin_path, "rb") as f:
        while chunk := f.read(8192):
            hasher.update(chunk)
    expected_sha256 = hasher.hexdigest()

    # Find if any file in storage matches the test.bin checksum
    found = False
    for filename in os.listdir(storage_dir):
        filepath = os.path.join(storage_dir, filename)
        if os.path.isfile(filepath):
            file_hasher = hashlib.sha256()
            with open(filepath, "rb") as f:
                while chunk := f.read(8192):
                    file_hasher.update(chunk)
            if file_hasher.hexdigest() == expected_sha256:
                found = True
                break

    assert found, "Could not find the uploaded test file in the storage directory with the matching checksum."
TEST_EOF

cat << 'RPC_EOF' > /tmp/test_upload_rpc.py
import hashlib
import os
import sys
import uuid
import zlib

import grpc
from google.protobuf import descriptor_pb2

sys.path.insert(0, "/home/user/upload_service")
import upload_pb2
import upload_pb2_grpc

# Verify the generated protobuf schema, including package, RPC streaming shape,
# oneof membership, field numbers, and field types.
fdp = descriptor_pb2.FileDescriptorProto()
fdp.ParseFromString(upload_pb2.DESCRIPTOR.serialized_pb)
assert fdp.syntax == "proto3"
assert fdp.package == "upload"
messages = {m.name: m for m in fdp.message_type}
services = {s.name: s for s in fdp.service}
assert {"UploadRequest", "Metadata", "Chunk", "UploadResponse"}.issubset(messages)
assert "FileUploadService" in services

service = services["FileUploadService"]
methods = {m.name: m for m in service.method}
assert "UploadFile" in methods
method = methods["UploadFile"]
assert method.client_streaming and not method.server_streaming
assert method.input_type == ".upload.UploadRequest"
assert method.output_type == ".upload.UploadResponse"

request = messages["UploadRequest"]
assert len(request.oneof_decl) == 1
assert request.oneof_decl[0].name == "payload"
request_fields = {f.name: f for f in request.field}
assert request_fields["metadata"].number == 1
assert request_fields["metadata"].type == request_fields["metadata"].TYPE_MESSAGE
assert request_fields["metadata"].type_name == ".upload.Metadata"
assert request_fields["metadata"].oneof_index == 0
assert request_fields["chunk"].number == 2
assert request_fields["chunk"].type == request_fields["chunk"].TYPE_MESSAGE
assert request_fields["chunk"].type_name == ".upload.Chunk"
assert request_fields["chunk"].oneof_index == 0

metadata_fields = {f.name: f for f in messages["Metadata"].field}
assert metadata_fields["filename"].number == 1
assert metadata_fields["filename"].type == metadata_fields["filename"].TYPE_STRING
chunk_fields = {f.name: f for f in messages["Chunk"].field}
assert chunk_fields["data"].number == 1
assert chunk_fields["data"].type == chunk_fields["data"].TYPE_BYTES
assert chunk_fields["crc32"].number == 2
assert chunk_fields["crc32"].type == chunk_fields["crc32"].TYPE_UINT32
response_fields = {f.name: f for f in messages["UploadResponse"].field}
assert response_fields["message"].number == 1
assert response_fields["message"].type == response_fields["message"].TYPE_STRING
assert response_fields["sha256_checksum"].number == 2
assert response_fields["sha256_checksum"].type == response_fields["sha256_checksum"].TYPE_STRING

channel = grpc.insecure_channel("127.0.0.1:50051")
grpc.channel_ready_future(channel).result(timeout=5)
stub = upload_pb2_grpc.FileUploadServiceStub(channel)

# Use verifier-generated content and irregular chunk boundaries so the response
# and assembled file cannot be satisfied by a precomputed fixed answer.
content = os.urandom(196731)
filename = "verifier_" + uuid.uuid4().hex + ".bin"
expected = hashlib.sha256(content).hexdigest()

def valid_requests():
    yield upload_pb2.UploadRequest(metadata=upload_pb2.Metadata(filename=filename))
    sizes = [1, 17, 4093, 65536, 777]
    offset = 0
    i = 0
    while offset < len(content):
        data = content[offset:offset + sizes[i % len(sizes)]]
        offset += len(data)
        i += 1
        yield upload_pb2.UploadRequest(
            chunk=upload_pb2.Chunk(data=data, crc32=zlib.crc32(data) & 0xFFFFFFFF)
        )

response = stub.UploadFile(valid_requests(), timeout=15)
assert response.sha256_checksum == expected
saved_path = os.path.join("/home/user/upload_service/storage", filename)
assert os.path.isfile(saved_path)
with open(saved_path, "rb") as f:
    assert f.read() == content

# The first stream message must be metadata.
def chunk_first_requests():
    data = os.urandom(31)
    yield upload_pb2.UploadRequest(
        chunk=upload_pb2.Chunk(data=data, crc32=zlib.crc32(data) & 0xFFFFFFFF)
    )

try:
    stub.UploadFile(chunk_first_requests(), timeout=5)
    raise AssertionError("UploadFile accepted a stream whose first message was a chunk")
except grpc.RpcError as exc:
    assert exc.code() == grpc.StatusCode.INVALID_ARGUMENT, exc.code()

# A bad per-chunk CRC must abort with DATA_LOSS and the specified detail.
def bad_crc_requests():
    yield upload_pb2.UploadRequest(metadata=upload_pb2.Metadata(filename="bad_" + uuid.uuid4().hex))
    data = os.urandom(113)
    good_crc = zlib.crc32(data) & 0xFFFFFFFF
    yield upload_pb2.UploadRequest(
        chunk=upload_pb2.Chunk(data=data, crc32=(good_crc + 1) & 0xFFFFFFFF)
    )

try:
    stub.UploadFile(bad_crc_requests(), timeout=5)
    raise AssertionError("UploadFile accepted a chunk with an invalid CRC32")
except grpc.RpcError as exc:
    assert exc.code() == grpc.StatusCode.DATA_LOSS, exc.code()
    assert exc.details() == "Invalid CRC32", exc.details()
RPC_EOF

if (
    cd /home/user/upload_service &&
    timeout 60s python3 client.py > /tmp/upload_client_stdout.txt 2>&1
) && grep -Eq '[a-fA-F0-9]{64}' /tmp/upload_client_stdout.txt \
  && python3 -m pytest /tmp/test_final_state.py -x --tb=short \
  && python3 /tmp/verify.py \
  && python3 /tmp/test_upload_rpc.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
