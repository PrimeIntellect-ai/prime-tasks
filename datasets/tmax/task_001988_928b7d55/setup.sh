#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/polyglot

cat << 'EOF' > /home/user/polyglot/algo.c
#include <stdlib.h>
double* moving_average(double* data, int len, int window) {
    if (len < window || window <= 0) return NULL;
    double* res = malloc(sizeof(double) * (len - window + 1));
    for(int i=0; i<=len-window; i++) {
        double sum = 0;
        for(int j=0; j<window; j++) sum += data[i+j];
        res[i] = sum / window;
    }
    return res;
}
EOF

cat << 'EOF' > /home/user/polyglot/wrapper.py
import ctypes
import sys
import time

# Flawed rate limiting logic
last_req = time.time()
def validate_and_limit():
    global last_req
    now = time.time()
    if now - last_req < 1.0:
        print("Rate limited!")
        sys.exit(1)
    last_req = now

validate_and_limit()

lib = ctypes.CDLL('./libalgo.so')

# TODO: Fix FFI signatures
# lib.moving_average.argtypes = ...
# lib.moving_average.restype = ...

data = (ctypes.c_double * 5)(1.0, 2.0, 3.0, 4.0, 5.0)
res_ptr = lib.moving_average(data, 5, 3)

res = ctypes.cast(res_ptr, ctypes.POINTER(ctypes.c_double))
print(f"{res[0]:.1f},{res[1]:.1f},{res[2]:.1f}")
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
