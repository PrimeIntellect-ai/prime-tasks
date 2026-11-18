#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tesseract-ocr imagemagick
    pip3 install pytest

    mkdir -p /home/user/auth_lib
    mkdir -p /app

    cat << 'EOF' > /home/user/auth_lib/auth.c
#include <stdio.h>
#include <string.h>

#ifndef TOKEN_SALT
#define TOKEN_SALT 0
#endif

int validate_token(const char* input) {
    int sum = TOKEN_SALT;
    for(int i=0; i<strlen(input); i++) {
        sum += input[i];
        sum ^= (input[i] << 2);
    }
    return sum;
}
EOF

    cat << 'EOF' > /home/user/auth_lib/Makefile
all:
	gcc -shared -fPIC -o libauth.so auth.c
EOF

    # Generate the image with instructions
    convert -background white -fill black -pointsize 24 label:"CRITICAL: The build must include the flag -DTOKEN_SALT=9928" /app/instructions.png

    cat << 'EOF' > /app/oracle
#!/usr/bin/env python3
import sys

def validate_token(input_str):
    sum_val = 9928
    for char in input_str:
        sum_val += ord(char)
        # simulate 32-bit signed integer overflow in python
        sum_val = (sum_val & 0xFFFFFFFF)
        if sum_val & 0x80000000:
            sum_val = sum_val - 0x100000000

        sum_val ^= (ord(char) << 2)

        sum_val = (sum_val & 0xFFFFFFFF)
        if sum_val & 0x80000000:
            sum_val = sum_val - 0x100000000
    return sum_val

for line in sys.stdin:
    line = line.strip('\n')
    print(validate_token(line))
EOF

    chmod +x /app/oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
