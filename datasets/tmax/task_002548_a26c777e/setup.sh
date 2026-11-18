#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest pytest-json-report

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > data_client.py
import ctypes
import os

# Assume libdata.so is in the same directory
lib_path = os.path.join(os.path.dirname(__file__), 'libdata.so')
lib = ctypes.CDLL(lib_path)

def process_data(text: str) -> str:
    # A fake ctypes wrapper that actually just implements the socket logic in Python 
    # for the sake of the environment setup (since compiling a real libdata.so with C socket logic is complex for this truth block).
    # In the actual scenario described, the libdata.so would do this. 
    # For testing the agent's emulator, we do it in Python.
    import socket
    import struct

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('127.0.0.1', 8888))

    payload = text.encode('utf-8')
    header = struct.pack('>H', len(payload))
    s.sendall(header + payload)

    resp_header = s.recv(2)
    if not resp_header:
        return ""
    resp_len = struct.unpack('>H', resp_header)[0]
    resp_payload = s.recv(resp_len)

    s.close()
    return resp_payload.decode('utf-8')
EOF

    cat << 'EOF' > libdata.c
void backend_init();
void init() {
    backend_init();
}
EOF

    echo "void backend_init() {}" > temp_backend.c
    gcc -shared -fPIC temp_backend.c -o libbackend.so
    gcc -shared -fPIC libdata.c -o libdata.so -L. -lbackend
    rm temp_backend.c libbackend.so

    cat << 'EOF' > test_client.py
import data_client

def test_failure():
    assert True
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
