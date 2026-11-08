#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc valgrind
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/crc_algo.c
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

uint32_t custom_crc(const uint8_t *data, size_t len) {
    // Copy to temporary buffer
    uint8_t *buffer = (uint8_t *)malloc(len);
    for (size_t i = 0; i < len; i++) {
        buffer[i] = data[i];
    }

    uint32_t crc = 0xFFFFFFFF;

    // BUG: Off-by-one error causing out-of-bounds read on heap memory
    for (size_t i = 0; i <= len; i++) {
        crc ^= buffer[i];
        for (int j = 0; j < 8; j++) {
            if (crc & 1) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }

    free(buffer);
    return crc ^ 0xFFFFFFFF;
}
EOF

    cat << 'EOF' > /home/user/wrapper.c
#include <stddef.h>
#include <stdint.h>

extern uint32_t custom_crc(const uint8_t *data, size_t len);

uint32_t compute_checksum(const char *text, size_t len) {
    return custom_crc((const uint8_t *)text, len);
}
EOF

    cat << 'EOF' > /home/user/test.py
import ctypes
import sys

try:
    lib = ctypes.CDLL('/home/user/libwrapper.so')
except OSError as e:
    print(f"Failed to load library: {e}")
    sys.exit(1)

lib.compute_checksum.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
lib.compute_checksum.restype = ctypes.c_uint32

def run_checksum():
    text = b"ALGORITHMIC_DEBUGGING"
    return lib.compute_checksum(text, len(text))

if __name__ == "__main__":
    print(run_checksum())
EOF

    gcc -shared -fPIC /home/user/wrapper.c -o /home/user/libwrapper.so
    chmod +x /home/user/test.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
