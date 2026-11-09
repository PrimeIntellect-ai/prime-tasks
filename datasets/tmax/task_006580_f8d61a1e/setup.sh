#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc openssl
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/access.log
192.168.1.15 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
10.0.45.22 - - [10/Oct/2023:14:02:11 -0700] "POST /rotate_trigger HTTP/1.1" 200 42
192.168.1.15 - - [10/Oct/2023:14:05:00 -0700] "GET /style.css HTTP/1.1" 200 1024
EOF

cat << 'EOF' > /home/user/legacy_crypto.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 4) {
        printf("Usage: %s <key> <input_file> <output_file>\n", argv[0]);
        return 1;
    }

    char *key = argv[1];
    int key_len = strlen(key);

    FILE *in = fopen(argv[2], "rb");
    FILE *out = fopen(argv[3], "wb");

    if (!in || !out) return 1;

    int c;
    int i = 0;
    while ((c = fgetc(in)) != EOF) {
        fputc(c ^ key[i % key_len], out);
        i++;
    }

    fclose(in);
    fclose(out);
    return 0;
}
EOF

gcc /home/user/legacy_crypto.c -o /tmp/legacy_crypto
openssl genrsa -out /home/user/old_credentials.pem 2048
cd /home/user
sha256sum old_credentials.pem > checksums.txt
/tmp/legacy_crypto "S3cr3tK!" old_credentials.pem old_credentials.enc

rm old_credentials.pem
rm /tmp/legacy_crypto

chmod -R 777 /home/user
