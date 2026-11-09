#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc
    pip3 install pytest

    mkdir -p /home/user/tool/src
    mkdir -p /home/user/tool/build

    cat << 'EOF' > /home/user/tool/src/algo.c
#include <stdio.h>

int process_data(int val) {
    return val * 42;
}
EOF

    cat << 'EOF' > /home/user/tool/src/main.py
import ctypes
import os
import sys

# Verify dependency is installed
try:
    import requests
except ImportError:
    print("Error: requests library not found.")
    sys.exit(1)

# Load library
try:
    lib = ctypes.CDLL("libalgo.so")
except Exception as e:
    print(f"Error loading libalgo.so: {e}")
    sys.exit(1)

lib.process_data.argtypes = [ctypes.c_int]
lib.process_data.restype = ctypes.c_int

result = lib.process_data(10)

if result == 420:
    with open("/home/user/tool/build/output.txt", "w") as f:
        f.write("SUCCESS_420")
    print("Success")
    sys.exit(0)
else:
    print(f"Failed with result {result}")
    sys.exit(1)
EOF

    cat << 'EOF' > /home/user/tool/requirements.txt
requests==2.31.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/tool
    chmod -R 777 /home/user
