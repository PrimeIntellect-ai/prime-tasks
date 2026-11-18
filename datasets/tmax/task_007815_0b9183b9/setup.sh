#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy
    cd /home/user/legacy

    cat << 'EOF' > tokenhash.c
#include <stdint.h>

uint32_t compute_hash(const char* data, int length) {
    uint32_t hash = 5381;
    for (int i = 0; i < length; i++) {
        hash = ((hash << 5) + hash) + data[i]; /* hash * 33 + c */
    }
    return hash;
}
EOF

    gcc -shared -o libtokenhash.so -fPIC tokenhash.c

    cat << 'EOF' > validator.py
import ctypes
import os

# Load shared library
lib_path = os.path.join(os.path.dirname(__file__), 'libtokenhash.so')
lib = ctypes.CDLL(lib_path)

def get_checksum(data):
    # Missing argtypes/restype definition, common in lazy Py2 code
    return lib.compute_hash(data, len(data))

class TokenValidator:
    def __init__(self):
        pass

    def parse_token(self, token):
        # State machine to parse SEC<data>#<checksum_hex>
        state = 'START'
        data = ""
        checksum = ""

        i = 0
        while i < len(token):
            c = token[i]
            if state == 'START':
                if token[i:i+3] == 'SEC':
                    state = 'READ_DATA'
                    i += 2
                else:
                    raise ValueError("Invalid prefix")
            elif state == 'READ_DATA':
                if c == '#':
                    state = 'READ_CHECKSUM'
                else:
                    data += c
            elif state == 'READ_CHECKSUM':
                checksum += c
            i += 1

        if state != 'READ_CHECKSUM' or not checksum:
            raise ValueError("Incomplete token")

        return data, int(checksum, 16)

    def validate(self, token):
        data, expected_checksum = self.parse_token(token)
        actual_checksum = get_checksum(data)
        # In Python 2, returned value might be a signed integer depending on ctypes defaults
        # To strictly compare, mask to 32-bit
        actual_checksum = actual_checksum & 0xFFFFFFFF
        return actual_checksum == expected_checksum
EOF

    chmod -R 777 /home/user
