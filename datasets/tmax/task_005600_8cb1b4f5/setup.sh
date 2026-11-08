#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc valgrind
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/stringops.c
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

uint16_t* encode_string(const char* input, int* out_len) {
    if (!input) return NULL;
    int len = strlen(input);
    uint16_t* output = (uint16_t*)malloc((len + 1) * sizeof(uint16_t));
    for (int i = 0; i < len; i++) {
        output[i] = (uint16_t)input[i];
    }
    output[len] = 0;
    if (out_len) *out_len = len;
    return output;
}

void free_encoded(uint16_t* ptr) {
    if (ptr) free(ptr);
}
EOF

gcc -shared -o /home/user/libstringops.so -fPIC /home/user/stringops.c

cat << 'EOF' > /home/user/input.txt
Hello
EOF

cat << 'EOF' > /home/user/process.py
import ctypes
import sys

lib = ctypes.CDLL('/home/user/libstringops.so')

def process_file(input_file, output_file):
    with open(input_file, 'rb') as f:
        data = f.read().strip()

    out_len = ctypes.c_int(0)
    result_ptr = lib.encode_string(data, ctypes.byref(out_len))

    # Missing logic to extract data, write to output, and free memory

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(1)
    process_file(sys.argv[1], sys.argv[2])
EOF

chmod -R 777 /home/user
