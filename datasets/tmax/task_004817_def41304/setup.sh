#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nmap \
        openssh-server \
        curl \
        gcc \
        binutils

    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user

    # Create the legacy_audit_sender C source
    cat << 'EOF' > /app/sender.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <audit_message>\n", argv[0]);
        return 1;
    }
    char *input = argv[1];
    int len = strlen(input);

    FILE *fp = fopen("/tmp/.payload.bin", "wb");
    if (!fp) return 1;

    for (int i = 0; i < len; i++) {
        fputc(input[i] ^ 0x5A, fp);
    }
    fclose(fp);

    system("base64 -w 0 /tmp/.payload.bin > /tmp/.payload.b64");
    system("curl -s -X POST --data-binary @/tmp/.payload.b64 http://127.0.0.1:8080/ingest > /dev/null");

    remove("/tmp/.payload.bin");
    remove("/tmp/.payload.b64");

    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 -o /app/legacy_audit_sender /app/sender.c
    strip /app/legacy_audit_sender
    rm /app/sender.c

    # Create the user
    useradd -m -s /bin/bash user || true

    # Fix permissions
    chmod -R 777 /home/user
    chmod 755 /app/legacy_audit_sender
