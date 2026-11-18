#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > math_ops.c
int add(int a, int b) { return a + b; }
int sub(int a, int b) { return a - b; }
EOF

    cat << 'EOF' > interpreter.py
import ctypes
import os
import sys

# Add tests directory to path to cause circularity issue conceptually based on old flat layout
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from test_config import DEBUG_MODE

lib = ctypes.CDLL('./libmath.so')

def evaluate(command_str):
    parts = command_str.strip().split()
    if parts[0] == 'ADD':
        return lib.add(int(parts[1]), int(parts[2]))
    elif parts[0] == 'SUB':
        return lib.sub(int(parts[1]), int(parts[2]))
    return 0
EOF

    cat << 'EOF' > test_config.py
from interpreter import evaluate
DEBUG_MODE = True
EOF

    cat << 'EOF' > test_interpreter.py
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '../src/pylib'))
from interpreter import evaluate

def test_add():
    assert evaluate("ADD 5 7") == 12
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
