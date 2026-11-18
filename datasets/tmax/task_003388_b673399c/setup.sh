#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/legacy
mkdir -p /home/user/modern

# 1. Create the C library
cat << 'EOF' > /home/user/legacy/checksum.c
#include <stdint.h>
uint32_t compute_checksum(const char* str) {
    uint32_t hash = 5381;
    int c;
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    }
    return hash;
}
EOF
gcc -shared -o /home/user/legacy/libchecksum.so -fPIC /home/user/legacy/checksum.c

# 2. Create the legacy Python 2 file
cat << 'EOF' > /home/user/legacy/math_eval.py
import ctypes

lib = ctypes.CDLL('/home/user/legacy/libchecksum.so')
lib.compute_checksum.argtypes = [ctypes.c_char_p]
lib.compute_checksum.restype = ctypes.c_uint32

def evaluate_prefix(tokens):
    if not tokens:
        return 0
    token = tokens.pop(0)
    if token == '+':
        return evaluate_prefix(tokens) + evaluate_prefix(tokens)
    elif token == '-':
        return evaluate_prefix(tokens) - evaluate_prefix(tokens)
    elif token == '*':
        return evaluate_prefix(tokens) * evaluate_prefix(tokens)
    elif token == '/':
        return evaluate_prefix(tokens) / evaluate_prefix(tokens)
    else:
        return int(token)

def evaluate_and_hash(expr):
    tokens = expr.split()
    # In python 2, string is bytes, so this passes directly
    chksum = lib.compute_checksum(expr)
    res = evaluate_prefix(tokens)
    return res, chksum

if __name__ == "__main__":
    for i in xrange(1):
        print "Legacy System Ready"
EOF

# 3. Create input file
cat << 'EOF' > /home/user/inputs.txt
+ 3 4
- 10 * 2 3
/ 10 3
+ / 20 6 * 2 5
EOF

chmod -R 777 /home/user
