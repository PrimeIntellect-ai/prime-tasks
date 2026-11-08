#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/pr-review
    cd /home/user/pr-review

    python3 -c "import os; open('input.bin', 'wb').write(bytes([1, 5, 10, 20, 50, 100]))"

    cat << 'EOF' > Makefile
CC=gcc
CFLAGS=-Wall -Werror

all: libvm.so

libvm.so: vm.c
	$(CC) $(CFLAGS) -o libvm.so vm.c
EOF

    cat << 'EOF' > vm.c
#include <stdint.h>

void execute_vm(uint8_t* bytecode, int bytecode_len, uint8_t* input, int input_len, uint8_t* output) {
    for (int i = 0; i < input_len; i++) {
        uint8_t stack[256];
        int sp = 0;
        int pc = 0;

        while (pc < bytecode_len) {
            uint8_t op = bytecode[pc++];
            if (op == 0x01) { // PUSH
                stack[sp++] = bytecode[pc++];
            } else if (op == 0x02) { // ADD (BUG: SUBTRACTS)
                uint8_t a = stack[--sp];
                uint8_t b = stack[--sp];
                stack[sp++] = b - a; // BUG HERE
            } else if (op == 0x03) { // SUB
                uint8_t a = stack[--sp];
                uint8_t b = stack[--sp];
                stack[sp++] = b - a;
            } else if (op == 0x04) { // MUL
                uint8_t a = stack[--sp];
                uint8_t b = stack[--sp];
                stack[sp++] = b * a;
            } else if (op == 0x05) { // LOAD_INPUT
                stack[sp++] = input[i];
            } else if (op == 0x06) { // STORE_OUTPUT
                output[i] = stack[--sp];
            } else if (op == 0x07) { // HALT
                break;
            } else {
                break; // Unknown opcode
            }
        }
    }
}
EOF

    cat << 'EOF' > test_vm.py
import ctypes
import os

lib = ctypes.CDLL(os.path.abspath("./libvm.so"))

# BUG: input_len and output_len argtypes are wrong (c_double instead of c_int)
lib.execute_vm.argtypes = [
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.c_int,
    ctypes.POINTER(ctypes.c_uint8),
    ctypes.c_double,
    ctypes.POINTER(ctypes.c_uint8)
]

def test_add():
    bytecode = bytes([0x05, 0x01, 0x05, 0x02, 0x06, 0x07]) # input + 5
    input_data = bytes([10])
    output_data = bytearray(1)

    b_arr = (ctypes.c_uint8 * len(bytecode)).from_buffer_copy(bytecode)
    i_arr = (ctypes.c_uint8 * len(input_data)).from_buffer_copy(input_data)
    o_arr = (ctypes.c_uint8 * len(output_data)).from_buffer(output_data)

    lib.execute_vm(b_arr, len(bytecode), i_arr, len(input_data), o_arr)
    assert output_data[0] == 15, f"Expected 15, got {output_data[0]}"

EOF

    cat << 'EOF' > process.py
import ctypes
import os
import json

lib = ctypes.CDLL(os.path.abspath("./libvm.so"))
lib.execute_vm.argtypes = [
    ctypes.POINTER(ctypes.c_uint8), ctypes.c_int,
    ctypes.POINTER(ctypes.c_uint8), ctypes.c_int,
    ctypes.POINTER(ctypes.c_uint8)
]

# TODO: Implement bytecode for y = 2*x + 7
BYTECODE = bytes([])

def main():
    with open("input.bin", "rb") as f:
        input_data = f.read()

    output_data = bytearray(len(input_data))

    b_arr = (ctypes.c_uint8 * len(BYTECODE)).from_buffer_copy(BYTECODE)
    i_arr = (ctypes.c_uint8 * len(input_data)).from_buffer_copy(input_data)
    o_arr = (ctypes.c_uint8 * len(output_data)).from_buffer(output_data)

    lib.execute_vm(b_arr, len(BYTECODE), i_arr, len(input_data), o_arr)

    with open("output.json", "w") as f:
        json.dump(list(output_data), f)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
