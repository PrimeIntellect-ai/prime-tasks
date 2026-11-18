#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/filter_engine.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void process_packet(const char* hex) {
    if (strncmp(hex, "8899AABB", 8) == 0) {
        char secret[256];
        int j = 0;
        for(int i = 8; i < strlen(hex) && hex[i] != '\n' && hex[i] != '\0'; i += 2) {
            char byte_str[3] = {hex[i], hex[i+1], 0};
            unsigned char b = (unsigned char)strtol(byte_str, NULL, 16);
            secret[j++] = b ^ 0x5A;
        }
        secret[j] = '\0';
        // In a real binary, it would write to a socket/file. We just hide the logic.
        if (secret[0] == '\0') {
            printf("Error\n");
        }
    }
}

int main() {
    char buffer[1024];
    while (fgets(buffer, sizeof(buffer), stdin)) {
        process_packet(buffer);
    }
    return 0;
}
EOF

    gcc -O2 /tmp/filter_engine.c -o /home/user/filter_engine
    strip /home/user/filter_engine
    rm /tmp/filter_engine.c
    chmod 755 /home/user/filter_engine

    cat << 'EOF' > /home/user/capture.hex
1A2B3C4D00112233445566778899AABBCCDDEEFF
FFFFFFFF000000001111111122222222
8899AABB1F021C13160E081B0E131514051915170A161F0E1F
00112233445566778899AABBCCDDEEFF00112233
EOF
    chmod 644 /home/user/capture.hex

    chmod -R 777 /home/user
