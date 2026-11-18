#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/pipeline

    # Generate memdump.bin with some binary garbage and the TXN ID
    head -c 1024 /dev/urandom > /home/user/pipeline/memdump.bin
    printf "CRASH_CONTEXT: TXN-A839F7X2 \0\0\0" >> /home/user/pipeline/memdump.bin
    head -c 1024 /dev/urandom >> /home/user/pipeline/memdump.bin

    # Create calc.c
    cat << 'EOF' > /home/user/pipeline/calc.c
#include <stdio.h>

double process_data(double* data, int len) {
    // BUG 2: numerical precision loss (float instead of double)
    float sum = 0.0;

    // BUG 1: off-by-one error (<= instead of <)
    for (int i = 0; i <= len; i++) {
        sum += data[i];
    }

    return (double)sum;
}
EOF

    # Create process.py
    cat << 'EOF' > /home/user/pipeline/process.py
import ctypes
import json
import os

# Load the shared library
lib = ctypes.CDLL('/home/user/pipeline/libcalc.so')
lib.process_data.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
lib.process_data.restype = ctypes.c_double

def run_pipeline():
    # Test data designed to show precision loss if float is used
    data = [100000000.0, 0.0000001, 0.0000002, 0.0000003] * 10000
    len_data = len(data)

    # Create C array
    c_array = (ctypes.c_double * len_data)(*data)

    # Run calculation
    result = lib.process_data(c_array, len_data)

    with open('/home/user/pipeline/results.json', 'w') as f:
        json.dump({"status": "success", "final_sum": result}, f)

if __name__ == "__main__":
    run_pipeline()
EOF

    # Compile the buggy version initially
    gcc -shared -o /home/user/pipeline/libcalc.so -fPIC /home/user/pipeline/calc.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
