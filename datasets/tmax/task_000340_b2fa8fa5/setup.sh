#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go gcc upx-ucl curl
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /tmp/scanner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 3) return 1;
    char *port = argv[2];
    char json[256];
    if (strcmp(port, "8080") == 0) {
        strcpy(json, "{\"service\":\"http\",\"status\":\"vulnerable\",\"api_token\":\"sk_live_12345\",\"details\":\"exposed admin panel\"}");
    } else if (strcmp(port, "3306") == 0) {
        strcpy(json, "{\"service\":\"mysql\",\"password\":\"root_password_123\",\"vulnerability\":\"empty root password\"}");
    } else {
        strcpy(json, "{\"status\":\"unknown\"}");
    }

    for (int i = 0; i < strlen(json); i++) {
        printf("%02X", (unsigned char)(json[i] ^ 0x42));
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 -s /tmp/scanner.c -o /app/legacy_scanner
    upx /app/legacy_scanner || true
    chmod +x /app/legacy_scanner

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
