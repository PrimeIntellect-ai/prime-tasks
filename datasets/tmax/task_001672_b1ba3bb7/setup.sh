#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential gcc
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo/src
    mkdir -p /home/user/repo/api
    mkdir -p /home/user/repo/data

    cat << 'EOF' > /home/user/repo/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MathService C ASM)

# Build the assembly shared library
add_library(fastmath SHARED src/fast_math.s)

# Build the C wrapper shared library
add_library(mathwrap SHARED src/wrapper.c)

# BUG: Missing link instruction
EOF

    cat << 'EOF' > /home/user/repo/src/fast_math.s
.global compute_poly
.text
compute_poly:
    # x in rdi, y in rsi
    # compute 3 * x^2 + 2 * y
    mov %rdi, %rax
    imul %rdi, %rax  # rax = x^2
    imul $3, %rax    # rax = 3 * x^2

    mov %rsi, %rcx
    add $2, %rcx     # BUG: This should be `imul $2, %rcx`

    add %rcx, %rax   # rax = 3x^2 + 2y
    ret
EOF

    cat << 'EOF' > /home/user/repo/src/wrapper.c
extern long compute_poly(long x, long y);

long compute_wrapper(long x, long y) {
    return compute_poly(x, y);
}
EOF

    cat << 'EOF' > /home/user/repo/api/server.py
from flask import Flask, request, jsonify
import ctypes

app = Flask(__name__)

# TODO: Agent must implement the ctypes loading and endpoint logic
@app.route('/compute', methods=['POST'])
def compute():
    pass

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    cat << 'EOF' > /home/user/repo/data/inputs.json
[
  {"input_x": 4, "input_y": 7},
  {"input_x": -2, "input_y": 10},
  {"input_x": 10, "input_y": 0},
  {"input_x": 1, "input_y": -5}
]
EOF

    chmod -R 777 /home/user
