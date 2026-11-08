#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    # Create C script for decode_payload
    cat << 'EOF' > /app/decode_payload.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <PIN> <obfuscated_string>\n", argv[0]);
        return 1;
    }
    if (strcmp(argv[1], "7391") != 0) {
        printf("Access Denied\n");
        return 1;
    }
    char cmd[8192];
    snprintf(cmd, sizeof(cmd), "echo '%s' | base64 -d 2>/dev/null", argv[2]);
    FILE *fp = popen(cmd, "r");
    if (!fp) return 1;
    int c;
    while ((c = fgetc(fp)) != EOF) {
        putchar(c ^ 0x42);
    }
    pclose(fp);
    return 0;
}
EOF

    # Compile and strip
    gcc -O2 /app/decode_payload.c -o /app/decode_payload
    strip /app/decode_payload
    rm /app/decode_payload.c

    # Generate corpora using Python
    cat << 'EOF' > /app/generate_corpus.py
import base64
import os

def encode_payload(payload):
    xored = bytes([c ^ 0x42 for c in payload.encode()])
    return base64.b64encode(xored).decode()

evil = [
    "../../../etc/passwd", 
    "<script>alert(1)</script>", 
    "images/..%2f..%2fconfig.php", 
    "\"><img src=x onerror=prompt()>"
]
clean = [
    "images/avatar.png", 
    "documents/report_2023.pdf", 
    "index.html"
]

for i, p in enumerate(evil):
    with open(f"/app/corpus/evil/{i}.txt", "w") as f:
        f.write(encode_payload(p))

for i, p in enumerate(clean):
    with open(f"/app/corpus/clean/{i}.txt", "w") as f:
        f.write(encode_payload(p))
EOF

    python3 /app/generate_corpus.py
    rm /app/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
