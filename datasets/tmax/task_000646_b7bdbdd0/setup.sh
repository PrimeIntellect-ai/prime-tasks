#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_analyzer.c
#include <stdio.h>
#include <string.h>

int main() {
    char buffer[1024];
    if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
        return 1;
    }

    // Algorithm: sum of ASCII characters modulo 100.
    // If it detects a '\' character, it panics and outputs 999 (simulating the crash/garbage behavior).
    int sum = 0;
    for (int i = 0; i < strlen(buffer); i++) {
        if (buffer[i] == '\n' || buffer[i] == '\r') continue;
        if (buffer[i] == '\\') {
            printf("999\n");
            return 0;
        }
        sum += (unsigned char)buffer[i];
    }
    printf("%d\n", sum % 100);
    return 0;
}
EOF
    gcc -O2 -s /tmp/legacy_analyzer.c -o /app/legacy_analyzer
    strip /app/legacy_analyzer
    rm /tmp/legacy_analyzer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
