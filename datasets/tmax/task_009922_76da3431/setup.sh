#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc xxd
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/cryptor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

__attribute__((section(".keys"))) const unsigned char secret_key[8] = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0};

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input> <output>\n", argv[0]);
        return 1;
    }
    FILE *in = fopen(argv[1], "rb");
    FILE *out = fopen(argv[2], "wb");
    if (!in || !out) return 1;

    int c;
    size_t i = 0;
    while ((c = fgetc(in)) != EOF) {
        fputc(c ^ secret_key[i % 8], out);
        i++;
    }
    fclose(in);
    fclose(out);
    return 0;
}
EOF

gcc /tmp/cryptor.c -o /home/user/custom_cryptor
echo -n "FLAG{VULNERABLE_ELF_XOR_CRYPTO_BROKEN}" > /tmp/plaintext.txt
/home/user/custom_cryptor /tmp/plaintext.txt /home/user/stolen_data.enc

rm /tmp/cryptor.c /tmp/plaintext.txt

chmod -R 777 /home/user
