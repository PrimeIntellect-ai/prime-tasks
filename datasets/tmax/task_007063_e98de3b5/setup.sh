#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/ticket_4489

    # Create the C source for the library with an intentional off-by-one bug
    cat << 'EOF' > /home/user/ticket_4489/calc.c
#include <stdio.h>

// Bug: loop goes up to i <= length, which accesses data[length], causing out-of-bounds
// If length is exactly the allocated size of the array, it might segfault.
double fast_moving_avg(double* data, int length) {
    double sum = 0;
    for (int i = 0; i <= length; i++) {
        sum += data[i];
    }
    return sum / length;
}
EOF

    gcc -shared -o /home/user/ticket_4489/libcalc.so -fPIC /home/user/ticket_4489/calc.c
    rm /home/user/ticket_4489/calc.c

    # Create the Python script
    cat << 'EOF' > /home/user/ticket_4489/summarize.py
import ctypes
import os

# Load the library
lib_path = os.path.join(os.path.dirname(__file__), 'libcalc.so')
lib = ctypes.CDLL(lib_path)
lib.fast_moving_avg.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
lib.fast_moving_avg.restype = ctypes.c_double

def sum_values(values):
    # Bug: standard summation causes floating point precision loss
    total = 0.0
    for v in values:
        total += v
    return total

def fast_process(values):
    # Convert list to ctypes array
    arr_type = ctypes.c_double * len(values)
    arr = arr_type(*values)
    # The C function has an off-by-one. Passing len(values) makes it read arr[len(values)]
    # which is out of bounds. The fix is to pass len(values) - 1.
    return lib.fast_moving_avg(arr, len(values))
EOF

    chmod +x /home/user/ticket_4489/summarize.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
