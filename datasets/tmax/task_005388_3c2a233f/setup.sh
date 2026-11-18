#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb strace
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    # 1. Create the vulnerable C library
    cat << 'EOF' > fastparse.c
#include <string.h>

int parse_record(const char* data, int len) {
    if (len < 4) return 1;
    for(int i = 0; i <= len - 4; i++) {
        // The deadly 4-byte sequence: DE AD BE EF
        if(data[i] == '\xDE' && data[i+1] == '\xAD' && data[i+2] == '\xBE' && data[i+3] == '\xEF') {
            char *ptr = 0; // NULL pointer
            *ptr = 1;      // Segmentation fault
        }
    }
    return 1;
}
EOF

    gcc -shared -o libfastparse.so -fPIC fastparse.c

    # 2. Create the dummy telemetry data (data.bin)
    python3 -c "
import random
random.seed(42)
with open('data.bin', 'wb') as f:
    for i in range(1000):
        if i == 732:
            chunk = b'A' * 30 + b'\xDE\xAD\xBE\xEF' + b'B' * 30
        else:
            chunk = bytes([random.randint(0, 255) for _ in range(64)])
            # Ensure no accidental DEADBEEF
            chunk = chunk.replace(b'\xDE\xAD\xBE\xEF', b'\x00\x00\x00\x00')
        f.write(chunk)
"

    # 3. Create the original (crashing) report_generator.py
    cat << 'EOF' > report_generator.py
import ctypes
import os

lib = ctypes.CDLL('./libfastparse.so')
lib.parse_record.argtypes = [ctypes.c_char_p, ctypes.c_int]

def main():
    if os.path.exists("processed.log"):
        os.remove("processed.log")

    chunk_size = 64
    processed = 0
    with open('data.bin', 'rb') as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            # Calling the C extension
            lib.parse_record(chunk, len(chunk))
            processed += 1

    with open('processed.log', 'w') as f:
        f.write(f"Processed {processed} chunks\n")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
