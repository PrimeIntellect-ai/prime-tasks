#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc espeak-ng ffmpeg
    pip3 install pytest

    mkdir -p /app/bin

    # Create and compile the cipher oracle
    cat << 'EOF' > /app/cipher_oracle.c
#include <stdio.h>

int main() {
    const char key[] = "BACKUP";
    int key_len = 6;
    int c;
    int i = 0;
    while ((c = getchar()) != EOF) {
        putchar(c ^ key[i % key_len]);
        i++;
    }
    return 0;
}
EOF
    gcc -O2 /app/cipher_oracle.c -o /app/bin/cipher_oracle
    rm /app/cipher_oracle.c

    # Generate the voicemail audio
    espeak-ng -w /app/voicemail_001.wav "Warning. The primary backup gateway is offline. Please route all recovery traffic through the emergency gateway at one nine two dot one six eight dot fifty dot twenty."

    # Generate the backup payload (5MB)
    dd if=/dev/urandom of=/app/original.dat bs=1M count=5 2>/dev/null
    /app/bin/cipher_oracle < /app/original.dat > /app/backup_payload.dat
    rm /app/original.dat

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
