#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make curl
pip3 install pytest flask flask-limiter

mkdir -p /home/user/math-api
cd /home/user/math-api

cat << 'EOF' > math_core.c
#include <stdint.h>

uint64_t fast_mod(uint64_t a, uint64_t m) {
    uint64_t res;
    // Bug: "=a" binds to rax (quotient of divq), should be "=&d" or "=d" for rdx (remainder)
    __asm__ __volatile__ (
        "xor %%rdx, %%rdx\n\t"
        "divq %2\n\t"
        : "=a" (res)
        : "a" (a), "r" (m)
        : "cc"
    );
    return res;
}
EOF

cat << 'EOF' > Makefile
all:
	gcc -shared -o libmathcore.so -fPIC math_core.c
EOF

cat << 'EOF' > app.py
from flask import Flask, request, jsonify
import ctypes

app = Flask(__name__)
math_core = ctypes.CDLL('./libmathcore.so')
math_core.fast_mod.argtypes = [ctypes.c_uint64, ctypes.c_uint64]
math_core.fast_mod.restype = ctypes.c_uint64

@app.route('/mod', methods=['GET'])
def mod():
    a = int(request.args.get('a'))
    m = int(request.args.get('m'))
    res = math_core.fast_mod(a, m)
    return jsonify({"result": res})

if __name__ == '__main__':
    app.run(port=5000)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
