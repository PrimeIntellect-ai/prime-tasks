#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/bin

    cat << 'EOF' > /home/user/project/src/libC.c
int funcC() { return 10; }
EOF

    cat << 'EOF' > /home/user/project/src/libB.c
int funcC();
int funcB() { return funcC() + 20; }
EOF

    cat << 'EOF' > /home/user/project/src/libA.c
int funcB();
int funcA() { return funcB() + 30; }
EOF

    cat << 'EOF' > /home/user/project/deps.txt
libC libB
libB libA
EOF

    cat << 'EOF' > /home/user/project/test_runner.py
import ctypes
import os
import json
import sys

# Verify mock config
try:
    with open("mock_config.json") as f:
        config = json.load(f)
        if not config.get("strict_mode"):
            print("Error: strict_mode is not true")
            sys.exit(1)
except FileNotFoundError:
    print("Error: mock_config.json not found")
    sys.exit(1)

# Load library A
try:
    # Requires LD_LIBRARY_PATH or similar to resolve libB and libC
    libA = ctypes.CDLL("./bin/libA.so")
    res = libA.funcA()
    print(f"Result_A: {res}")
    print("Status: SUCCESS")
    print("Platform: CI")
except Exception as e:
    print(f"Error loading library: {e}")
    sys.exit(1)
EOF

    cat << 'EOF' > /home/user/project/expected.txt
Platform: CI
Result_A: 60
Status: SUCCESS
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
