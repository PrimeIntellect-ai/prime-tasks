#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb valgrind
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

int main() {
    char hex[4096];
    if(scanf("%4095s", hex) != 1) return 1;
    unsigned char buf[2048];
    size_t hex_len = strlen(hex);
    int len = hex_len / 2;
    for(int i=0; i<len; i++) {
        sscanf(hex + 2*i, "%2hhx", &buf[i]);
    }
    if(len < 4 || memcmp(buf, "TOKN", 4) != 0) return 1;

    int pos = 4;
    while(pos < len) {
        if(pos + 3 > len) kill(getpid(), 11);
        unsigned char type = buf[pos];
        unsigned short vlen = (buf[pos+1] << 8) | buf[pos+2];
        if(pos + 3 + vlen > len) kill(getpid(), 11);
        if(type == 2 && vlen > 32) kill(getpid(), 11);
        pos += 3 + vlen;
    }
    printf("{}\n");
    return 0;
}
EOF

    gcc -O0 -o /app/legacy_decoder /tmp/decoder.c
    strip /app/legacy_decoder
    rm /tmp/decoder.c

    cat << 'EOF' > /tmp/gen_corpus.py
import os
import random

for i in range(50):
    # Clean: Type 1, len 4
    val = "544f4b4e010004" + os.urandom(4).hex()
    with open(f'/app/corpus/clean/clean_{i}.txt', 'w') as f:
        f.write(val)

    # Evil
    if i % 2 == 0:
        # Type 2, len 33 (Buffer Overflow)
        val = "544f4b4e020021" + os.urandom(33).hex()
    else:
        # OOB read (Length exceeds remaining)
        val = "544f4b4e010005" + os.urandom(4).hex()
    with open(f'/app/corpus/evil/evil_{i}.txt', 'w') as f:
        f.write(val)
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
