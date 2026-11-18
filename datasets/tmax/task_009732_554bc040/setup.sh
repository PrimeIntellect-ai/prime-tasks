#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest packaging

    mkdir -p /home/user
    cat << 'EOF' > /home/user/math_utility.py
import ctypes
from packaging import version
import math

def run_calculation(lib_path, value):
    try:
        lib = ctypes.CDLL(lib_path)
    except OSError:
        return None

    lib.get_version.restype = ctypes.c_char_p
    v_str = lib.get_version().decode('utf-8')

    if version.parse(v_str) >= version.parse("2.0.0"):
        lib.advanced_calc.restype = ctypes.c_double
        lib.advanced_calc.argtypes = [ctypes.c_double]
        return lib.advanced_calc(float(value))
    else:
        return math.sqrt(float(value))
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
