#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb ltrace strace binutils coreutils
    pip3 install pytest

    mkdir -p /app /corpus/evil /corpus/clean

    cat << 'EOF' > /tmp/token_checker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char cmd[2048];
    // Simple base64 decode using system
    snprintf(cmd, sizeof(cmd), "echo '%s' | base64 -d > /tmp/decoded.txt 2>/dev/null", argv[1]);
    system(cmd);

    FILE *f = fopen("/tmp/decoded.txt", "r");
    if (!f) return 1;
    char buf[1024] = {0};
    fread(buf, 1, sizeof(buf)-1, f);
    fclose(f);

    // Vulnerable printf
    printf(buf);
    printf("\n");
    return 0;
}
EOF

    gcc -O2 -s -o /app/token_checker /tmp/token_checker.c
    rm /tmp/token_checker.c

    cat << 'EOF' > /tmp/generate_corpus.py
import base64
import os

evil_payloads = [f"admin{i}%n%s%x" for i in range(50)]
clean_payloads = [f"admin_user_{i}:12345" for i in range(50)]

for i, p in enumerate(evil_payloads):
    with open(f'/corpus/evil/{i}.txt', 'w') as f:
        f.write(base64.b64encode(p.encode()).decode())

for i, p in enumerate(clean_payloads):
    with open(f'/corpus/clean/{i}.txt', 'w') as f:
        f.write(base64.b64encode(p.encode()).decode())
EOF

    python3 /tmp/generate_corpus.py
    rm /tmp/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
