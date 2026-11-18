#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc
    pip3 install pytest Pillow

    mkdir -p /app
    mkdir -p /home/user/parser

    # 1. Generate image
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "SYSTEM DASHBOARD\nSTATUS: FAILING\nCRITICAL_OFFSET: 83912", fill=(0, 0, 0))
img.save('/app/ticket_screenshot.png')
EOF
    python3 /tmp/gen_image.py
    rm /tmp/gen_image.py

    # 2. Compile legacy_parser
    cat << 'EOF' > /tmp/legacy_parser.c
#include <stdio.h>

int main() {
    int c;
    int depth = 1;
    long offset = 83912;
    while ((c = fgetc(stdin)) != EOF) {
        if (c == '(') {
            depth++;
            printf("%ld\n", (c + offset) * depth);
        } else if (c == ')') {
            printf("%ld\n", (c + offset) * depth);
            if (depth > 1) depth--;
        } else {
            printf("%ld\n", (c + offset) * depth);
        }
    }
    return 0;
}
EOF
    gcc -O2 /tmp/legacy_parser.c -o /app/legacy_parser
    strip /app/legacy_parser
    rm /tmp/legacy_parser.c

    # 3. Create fast_parser.py
    cat << 'EOF' > /home/user/parser/fast_parser.py
import sys

CONFIG_OFFSET = 0

def parse(data, index, depth):
    if index >= len(data):
        return

    char = data[index]

    if char == '(':
        depth += 1
        print((ord(char) + CONFIG_OFFSET) * depth)
        # Bug: missing index increment
        parse(data, index, depth)
    elif char == ')':
        print((ord(char) + CONFIG_OFFSET) * depth)
        if depth > 1:
            depth -= 1
        parse(data, index + 1, depth)
    else:
        print((ord(char) + CONFIG_OFFSET) * depth)
        parse(data, index + 1, depth)

if __name__ == "__main__":
    sys.setrecursionlimit(2000)
    data = sys.stdin.read()
    parse(data, 0, 1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
