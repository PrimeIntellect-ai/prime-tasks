#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    mkdir -p /home/user/legacy_app

    cat << 'EOF' > /home/user/legacy_app/processor.c
#include <string.h>

void process_string(const char* input, char* output) {
    int len = strlen(input);
    for(int i = 0; i < len; i++) {
        // Simple ROT13 implementation for testing
        if (input[i] >= 'a' && input[i] <= 'z') {
            output[i] = ((input[i] - 'a') + 13) % 26 + 'a';
        } else if (input[i] >= 'A' && input[i] <= 'Z') {
            output[i] = ((input[i] - 'A') + 13) % 26 + 'A';
        } else {
            output[i] = input[i];
        }
    }
    output[len] = '\0';
}
EOF

    cat << 'EOF' > /home/user/legacy_app/Makefile
libprocessor.so: processor.c
	gcc -o libprocessor.so processor.c
EOF

    cat << 'EOF' > /home/user/legacy_app/wrapper.py
import ctypes
import os

lib_path = os.path.join(os.path.dirname(__file__), 'libprocessor.so')
lib = ctypes.CDLL(lib_path)

def transform(text):
    out = ctypes.create_string_buffer(len(text) + 1)
    lib.process_string(text, out)
    print "Processed string: " + out.value
    return out.value
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/legacy_app
    chmod -R 777 /home/user
