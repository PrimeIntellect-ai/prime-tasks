#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb strace ltrace
pip3 install --default-timeout=100 pytest

mkdir -p /app
cat << 'EOF' > /tmp/decoder.c
#include <stdio.h>

int main() {
    int c;
    while ((c = getchar()) != EOF) {
        if (c >= 'a' && c <= 'z') {
            c = ((c - 'a' + 5) % 26) + 'a';
        } else if (c >= 'A' && c <= 'Z') {
            c = ((c - 'A' + 13) % 26) + 'A';
        } else if (c >= '0' && c <= '9') {
            c = ((c - '0' + 7) % 10) + '0';
        }
        putchar(c);
    }
    return 0;
}
EOF

gcc -O2 -o /app/path_decoder /tmp/decoder.c
strip /app/path_decoder
rm /tmp/decoder.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
