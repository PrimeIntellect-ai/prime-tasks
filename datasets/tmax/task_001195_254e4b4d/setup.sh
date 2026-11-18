#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Create the oracle validator C program
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/sha.h>
#include <stdint.h>

static const char base64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
void base64_encode(const unsigned char *in, size_t in_len, char *out) {
    size_t i, j;
    for (i = 0, j = 0; i < in_len; ) {
        uint32_t octet_a = i < in_len ? (unsigned char)in[i++] : 0;
        uint32_t octet_b = i < in_len ? (unsigned char)in[i++] : 0;
        uint32_t octet_c = i < in_len ? (unsigned char)in[i++] : 0;
        uint32_t triple = (octet_a << 0x10) + (octet_b << 0x08) + octet_c;
        out[j++] = base64_table[(triple >> 3 * 6) & 0x3F];
        out[j++] = base64_table[(triple >> 2 * 6) & 0x3F];
        out[j++] = base64_table[(triple >> 1 * 6) & 0x3F];
        out[j++] = base64_table[(triple >> 0 * 6) & 0x3F];
    }
    for (int k = 0; k < (3 - in_len % 3) % 3; k++)
        out[j - 1 - k] = '=';
    out[j] = '\0';
}

void reverse_string(char *str) {
    int len = strlen(str);
    for (int i = 0; i < len / 2; i++) {
        char temp = str[i];
        str[i] = str[len - 1 - i];
        str[len - 1 - i] = temp;
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = argv[1];
    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)input, strlen(input), hash);

    char hex_hash[SHA256_DIGEST_LENGTH * 2 + 1];
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        sprintf(hex_hash + (i * 2), "%02x", hash[i]);
    }

    char combined[8192];
    snprintf(combined, sizeof(combined), "%s:%s", input, hex_hash);

    char b64[16384];
    base64_encode((unsigned char*)combined, strlen(combined), b64);

    reverse_string(b64);

    printf("KNOCK-PAYLOAD-%s\n", b64);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 /tmp/oracle.c -o /app/oracle_validator -lcrypto
    strip /app/oracle_validator
    chmod 755 /app/oracle_validator
    rm /tmp/oracle.c

    # Generate a dummy video file
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 -c:v libx264 /app/intercepted_knock.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
