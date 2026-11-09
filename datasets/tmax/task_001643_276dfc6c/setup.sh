#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3 || strcmp(argv[1], "--analyze") != 0) {
        return 1;
    }
    FILE *f = fopen(argv[2], "r");
    if (!f) return 1;

    char buffer[256];
    size_t n = fread(buffer, 1, 255, f);
    buffer[n] = '\0';
    fclose(f);

    if (strncmp(buffer, "BENIGN_PAYLOAD_1", 16) == 0) {
        printf("=== ARCHIVE ENTRY ===\nFilepath: bin/startup.sh\nSize: 1024\nType: file\n=====================\n=== ARCHIVE ENTRY ===\nFilepath: lib/core.so\nSize: 2048\nType: file\n=====================\n");
    } else if (strncmp(buffer, "MALICIOUS_PAYLOAD_1", 19) == 0) {
        printf("=== ARCHIVE ENTRY ===\nFilepath: ../../../etc/shadow\nSize: 512\nType: file\n=====================\n");
    }
    return 0;
}
EOF

    gcc -o /app/extractor /app/extractor.c
    strip /app/extractor
    rm /app/extractor.c
    chmod +x /app/extractor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
