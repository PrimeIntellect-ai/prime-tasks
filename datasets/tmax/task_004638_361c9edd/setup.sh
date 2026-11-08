#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/fastchk.c
#include <stdint.h>
int calculate_checksum(const char* input, int length, uint32_t* output) {
    if (!input || !output) return -1;
    uint32_t crc = 0xFFFFFFFF;
    for (int i = 0; i < length; i++) {
        crc ^= (uint8_t)input[i];
        for (int j = 0; j < 8; j++) {
            crc = (crc >> 1) ^ (0xEDB88320 & (-(crc & 1)));
        }
    }
    *output = ~crc;
    return 0;
}
EOF

    gcc -shared -o /home/user/libfastchk.so -fPIC /home/user/fastchk.c

    cat << 'EOF' > /home/user/checksum_wrapper.py
import ctypes
import os

lib = ctypes.CDLL('/home/user/libfastchk.so')

# BUG: Incorrect argtypes and passing by value instead of reference
lib.calculate_checksum.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
lib.calculate_checksum.restype = ctypes.c_int

def get_checksum(data: bytes) -> int:
    out = ctypes.c_int(0)
    res = lib.calculate_checksum(data, len(data), out)
    if res != 0:
        raise Exception("Checksum failed")
    return out.value
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
