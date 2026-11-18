#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest flask fastapi uvicorn requests

mkdir -p /app

cat << 'EOF' > /tmp/telemetry_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char hex[1024];
    if (scanf("%1023s", hex) != 1) return 1;
    size_t len = strlen(hex);
    for (size_t i = 0; i < len; i += 2) {
        unsigned int byte;
        sscanf(&hex[i], "%2x", &byte);
        putchar(byte);
    }
    return 0;
}
EOF

gcc -O2 -s /tmp/telemetry_decoder.c -o /app/telemetry_decoder
chmod +x /app/telemetry_decoder
rm /tmp/telemetry_decoder.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
