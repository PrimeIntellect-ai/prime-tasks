#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/api_requests.log
[2023-10-24 10:12:00] INFO GET /api/health HTTP/1.1 200 OK
[2023-10-24 10:15:32] ERROR GET /api/debug?query=SELECT%20*%20FROM%20configs%20WHERE%20id%20=%201%20UNION%20SELECT%201,master_key,iv%20FROM%20secrets-- HTTP/1.1 200 OK - {"error": "Debug query returned data", "data": {"master_key": "55705eae9d95c4dc8d31f9d8eb6c", "iv": "0x5A3C"}}
[2023-10-24 10:16:05] INFO GET /api/status HTTP/1.1 200 OK
EOF

    cat << 'EOF' > /home/user/legacy_encrypt.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

void encrypt_data(const char* plaintext, uint32_t iv) {
    uint32_t state = iv;
    size_t len = strlen(plaintext);
    for (size_t i = 0; i < len; i++) {
        state = (state * 0x1337 + 0x5EED) & 0xFFFFFFFF;
        uint8_t keystream_byte = (state >> 16) & 0xFF;
        printf("%02x", (uint8_t)(plaintext[i] ^ keystream_byte));
    }
    printf("\n");
}

int main(int argc, char** argv) {
    if (argc != 3) {
        printf("Usage: %s <plaintext> <iv>\n", argv[0]);
        return 1;
    }
    uint32_t iv = strtoul(argv[2], NULL, 16);
    encrypt_data(argv[1], iv);
    return 0;
}
EOF

    gcc -O2 /home/user/legacy_encrypt.c -o /home/user/legacy_encrypt
    strip /home/user/legacy_encrypt
    rm /home/user/legacy_encrypt.c

    chmod -R 777 /home/user
