#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc tesseract-ocr imagemagick fonts-dejavu-core
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main() {
    int32_t L;
    if (fread(&L, sizeof(int32_t), 1, stdin) != 1) {
        return 1;
    }
    if (L < 0) return 1;

    uint8_t *payload = malloc(L);
    if (!payload && L > 0) return 1;

    if (L > 0) {
        size_t read_bytes = fread(payload, 1, L, stdin);
        if (read_bytes != L) {
            free(payload);
            return 1;
        }
    }

    int32_t MAGIC_SEED = 2147483640;
    uint8_t XOR_KEY = 0x5A;

    int32_t offset = L * 2 + MAGIC_SEED;

    uint8_t key = XOR_KEY;
    if (offset < 0) {
        key = XOR_KEY ^ 0xFF;
    }

    for (int32_t i = 0; i < L; i++) {
        payload[i] ^= key;
    }

    if (L > 0) {
        fwrite(payload, 1, L, stdout);
    }
    free(payload);
    return 0;
}
EOF

gcc -O2 /tmp/oracle.c -o /app/oracle_decoder
strip /app/oracle_decoder
chmod +x /app/oracle_decoder

# Generate the config snippet image
convert -background white -fill black -font DejaVu-Sans -pointsize 36 label:"MAGIC_SEED = 2147483640\nXOR_KEY = 0x5A" /app/config_snippet.png

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
