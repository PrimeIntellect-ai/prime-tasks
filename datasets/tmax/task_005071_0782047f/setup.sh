#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/ws_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main() {
    int b0, b1;
    while ((b0 = fgetc(stdin)) != EOF) {
        int fin = (b0 & 0x80) != 0;
        int opcode = b0 & 0x0F;

        if (opcode != 1 && opcode != 8) {
            printf("ERROR\n");
            return 1;
        }

        b1 = fgetc(stdin);
        if (b1 == EOF) {
            printf("ERROR\n");
            return 1;
        }

        int mask = (b1 & 0x80) != 0;
        int payload_len = b1 & 0x7F;

        if (payload_len > 125) {
            printf("ERROR\n");
            return 1;
        }

        uint8_t masking_key[4];
        if (mask) {
            if (fread(masking_key, 1, 4, stdin) != 4) {
                printf("ERROR\n");
                return 1;
            }
        }

        uint8_t payload[125];
        if (payload_len > 0) {
            if (fread(payload, 1, payload_len, stdin) != (size_t)payload_len) {
                printf("ERROR\n");
                return 1;
            }
        }

        if (mask) {
            for (int i = 0; i < payload_len; i++) {
                payload[i] ^= masking_key[i % 4];
            }
        }

        if (opcode == 8) {
            printf("CLOSE\n");
            return 0;
        } else if (opcode == 1) {
            for (int i = 0; i < payload_len; i++) {
                putchar(payload[i]);
            }
            putchar('\n');
        }
    }
    return 0;
}
EOF

gcc -O2 /tmp/ws_oracle.c -o /app/ws_oracle
strip -s /app/ws_oracle
chmod +x /app/ws_oracle
rm /tmp/ws_oracle.c

useradd -m -s /bin/bash user || true
mkdir -p /home/user/src /home/user/bin

chmod -R 777 /home/user
