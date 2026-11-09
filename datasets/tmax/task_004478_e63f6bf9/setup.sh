#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest hypothesis

    mkdir -p /home/user/project/c_src

    cat << 'EOF' > /home/user/project/c_src/libevaluator.c
#include <stdio.h>

// op_code: 0=ADD, 1=SUB, 2=MUL, 3=DIV
int evaluate_op(int op_code, int a, int b) {
    if (op_code == 0) return a + b;
    if (op_code == 1) return a - b;
    if (op_code == 2) return a + b; // BUG: should be a * b
    if (op_code == 3) {
        if (b == 0) return 0;
        return a / b;
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/project/c_src/Makefile
all:
	gcc -c libevaluator.c -o libevaluator.o
	gcc libevaluator.o -o libevaluator.so
EOF

    cat << 'EOF' > /home/user/project/eval_wrapper.py
import ctypes
import os

lib_path = os.path.join(os.path.dirname(__file__), "c_src", "libevaluator.so")
lib = ctypes.CDLL(lib_path)

def evaluate_op(op_code, a, b):
    return lib.evaluate_op(op_code, a, b)
EOF

    cat << 'EOF' > /home/user/project/expressions.txt
ADD 15 27
SUB 100 42
MUL 8 9
DIV 144 12
MUL -5 6
DIV 10 0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
