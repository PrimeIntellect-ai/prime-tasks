#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/math_project

    cat << 'EOF' > /home/user/math_project/fastmath.c
#include <stdint.h>

// Computes A_n = (3*A_{n-1} + 2*A_{n-2}) mod 998244353
uint64_t compute_seq(uint32_t n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    uint64_t a = 0;
    uint64_t b = 1;
    uint64_t c;
    for (uint32_t i = 2; i <= n; i++) {
        c = (3 * b + 2 * a) % 998244353;
        a = b;
        b = c;
    }
    return b;
}
EOF

    cat << 'EOF' > /home/user/math_project/math_wrapper.py
import ctypes
import os

# BUG: Doesn't handle path correctly, CI will fail if run from different dir
# BUG: Missing argtypes and restype
lib = ctypes.CDLL("libfastmath.so")

def get_seq(n):
    return lib.compute_seq(n)
EOF

    cat << 'EOF' > /home/user/math_project/test_math.py
import sys
import os

# Ensure the module can be imported
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from math_wrapper import get_seq

def test_compute():
    val_10 = get_seq(10)
    assert val_10 == 139811, f"Expected 139811 for n=10, got {val_10}"

    val_100 = get_seq(100)
    assert val_100 == 826435372, f"Expected 826435372 for n=100, got {val_100}"

    print("ALL TESTS PASSED")

if __name__ == "__main__":
    test_compute()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
