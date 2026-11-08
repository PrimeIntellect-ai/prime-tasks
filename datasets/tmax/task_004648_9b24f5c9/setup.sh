#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest grpcio grpcio-tools protobuf flask

    mkdir -p /app/secscanner-1.0.4/secscanner

    cat << 'EOF' > /app/secscanner-1.0.4/setup.py
from setuptools import setup, find_packages

setup(
    name="secscanner",
    version="1.0.4",
    packages=find_packages(),
    install_requires=[
        "baddep==9.9.9"
    ]
)
EOF

    cat << 'EOF' > /app/secscanner-1.0.4/secscanner/__init__.py
from .redactor import redact_payload
EOF

    cat << 'EOF' > /app/secscanner-1.0.4/secscanner/redactor.py
import base64
import re

def redact_payload(encoded_payload):
    # Bug: using b32decode instead of b64decode
    decoded_bytes = base64.b32decode(encoded_payload)
    decoded_str = decoded_bytes.decode('utf-8')

    # Redact AWS API keys
    redacted_str = re.sub(r'AKIA[0-9A-Z]{16}', '[REDACTED]', decoded_str)
    return redacted_str
EOF

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/scanner.proto
syntax = "proto3";
service Scanner {
  rpc ScanPayload (ScanRequest) returns (ScanResponse) {}
}
message ScanRequest {
  string filepath = 1;
  string encoded_payload = 2;
}
message ScanResponse {
  string message = 1;
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
