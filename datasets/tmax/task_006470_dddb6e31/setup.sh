#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/pr_review/src
    mkdir -p /home/user/pr_review/lib
    mkdir -p /home/user/pr_review/tests

    cat << 'EOF' > /home/user/pr_review/src/processor.c
#include <stdio.h>

double execute_magic(double val) {
    return val * 2.5;
}
EOF

    gcc -shared -o /home/user/pr_review/lib/libprocessor.so -fPIC /home/user/pr_review/src/processor.c

    cat << 'EOF' > /home/user/pr_review/src/vm.py
import json
import ctypes
import sys
import os

# Load shared library
lib_path = os.path.join(os.path.dirname(__file__), '../lib/libprocessor.so')
lib = ctypes.CDLL(lib_path)

# BUG: Missing ABI definitions
# lib.execute_magic.argtypes = [ctypes.c_double]
# lib.execute_magic.restype = ctypes.c_double

def verify_constraints(instructions):
    prev_op = None
    for instr in instructions:
        op = instr.get('op')
        args = instr.get('args', [])

        if op == 'add' and prev_op == 'add':
            return False

        if op == 'magic':
            # BUG: Broken constraint logic (rejects valid inputs)
            if args[0] > 0 and args[0] % 2 == 0:
                return False

        prev_op = op
    return True

def run_vm(payload_path):
    with open(payload_path, 'r') as f:
        data = json.load(f)

    instructions = data.get('instructions', [])

    if not verify_constraints(instructions):
        print("CONSTRAINT_VIOLATION")
        return

    state = 0.0
    for instr in instructions:
        op = instr['op']
        args = instr['args']
        if op == 'add':
            state += sum(args)
        elif op == 'magic':
            state += lib.execute_magic(args[0])

    with open('/home/user/pr_review/output.log', 'w') as f:
        f.write(f"SUCCESS: {int(state)}\n")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python vm.py <payload>")
        sys.exit(1)
    run_vm(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/pr_review/tests/test_payload.json
{
  "instructions": [
    {"op": "add", "args": [10, 5]},
    {"op": "magic", "args": [4]},
    {"op": "add", "args": [3]}
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
