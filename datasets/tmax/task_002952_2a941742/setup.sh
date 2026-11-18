#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tesseract-ocr
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user/project

    # Generate kernel_spec.png using Python
    cat << 'EOF' > /tmp/gen_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 100), color = (255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10,40), "Weights: 13, 17, 31", fill=(0,0,0))
img.save('/app/kernel_spec.png')
EOF
    python3 /tmp/gen_img.py

    # Create oracle C code
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

int is_numeric(const char *str) {
    if (!*str) return 0;
    if (*str == '-') str++;
    if (!*str) return 0;
    while (*str) {
        if (!isdigit((unsigned char)*str)) return 0;
        str++;
    }
    return 1;
}

int main() {
    char token[256];
    long long w[3] = {0};
    int count = 0;
    while (scanf("%255s", token) == 1) {
        if (is_numeric(token)) {
            w[0] = w[1];
            w[1] = w[2];
            w[2] = atoll(token);
            count++;
            if (count >= 3) {
                printf("%lld\n", w[0]*13 + w[1]*17 + w[2]*31);
            }
        }
    }
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/oracle_bin
    chmod +x /app/oracle_bin

    # Create buggy C code
    cat << 'EOF' > /home/user/project/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TOKENS 100000

int main() {
    char token[256];
    long long *arr = malloc(MAX_TOKENS * sizeof(long long)); // uninitialized memory
    int count = 0;

    // Blindly reading tokens without validation
    while (scanf("%255s", token) == 1) {
        arr[count++] = atoll(token);
    }

    // Off-by-one loop condition
    for (int i = 0; i < count - 1; i++) {
        if (i + 2 < count) {
            // Incorrect weights
            printf("%lld\n", arr[i]*1 + arr[i+1]*1 + arr[i+2]*1);
        }
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
