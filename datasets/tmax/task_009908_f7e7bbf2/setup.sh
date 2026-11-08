#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/verify.py
import ctypes
import os

def run_test():
    lib_path = '/home/user/libtransform.so'
    if not os.path.exists(lib_path):
        print("Shared library not found")
        return

    lib = ctypes.CDLL(lib_path)
    lib.transform_string.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    lib.transform_string.restype = ctypes.c_int

    out_buf = ctypes.create_string_buffer(256)
    length = lib.transform_string(b"engineer", out_buf)

    with open('/home/user/result.log', 'w') as f:
        f.write(f"{length},{out_buf.value.decode('utf-8')}")

if __name__ == '__main__':
    run_test()
EOF

chmod -R 777 /home/user
