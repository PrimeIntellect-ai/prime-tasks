#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest hypothesis

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/string_processor.c
#include <string.h>

void process_string(const char* input, char* output) {
    int len = strlen(input);
    for (int i = 0; i < len; i++) {
        char c = input[len - 1 - i];
        if (c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u') {
            output[i] = c - 32; // Uppercase lowercase vowels
        } else {
            output[i] = c;
        }
    }
    output[len] = '\0';
}
EOF

    cat << 'EOF' > /home/user/project/pipeline_util.py
import ctypes
import os

lib_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "libstring_processor.so"))
if os.path.exists(lib_path):
    lib = ctypes.CDLL(lib_path)
    lib.process_string.argtypes = [ctypes.c_char_p, ctypes.c_char_p]

def process_string_c(input_str: str) -> str:
    b_in = input_str.encode('ascii', errors='ignore')
    b_out = ctypes.create_string_buffer(len(b_in) + 1)
    lib.process_string(b_in, b_out)
    return b_out.value.decode('ascii')
EOF

    cp /home/user/project/pipeline_util.py /home/user/project/pipeline_util.py.orig

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
