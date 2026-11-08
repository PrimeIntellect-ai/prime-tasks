#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest grpcio grpcio-tools

cat << 'EOF' > /tmp/verify.py
import sys
import grpc
import os
import zlib
import hashlib
import time

sys.path.insert(0, '/home/user/upload_service')
try:
    import upload_pb2
    import upload_pb2_grpc
except ImportError:
    print("Failed to import generated protobuf files.")
    sys.exit(1)

def test_valid_upload():
    channel = grpc.insecure_channel('localhost:50051')
    stub = upload_pb2_grpc.FileUploadServiceStub(channel)

    file_content = b"Hello, world! " * 1000
    expected_sha256 = hashlib.sha256(file_content).hexdigest()

    def generate_requests():
        yield upload_pb2.UploadRequest(metadata=upload_pb2.Metadata(filename="valid.txt"))

        chunk_size = 100
        for i in range(0, len(file_content), chunk_size):
            data = file_content[i:i+chunk_size]
            crc = zlib.crc32(data) & 0xFFFFFFFF
            yield upload_pb2.UploadRequest(chunk=upload_pb2.Chunk(data=data, crc32=crc))

    try:
        response = stub.UploadFile(generate_requests())
        if response.sha256_checksum != expected_sha256:
            print(f"Error: Expected SHA256 {expected_sha256}, got {response.sha256_checksum}")
            sys.exit(1)

        with open('/home/user/upload_service/storage/valid.txt', 'rb') as f:
            saved_content = f.read()
            if saved_content != file_content:
                print("Error: Saved file content does not match.")
                sys.exit(1)
    except Exception as e:
        print(f"Error during valid upload: {e}")
        sys.exit(1)

def test_invalid_upload():
    channel = grpc.insecure_channel('localhost:50051')
    stub = upload_pb2_grpc.FileUploadServiceStub(channel)

    def generate_requests():
        yield upload_pb2.UploadRequest(metadata=upload_pb2.Metadata(filename="invalid.txt"))
        data = b"Some bad data"
        # Deliberately wrong CRC
        yield upload_pb2.UploadRequest(chunk=upload_pb2.Chunk(data=data, crc32=12345))

    try:
        response = stub.UploadFile(generate_requests())
        print("Error: Server should have rejected invalid CRC32 but didn't.")
        sys.exit(1)
    except grpc.RpcError as e:
        if e.code() != grpc.StatusCode.DATA_LOSS:
            print(f"Error: Expected DATA_LOSS status, got {e.code()}")
            sys.exit(1)

if __name__ == '__main__':
    time.sleep(1) # Give server time if just started
    test_valid_upload()
    test_invalid_upload()
    print("Success")
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
