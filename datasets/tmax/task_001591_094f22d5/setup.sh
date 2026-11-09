#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev binutils espeak
    pip3 install pytest

    mkdir -p /app

    # Create the oracle binary
    cat << 'EOF' > /tmp/auth_module.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/md5.h>

void reverse_string(char *str) {
    int n = strlen(str);
    for (int i = 0; i < n / 2; i++) {
        char ch = str[i];
        str[i] = str[n - i - 1];
        str[n - i - 1] = ch;
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "%s", argv[1]);
    reverse_string(buffer);
    strncat(buffer, "R3d0ct0ber", sizeof(buffer) - strlen(buffer) - 1);

    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)buffer, strlen(buffer), digest);

    for(int i = 0; i < MD5_DIGEST_LENGTH; i++)
        printf("%02x", digest[i]);
    printf("\n");

    return 0;
}
EOF
    gcc -O2 /tmp/auth_module.c -o /app/auth_module -lcrypto
    strip /app/auth_module
    rm /tmp/auth_module.c

    # Create the audio fixture
    espeak -w /app/voicemail.wav "Make sure you use the salt R3d0ct0ber when generating the tokens."
    echo "Audio generated with TTS containing: 'Make sure you use the salt R3d0ct0ber when generating the tokens.'" > /app/voicemail_meta.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
