#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /app/libfastcrc

cat << 'EOF' > /app/libfastcrc/fastcrc.c
#include <stdint.h>
#include <stddef.h>

// Poorly optimized reference code
uint32_t compute_checksum_and_serialize(const uint8_t* data, size_t len) {
    uint32_t checksum = 0;
    for (size_t i = 0; i < len; i++) {
        // Unnecessary inner loop causing performance drop
        for (size_t j = 0; j < 100; j++) {
            checksum ^= (data[i] << (j % 8));
        }
        checksum += data[i];
    }
    return checksum;
}
EOF

cat << 'EOF' > /app/libfastcrc/Makefile
all: fastcrc.o
	gcc -o libfastcrc.so fastcrc.o

fastcrc.o: fastcrc.c
	gcc -c fastcrc.c -o fastcrc.o
EOF

cat << 'EOF' > /app/benchmark.py
import ctypes
import time
import os
import sys

def py_checksum(data):
    checksum = 0
    for i in range(len(data)):
        for j in range(100):
            checksum ^= (data[i] << (j % 8))
            checksum &= 0xFFFFFFFF
        checksum = (checksum + data[i]) & 0xFFFFFFFF
    return checksum

def main():
    if not os.path.exists('/app/libfastcrc/libfastcrc.so'):
        print("0.0")
        return

    lib = ctypes.CDLL('/app/libfastcrc/libfastcrc.so')
    lib.compute_checksum_and_serialize.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    lib.compute_checksum_and_serialize.restype = ctypes.c_uint32

    data = bytes(os.urandom(10000))
    c_data = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)

    # Warmup
    py_checksum(data[:10])
    lib.compute_checksum_and_serialize(c_data, 10)

    start = time.time()
    for _ in range(10):
        py_checksum(data)
    py_time = time.time() - start

    start = time.time()
    for _ in range(10):
        lib.compute_checksum_and_serialize(c_data, len(data))
    c_time = time.time() - start

    if c_time == 0:
        c_time = 0.000001

    speedup = py_time / c_time
    print(f"Speedup: {speedup:.2f}")

    # Write just the float for the verifier
    with open('/tmp/metric.txt', 'w') as f:
        f.write(str(speedup))

if __name__ == '__main__':
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
