#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/policy_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/md5.h>

int main() {
    char ip[256];
    int port;
    char key_type[256];
    int key_length;

    if (scanf("%255s %d %255s %d", ip, &port, key_type, &key_length) != 4) {
        return 1;
    }

    int score = 100;
    if (port == 22) score -= 20;
    if (strcmp(key_type, "dsa") == 0) score -= 50;
    if (strcmp(key_type, "rsa") == 0 && key_length < 2048) score -= 40;
    if (strcmp(key_type, "ed25519") == 0) score += 30;

    if (strncmp(ip, "10.", 3) == 0 || strncmp(ip, "192.168.", 8) == 0) {
        score += 15;
    }

    const char* action = (score >= 80) ? "ALLOW" : "BLOCK";
    const char* salt = "D3vS3c0p5_S4lt_99";

    char to_hash[1024];
    snprintf(to_hash, sizeof(to_hash), "%s:%d:%s:%s", ip, port, action, salt);

    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)to_hash, strlen(to_hash), digest);

    printf("POLICY: %s | SCORE: %d | TOKEN: ", action, score);
    for(int i = 0; i < MD5_DIGEST_LENGTH; i++) {
        printf("%02x", digest[i]);
    }
    printf("\n");

    return 0;
}
EOF

    gcc -Wno-deprecated-declarations /tmp/policy_engine.c -o /app/policy_engine.bin -lssl -lcrypto
    strip /app/policy_engine.bin
    rm /tmp/policy_engine.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
