#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        libc6-dev \
        openssl \
        libssl-dev \
        coreutils

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Weak custom block cipher - Decryption
// Operates on 8 bytes (64 bits) at a time
void decrypt_block(unsigned char* data) {
    unsigned char key[8] = {0x13, 0x37, 0xBE, 0xEF, 0xAA, 0xBB, 0xCC, 0xDD};
    for (int i = 0; i < 8; i++) {
        // Reverse substitution
        data[i] = (data[i] - i) ^ key[i];
    }
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <cert.pem> <token.txt>\n", argv[0]);
        return 1;
    }

    // 1. Get SHA256 fingerprint of the cert using openssl system call
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "openssl x509 -noout -fingerprint -sha256 -in %s | cut -d'=' -f2 | tr -d ':'", argv[1]);

    FILE *fp = popen(cmd, "r");
    if (!fp) return 1;

    char fingerprint_hex[65];
    if (!fgets(fingerprint_hex, sizeof(fingerprint_hex), fp)) return 1;
    pclose(fp);

    unsigned char expected_fp[8];
    for(int i = 0; i < 8; i++) {
        sscanf(&fingerprint_hex[i*2], "%2hhx", &expected_fp[i]);
    }

    // 2. Read token
    FILE *tfp = fopen(argv[2], "r");
    if (!tfp) return 1;
    char token_hex[17];
    if (!fgets(token_hex, sizeof(token_hex), tfp)) return 1;
    fclose(tfp);

    unsigned char token[8];
    for(int i = 0; i < 8; i++) {
        sscanf(&token_hex[i*2], "%2hhx", &token[i]);
    }

    // 3. Decrypt token
    decrypt_block(token);

    // 4. Compare
    if (memcmp(expected_fp, token, 8) == 0) {
        printf("VALID\n");
        return 0;
    } else {
        printf("INVALID\n");
        return 1;
    }
}
EOF

    chmod -R 777 /home/user
