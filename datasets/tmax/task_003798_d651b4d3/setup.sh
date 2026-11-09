#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest Flask hypothesis

    mkdir -p /home/user/math_service
    cd /home/user/math_service

    cat << 'EOF' > fast_inverse_sqrt.c
#include <stdint.h>

float fast_inv_sqrt(float number) {
    int32_t i;
    float x2, y;
    const float threehalfs = 1.5F;

    x2 = number * 0.5F;
    y  = number;
    i  = * ( int32_t * ) &y;                       
    i  = 0x5f3759df - ( i >> 1 );               
    y  = * ( float * ) &i;
    y  = y * ( threehalfs - ( x2 * y * y ) );   
    return y;
}
EOF

    cat << 'EOF' > math_ops.py
import ctypes
import os

lib_path = os.path.abspath(os.path.join(os.path.dirname(__file__), 'libfastmath.so'))
if os.path.exists(lib_path):
    lib = ctypes.CDLL(lib_path)
    # BUG: Wrong ctypes! C uses float (32-bit), but here we use double (64-bit)
    lib.fast_inv_sqrt.argtypes = [ctypes.c_double]
    lib.fast_inv_sqrt.restype = ctypes.c_double
else:
    lib = None

def get_inv_sqrt(n):
    if n <= 0:
        raise ValueError("Must be positive")
    if lib is None:
        raise RuntimeError("Library not compiled")
    return lib.fast_inv_sqrt(n)
EOF

    cat << 'EOF' > api.py
from flask import Flask, jsonify
from math_ops import get_inv_sqrt

app = Flask(__name__)

# BUG: route parameter is a string, not a float
@app.route('/invsqrt/<value>')
def invsqrt(value):
    try:
        # Fails here or in math_ops because value is not converted properly
        res = get_inv_sqrt(value)
        return jsonify({"result": res})
    except Exception as e:
        return jsonify({"error": str(e)}), 400

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > test_api.py
import pytest
from math_ops import get_inv_sqrt
from api import app

def test_basic():
    assert abs(get_inv_sqrt(4.0) - 0.5) < 0.1

# TODO: Add hypothesis test
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
