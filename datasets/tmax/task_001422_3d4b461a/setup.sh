#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/patcher.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

const char b64chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

int b64decode(const char *in, unsigned char *out) {
    int len = strlen(in);
    int out_len = 0;
    int val = 0, valb = -8;
    for (int i = 0; i < len; i++) {
        unsigned char c = in[i];
        if (c == '=') break;
        const char *p = strchr(b64chars, c);
        if (!p) continue;
        val = (val << 6) + (p - b64chars);
        valb += 6;
        if (valb >= 0) {
            out[out_len++] = (val >> valb) & 0xFF;
            valb -= 8;
        }
    }
    return out_len;
}

void dummy_padding() {
    int x = 0;
    for(int i=0; i<10000; i++) x += i;
    if(x == -1) printf("dummy");
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    unsigned char buf[1024];
    int len = b64decode(argv[1], buf);
    if (len < 4) return 1;
    if (buf[0] != 0xDE || buf[1] != 0xAD || buf[2] != 0xBE || buf[3] != 0xEF) return 1;

    int32_t A = 0;
    for (int i = 4; i <= len - 3; i += 3) {
        unsigned char op = buf[i];
        int16_t operand = (buf[i+1] | (buf[i+2] << 8));
        if (op == 1) A += operand;
        else if (op == 2) A -= operand;
        else if (op == 3) A *= operand;
        else if (op == 4) {
            if (operand == 0) {
                int *p = NULL; *p = 0;
            }
            A /= operand;
        }
        if (A < 0) {
            int *p = NULL; *p = 0;
        }
    }
    dummy_padding();
    return 0;
}
EOF

    gcc -O0 -o /app/legacy_patcher /tmp/patcher.c
    strip /app/legacy_patcher || true
    upx /app/legacy_patcher || true

    mkdir -p /var/opt/verifier/corpora/clean
    mkdir -p /var/opt/verifier/corpora/evil

    cat << 'EOF' > /tmp/gen_corpora.py
import base64
import struct
import os

def make_patch(ops):
    buf = b'\xde\xad\xbe\xef'
    for op, operand in ops:
        buf += struct.pack('<Bh', op, operand)
    return base64.b64encode(buf).decode('utf-8')

clean_dir = '/var/opt/verifier/corpora/clean'
evil_dir = '/var/opt/verifier/corpora/evil'

with open(f'{clean_dir}/c1.txt', 'w') as f: f.write(make_patch([(1, 5)]))
with open(f'{clean_dir}/c2.txt', 'w') as f: f.write(make_patch([(1, 10), (2, 5)]))
with open(f'{evil_dir}/e1.txt', 'w') as f: f.write(make_patch([(1, 5), (4, 0)]))
with open(f'{evil_dir}/e2.txt', 'w') as f: f.write(make_patch([(2, 5)]))
EOF
    python3 /tmp/gen_corpora.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
