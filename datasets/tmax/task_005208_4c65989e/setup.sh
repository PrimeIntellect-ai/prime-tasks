#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils strace ltrace gdb xxd
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /tmp/telemetry_sender.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *input = argv[1];
    int len = strlen(input);
    for (int i = 0; i < len; i++) {
        unsigned char c = (unsigned char)input[i];
        unsigned char obf = (c ^ 0x5A) + (i % 256);
        printf("%02x", obf);
    }
    printf("\n");
    return 0;
}
EOF

gcc -O2 -s /tmp/telemetry_sender.c -o /app/telemetry_sender
chmod +x /app/telemetry_sender
rm /tmp/telemetry_sender.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
