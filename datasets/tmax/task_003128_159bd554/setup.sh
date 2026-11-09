#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > math_lib.c
#include <stdint.h>
#include <stddef.h>

uint32_t calculate_checksum(const uint8_t* data, size_t length) {
    uint32_t hash = 0x811c9dc5;
    for (size_t i = 0; i < length; i++) {
        hash ^= data[i];
        hash *= 0x01000193;
    }
    return hash;
}
EOF

    cat << 'EOF' > app.py
import ctypes
import time
import json
import os

# Pure Python version for benchmarking
def py_checksum(data: bytes) -> int:
    hash_val = 0x811c9dc5
    for byte in data:
        hash_val ^= byte
        hash_val = (hash_val * 0x01000193) & 0xFFFFFFFF
    return hash_val

def main():
    lib = ctypes.CDLL('./libmath_lib.so')

    # BUGGY ABI DEFINITIONS - AGENT MUST FIX THESE
    lib.calculate_checksum.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.calculate_checksum.restype = ctypes.c_int

    with open('/home/user/payload.bin', 'rb') as f:
        data = f.read()

    # Benchmark C version
    start = time.time()
    # AGENT MAY NEED TO FIX HOW DATA IS PASSED HERE DEPENDING ON ARGTYPES
    c_result = lib.calculate_checksum(data, len(data))
    c_time = time.time() - start

    # Benchmark Py version
    start = time.time()
    py_result = py_checksum(data)
    py_time = time.time() - start

    # Mask to 32-bit unsigned to handle potential c_int signedness issues from the bug
    c_result_unsigned = c_result & 0xFFFFFFFF

    if c_result_unsigned != py_result:
        print(f"Checksum mismatch! C: {c_result_unsigned}, Py: {py_result}")
        return

    with open('/home/user/results.json', 'w') as f:
        json.dump({
            "checksum": py_result,
            "c_faster_than_py": c_time < py_time
        }, f)

if __name__ == "__main__":
    main()
EOF

    dd if=/dev/urandom of=/home/user/payload.bin bs=1K count=1024 status=none
    printf '\x00\x00\x00\x00' | dd of=/home/user/payload.bin bs=1 seek=100 count=4 conv=notrunc status=none

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
