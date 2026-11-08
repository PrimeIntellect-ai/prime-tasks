#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest hypothesis

mkdir -p /home/user/math_vm
cd /home/user/math_vm

cat << 'EOF' > vm.c
#include <stdlib.h>

typedef struct {
    int opcode;
    int value;
} Instruction;

int execute_vm(Instruction* instrs, int count, int* result) {
    // BUG 1: Static tiny buffer. Will overflow on >10 pushes.
    int* stack = malloc(10 * sizeof(int)); 
    int sp = 0;

    for(int i = 0; i < count; i++) {
        if (instrs[i].opcode == 0) {
            stack[sp++] = instrs[i].value;
        } else {
            if (sp < 2) { 
                free(stack); 
                return -1; 
            }
            int b = stack[--sp];
            int a = stack[--sp];
            if (instrs[i].opcode == 1) stack[sp++] = a + b;
            else if (instrs[i].opcode == 2) stack[sp++] = a - b;
            else if (instrs[i].opcode == 3) stack[sp++] = a * b;
        }
    }

    if (sp != 1) { 
        free(stack); 
        return -1; 
    }

    *result = stack[0];

    // BUG 2: Missing free(stack) on success path (memory leak)
    return 0;
}
EOF

cat << 'EOF' > Makefile
all:
	gcc -shared -o libvm.so -fPIC vm.c
EOF

cat << 'EOF' > pyvm.py
import ctypes
import os

class Instruction(ctypes.Structure):
    _fields_ = [("opcode", ctypes.c_int),
                ("value", ctypes.c_int)]

# Load the compiled C library
lib_path = os.path.abspath("./libvm.so")
if os.path.exists(lib_path):
    lib = ctypes.CDLL(lib_path)
    lib.execute_vm.argtypes = [ctypes.POINTER(Instruction), ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
    lib.execute_vm.restype = ctypes.c_int

def execute_c(instructions):
    arr = (Instruction * len(instructions))()
    for i, (op, val) in enumerate(instructions):
        arr[i].opcode = op
        arr[i].value = val

    res = ctypes.c_int()
    status = lib.execute_vm(arr, len(instructions), ctypes.byref(res))
    if status != 0:
        raise ValueError("VM Error")
    return res.value

def execute_py(instructions):
    stack = []
    for op, val in instructions:
        if op == 0:
            stack.append(val)
        else:
            if len(stack) < 2:
                raise ValueError("VM Error")
            b = stack.pop()
            a = stack.pop()
            if op == 1: stack.append(a + b)
            elif op == 2: stack.append(a - b)
            elif op == 3: stack.append(a * b)

    if len(stack) != 1:
        raise ValueError("VM Error")
    return stack[0]
EOF

make

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
