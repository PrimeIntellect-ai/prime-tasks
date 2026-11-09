#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make file
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/parser.c
#include <stdio.h>
#include <string.h>

void parse_token(const char* input, char* output) {
    int state = 0; // 0 = KEY, 1 = VALUE
    char key[16];
    char value[16];
    int k_idx = 0;
    int v_idx = 0;

    strcpy(output, "{");

    for (int i = 0; input[i] != '\0'; i++) {
        char c = input[i];
        if (state == 0) {
            if (c == ':') {
                key[k_idx] = '\0';
                state = 1;
            } else {
                key[k_idx++] = c; // BUG: No bounds check
            }
        } else if (state == 1) {
            if (c == ';') {
                value[v_idx] = '\0';

                // Append to output JSON
                if (strlen(output) > 1) strcat(output, ", ");
                strcat(output, "\"");
                strcat(output, key);
                strcat(output, "\": \"");
                strcat(output, value);
                strcat(output, "\"");

                // Reset for next pair
                k_idx = 0;
                v_idx = 0;
                state = 0;
            } else {
                value[v_idx++] = c; // BUG: No bounds check
            }
        }
    }
    strcat(output, "}");
}
EOF

    cat << 'EOF' > /home/user/workspace/Makefile
all:
	gcc -o libparser.so parser.c
EOF

    cat << 'EOF' > /home/user/workspace/test.py
import ctypes
import json
import os

def main():
    lib = ctypes.CDLL('/home/user/workspace/libparser.so')
    lib.parse_token.argtypes = [ctypes.c_char_p, ctypes.c_char_p]

    payload = b"admin_status_override:true;normal_k:normal_v;"
    out_buf = ctypes.create_string_buffer(256)

    lib.parse_token(payload, out_buf)

    # Parse to ensure it's valid JSON
    result = json.loads(out_buf.value.decode('utf-8'))

    with open('/home/user/workspace/result.json', 'w') as f:
        json.dump(result, f)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
