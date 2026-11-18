#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb curl
    pip3 install pytest requests flask

    mkdir -p /app
    cat << 'EOF' > /app/server.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void check_auth(const char* token, const char* date) {
    char salt[] = "S@lt123";
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "%s%s", date, salt);
    // md5 check would go here
    printf("Checking md5(YYYY-MM-DDS@lt123)\n");
}

void decrypt_payload(char* data, int len) {
    char key[] = "NETSEC2024";
    for(int i = 0; i < len; i++) {
        data[i] ^= key[i % 10];
    }
}

int main() {
    printf("Upload server running...\n");
    return 0;
}
EOF

    gcc -O2 /app/server.c -o /app/upload_server_bin
    strip -s /app/upload_server_bin
    rm /app/server.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/safe_uploads
    chmod -R 777 /home/user
    chmod -R 777 /app
