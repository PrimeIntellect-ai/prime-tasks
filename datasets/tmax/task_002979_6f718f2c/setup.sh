#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/fast-token-parser

    cat << 'EOF' > /home/user/fast-token-parser/parser.c
#include <stdint.h>
#include <string.h>

// Returns 0 on success, -1 on error
int parse_token(const unsigned char* input, int input_len, unsigned char* out_data, int* out_type) {
    if (input_len < 3) return -1;

    *out_type = input[0];
    int data_len = (input[1] << 8) | input[2];

    if (data_len + 3 > input_len) return -1; // Wait for full payload

    unsigned char internal_buffer[64];
    // BUG: Missing check for data_len > 64
    memcpy(internal_buffer, input + 3, data_len);

    memcpy(out_data, internal_buffer, data_len);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/fast-token-parser/config.py
import os
def init():
    os.environ['PARSER_INITIALIZED'] = '1'
init()
EOF

    cat << 'EOF' > /home/user/fast-token-parser/ffi_wrapper.py
import ctypes
import os

if not os.environ.get('PARSER_INITIALIZED'):
    # Simulating the bad initialization state if imported too early
    raise RuntimeError("config must be imported before ffi_wrapper!")

lib = ctypes.CDLL('/home/user/fast-token-parser/libparser.so')

def parse(token_bytes):
    out_data = (ctypes.c_ubyte * 256)()
    out_type = ctypes.c_int()

    res = lib.parse_token(token_bytes, len(token_bytes), out_data, ctypes.byref(out_type))
    if res == -1:
        return {"error": "Invalid token"}

    # Calculate length from token (for simplicity in wrapper)
    length = (token_bytes[1] << 8) | token_bytes[2]
    data = bytes(out_data[:length])
    return {"type": out_type.value, "data": data.decode('utf-8', errors='ignore')}
EOF

    cat << 'EOF' > /home/user/fast-token-parser/test_suite.py
import ffi_wrapper # BUG: This is imported before config!
import config
import json

payloads = [
    b'\x01\x00\x05hello',
    b'\x02\x00\x45' + b'A' * 69, # This triggers the overflow in C
    b'\x03\x00\x04test'
]

def run_tests():
    results = []
    for p in payloads:
        results.append(ffi_wrapper.parse(p))

    with open('/home/user/parsed_tokens.json', 'w') as f:
        json.dump(results, f)

if __name__ == '__main__':
    run_tests()
EOF

    cd /home/user/fast-token-parser
    gcc -shared -o libparser.so -fPIC parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
