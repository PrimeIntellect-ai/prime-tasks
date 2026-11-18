#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/math_service.py
import sys
import base64
import zlib
import json

def process(payload):
    try:
        decoded = base64.b64decode(payload)
        decompressed = zlib.decompress(decoded)
        data = json.loads(decompressed)
        matrix = data.get("matrix")
        if not matrix or len(matrix) != 2 or len(matrix[0]) != 2:
            return
        det = matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]
        assert det != 0, "Singular matrix not allowed in processing pipeline"
        print("Success, determinant:", det)
    except Exception as e:
        if isinstance(e, AssertionError):
            raise e
        pass

if __name__ == "__main__":
    if len(sys.argv) > 1:
        process(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/setup_dump.py
import os
import random

payload1 = b"eJyrVkrLz1eyUkpKLFKyUjA01FFQMigw1VEwNFAwVNJRKi0oyi9KLQaKmRkYGOsoGZroKBmYWgAASY4Qdw=="
payload2 = b"eJyrVkrLz1eyUkpKLFKyUjAy11FQMigw1VEwMFAwVNJRKi0oyi9KLQaKGZkYGOsoGZrpKBmYmAAASV8Qcw=="
payload3 = b"eJyrVkrLz1eyUkpKLFKyUjA001FQMigw11EwMVAwVNJRKi0oyi9KLQaKGZkZGOsoGRjoKBmYWwAASVoQeA=="

with open('/home/user/process.dmp', 'wb') as f:
    f.write(os.urandom(1024))
    f.write(payload1)
    f.write(os.urandom(2048))
    f.write(payload2)
    f.write(os.urandom(512))
    f.write(payload3)
    f.write(os.urandom(1024))
EOF

    python3 /home/user/setup_dump.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
