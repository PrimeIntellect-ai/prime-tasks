#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /app/bin
    cat << 'EOF' > /tmp/zdecoder.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    unsigned char buf[2];
    while (fread(buf, 1, 2, f) == 2) {
        int count = buf[0];
        unsigned char payload = buf[1] ^ 0xAA;
        for (int i = 0; i < count; i++) {
            putchar(payload);
        }
    }
    fclose(f);
    return 0;
}
EOF
    gcc /tmp/zdecoder.c -o /app/bin/zdecoder
    strip /app/bin/zdecoder
    chmod +x /app/bin/zdecoder

    mkdir -p /home/user/logs

    cat << 'EOF' > /tmp/gen_logs.py
import os

def write_zlog(filename, text):
    utf16 = text.encode('utf-16le')
    encoded = bytearray()
    # Simple RLE encoding: 1 byte count, 1 byte XOR payload
    for b in utf16:
        encoded.append(1)
        encoded.append(b ^ 0xAA)
    with open(filename, 'wb') as f:
        f.write(encoded)

write_zlog('/home/user/logs/syslog.zlog', 'System log initialized.\nNo errors found.\n')
write_zlog('/home/user/logs/auth.zlog', 'User admin authenticated successfully.\n')
EOF
    python3 /tmp/gen_logs.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
